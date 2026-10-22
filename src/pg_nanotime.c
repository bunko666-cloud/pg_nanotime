/*
 * pg_nanotime — nanosecond-precision timestamp types for PostgreSQL.
 *
 * nanotimestamptz: 16 bytes, { int64 sec; int64 nsec; }
 *   sec  = seconds since 1970-01-01 00:00:00 UTC (floor),
 *   nsec = 0 .. 999999999 (always normalized).
 * Valid range equals PostgreSQL timestamptz: 4713-11-24 BC 00:00:00 UTC
 * up to (but excluding) 294277-01-01 00:00:00 UTC.
 *
 * nanotimestamptz8: 8 bytes, int64 nanoseconds since 1970 (pass by value),
 *   range 1677-09-21 00:12:43.145224192 .. 2262-04-11 23:47:16.854775807 UTC.
 *   Binary-compatible with bigint. Shares parsing/formatting with the 16B type.
 *
 * Requires PostgreSQL 17+.
 *
 * Copyright (c) 2026, pg_nanotime contributors. PostgreSQL License.
 */
#include "postgres.h"

#include <time.h>
#include <ctype.h>

#include "fmgr.h"
#include "access/xact.h"
#include "common/hashfn.h"
#include "executor/executor.h"
#include "libpq/pqformat.h"
#include "miscadmin.h"
#include "pgtime.h"
#include "storage/proc.h"
#include "utils/builtins.h"
#include "utils/datetime.h"
#include "utils/numeric.h"
#include "utils/timestamp.h"

#if PG_VERSION_NUM < 170000
#error "pg_nanotime requires PostgreSQL 17 or later"
#endif

#ifndef HAVE_INT128
#error "pg_nanotime requires a compiler with 128-bit integer support"
#endif

PG_MODULE_MAGIC;

typedef struct NanoTimestamp
{
	int64		sec;
	int64		nsec;
} NanoTimestamp;

#define NS_PER_SEC		INT64CONST(1000000000)
#define NS_PER_USEC		INT64CONST(1000)
/* seconds between Unix epoch (1970) and PostgreSQL epoch (2000) */
#define PG_UNIX_EPOCH_DIFF_SECS \
	((int64) (POSTGRES_EPOCH_JDATE - UNIX_EPOCH_JDATE) * SECS_PER_DAY)
/* range in Unix seconds, derived from PostgreSQL's own timestamp limits */
#define NT_MIN_SEC	(MIN_TIMESTAMP / USECS_PER_SEC + PG_UNIX_EPOCH_DIFF_SECS)
#define NT_END_SEC	(END_TIMESTAMP / USECS_PER_SEC + PG_UNIX_EPOCH_DIFF_SECS)

#define MY_LXID (MyProc->vxid.lxid)

#define PG_GETARG_NT(n)	((NanoTimestamp *) PG_GETARG_POINTER(n))

static inline int64
floordiv(int64 a, int64 b)
{
	int64		q = a / b;

	if ((a % b != 0) && ((a < 0) != (b < 0)))
		q--;
	return q;
}

static inline int64
floormod(int64 a, int64 b)
{
	int64		m = a % b;

	if (m != 0 && ((m < 0) != (b < 0)))
		m += b;
	return m;
}

static void
nt_check_range(int64 sec)
{
	if (sec < NT_MIN_SEC || sec >= NT_END_SEC)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("nanotimestamptz out of range")));
}

static NanoTimestamp *
nt_make(int64 sec, int64 nsec)
{
	NanoTimestamp *r;

	Assert(nsec >= 0 && nsec < NS_PER_SEC);
	nt_check_range(sec);
	r = (NanoTimestamp *) palloc(sizeof(NanoTimestamp));
	r->sec = sec;
	r->nsec = nsec;
	return r;
}

static inline int
nt_cmp_internal(const NanoTimestamp *a, const NanoTimestamp *b)
{
	if (a->sec != b->sec)
		return a->sec < b->sec ? -1 : 1;
	if (a->nsec != b->nsec)
		return a->nsec < b->nsec ? -1 : 1;
	return 0;
}

/* PostgreSQL timestamptz (microseconds since 2000) -> NanoTimestamp */
static NanoTimestamp *
nt_from_pg_us(TimestampTz us, int64 extra_ns)
{
	int64		sec,
				subus;

	if (TIMESTAMP_NOT_FINITE(us))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("infinite timestamps are not supported by nanotimestamptz")));
	sec = floordiv(us, USECS_PER_SEC) + PG_UNIX_EPOCH_DIFF_SECS;
	subus = floormod(us, USECS_PER_SEC);
	return nt_make(sec, subus * NS_PER_USEC + extra_ns);
}

/* NanoTimestamp -> PostgreSQL timestamptz, floor to microseconds */
static TimestampTz
nt_to_pg_us(const NanoTimestamp *t)
{
	/* within range, (sec - diff) * 1e6 cannot overflow */
	return (t->sec - PG_UNIX_EPOCH_DIFF_SECS) * USECS_PER_SEC + t->nsec / NS_PER_USEC;
}

/* --------------------------- text I/O ---------------------------------- */

/*
 * Input: anything timestamptz_in accepts, with up to 9 fractional second
 * digits. The fraction is cut out of the string, the rest is parsed by
 * PostgreSQL (time zones, BC, DateStyle all behave as for timestamptz),
 * then the nanoseconds are added back.
 */
static NanoTimestamp *ntl_from_pg_us(Timestamp us, int64 extra_ns);

static NanoTimestamp *
nt_parse_ex(const char *str, bool notz)
{
	char	   *buf = pstrdup(str);
	char	   *p;
	int64		frac_ns = 0;
	bool		found = false;
	TimestampTz us;

	/* look for HH:MM:SS.fffffffff */
	for (p = buf; *p; p++)
	{
		if (isdigit((unsigned char) p[0]) && isdigit((unsigned char) p[1]) &&
			p[2] == ':' && isdigit((unsigned char) p[3]) && isdigit((unsigned char) p[4]) &&
			p[5] == ':' && isdigit((unsigned char) p[6]) && isdigit((unsigned char) p[7]) &&
			p[8] == '.')
		{
			char	   *f = p + 9;
			char	   *e = f;
			int			ndig = 0;

			while (isdigit((unsigned char) *e))
			{
				if (ndig < 9)
					frac_ns = frac_ns * 10 + (*e - '0');
				else if (*e != '0')
					ereport(ERROR,
							(errcode(ERRCODE_INVALID_DATETIME_FORMAT),
							 errmsg("more than 9 fractional second digits in \"%s\"", str)));
				ndig++;
				e++;
			}
			if (ndig == 0)
				break;
			for (; ndig < 9; ndig++)
				frac_ns *= 10;
			memmove(p + 8, e, strlen(e) + 1);	/* drop ".fffffffff" */
			found = true;
			break;
		}
	}
	(void) found;

	us = DatumGetTimestampTz(DirectFunctionCall3(notz ? timestamp_in : timestamptz_in,
												 CStringGetDatum(buf),
												 ObjectIdGetDatum(InvalidOid),
												 Int32GetDatum(-1)));
	return notz ? ntl_from_pg_us(us, frac_ns) : nt_from_pg_us(us, frac_ns);
}

static NanoTimestamp *
nt_parse(const char *str)
{
	return nt_parse_ex(str, false);
}

PG_FUNCTION_INFO_V1(nanotimestamptz_in);
Datum
nanotimestamptz_in(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_parse(PG_GETARG_CSTRING(0)));
}

static void
append_tz(char *out, int tz)
{
	/* PostgreSQL ISO style: tz is seconds WEST of UTC */
	int			off = -tz;
	int			h,
				m,
				s;
	char		sign = off < 0 ? '-' : '+';

	if (off < 0)
		off = -off;
	h = off / SECS_PER_HOUR;
	m = (off / SECS_PER_MINUTE) % 60;
	s = off % 60;
	if (s != 0)
		sprintf(out, "%c%02d:%02d:%02d", sign, h, m, s);
	else if (m != 0)
		sprintf(out, "%c%02d:%02d", sign, h, m);
	else
		sprintf(out, "%c%02d", sign, h);
}

static char *nt_format_ex(const NanoTimestamp *t, bool notz);

static char *
nt_format(const NanoTimestamp *t)
{
	return nt_format_ex(t, false);
}

static char *
nt_format_ex(const NanoTimestamp *t, bool notz)
{
	TimestampTz whole = (t->sec - PG_UNIX_EPOCH_DIFF_SECS) * USECS_PER_SEC;
	struct pg_tm tm;
	fsec_t		fsec;
	int			tz;
	const char *tzn;
	char		tzbuf[16];
	int			year;

	if (timestamp2tm(whole, notz ? NULL : &tz, &tm, &fsec, notz ? NULL : &tzn, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("%s out of range", notz ? "nanotimestamp" : "nanotimestamptz")));
	if (notz)
		tzbuf[0] = '\0';
	else
		append_tz(tzbuf, tz);
	year = tm.tm_year > 0 ? tm.tm_year : -(tm.tm_year - 1);
	return psprintf("%04d-%02d-%02d %02d:%02d:%02d.%09lld%s%s",
							   year, tm.tm_mon, tm.tm_mday,
							   tm.tm_hour, tm.tm_min, tm.tm_sec,
							   (long long) t->nsec, tzbuf,
							   tm.tm_year > 0 ? "" : " BC");
}

PG_FUNCTION_INFO_V1(nanotimestamptz_out);
Datum
nanotimestamptz_out(PG_FUNCTION_ARGS)
{
	PG_RETURN_CSTRING(nt_format(PG_GETARG_NT(0)));
}

/* --------------------------- binary I/O -------------------------------- */

PG_FUNCTION_INFO_V1(nanotimestamptz_recv);
Datum
nanotimestamptz_recv(PG_FUNCTION_ARGS)
{
	StringInfo	b = (StringInfo) PG_GETARG_POINTER(0);
	int64		sec = pq_getmsgint64(b);
	int64		nsec = pq_getmsgint64(b);

	if (nsec < 0 || nsec >= NS_PER_SEC)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_BINARY_REPRESENTATION),
				 errmsg("invalid nanosecond field in external nanotimestamptz")));
	PG_RETURN_POINTER(nt_make(sec, nsec));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_send);
Datum
nanotimestamptz_send(PG_FUNCTION_ARGS)
{
	NanoTimestamp *t = PG_GETARG_NT(0);
	StringInfoData b;

	pq_begintypsend(&b);
	pq_sendint64(&b, t->sec);
	pq_sendint64(&b, t->nsec);
	PG_RETURN_BYTEA_P(pq_endtypsend(&b));
}

/* --------------------------- comparison -------------------------------- */

#define NT_CMP_FN(name, op) \
PG_FUNCTION_INFO_V1(name); \
Datum name(PG_FUNCTION_ARGS) \
{ PG_RETURN_BOOL(nt_cmp_internal(PG_GETARG_NT(0), PG_GETARG_NT(1)) op 0); }

NT_CMP_FN(nanotimestamptz_lt, <)
NT_CMP_FN(nanotimestamptz_le, <=)
NT_CMP_FN(nanotimestamptz_eq, ==)
NT_CMP_FN(nanotimestamptz_ne, !=)
NT_CMP_FN(nanotimestamptz_ge, >=)
NT_CMP_FN(nanotimestamptz_gt, >)

PG_FUNCTION_INFO_V1(nanotimestamptz_cmp);
Datum
nanotimestamptz_cmp(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT32(nt_cmp_internal(PG_GETARG_NT(0), PG_GETARG_NT(1)));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_hash);
Datum
nanotimestamptz_hash(PG_FUNCTION_ARGS)
{
	/* values are always normalized, so equal values have equal bytes */
	return hash_any((unsigned char *) PG_GETARG_NT(0), sizeof(NanoTimestamp));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_larger);
Datum
nanotimestamptz_larger(PG_FUNCTION_ARGS)
{
	NanoTimestamp *a = PG_GETARG_NT(0),
			   *b = PG_GETARG_NT(1);

	PG_RETURN_POINTER(nt_cmp_internal(a, b) >= 0 ? a : b);
}

PG_FUNCTION_INFO_V1(nanotimestamptz_smaller);
Datum
nanotimestamptz_smaller(PG_FUNCTION_ARGS)
{
	NanoTimestamp *a = PG_GETARG_NT(0),
			   *b = PG_GETARG_NT(1);

	PG_RETURN_POINTER(nt_cmp_internal(a, b) <= 0 ? a : b);
}

/* --------------------------- casts ------------------------------------- */

PG_FUNCTION_INFO_V1(nanotimestamptz_from_timestamptz);
Datum
nanotimestamptz_from_timestamptz(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_from_pg_us(PG_GETARG_TIMESTAMPTZ(0), 0));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_to_timestamptz);
Datum
nanotimestamptz_to_timestamptz(PG_FUNCTION_ARGS)
{
	PG_RETURN_TIMESTAMPTZ(nt_to_pg_us(PG_GETARG_NT(0)));
}

/* bigint = nanoseconds since 1970-01-01 UTC */
PG_FUNCTION_INFO_V1(nanotimestamptz_from_int8);
Datum
nanotimestamptz_from_int8(PG_FUNCTION_ARGS)
{
	int64		v = PG_GETARG_INT64(0);

	PG_RETURN_POINTER(nt_make(floordiv(v, NS_PER_SEC), floormod(v, NS_PER_SEC)));
}

static void
ns64_range_error(const char *what)
{
	if (strcmp(what, "bigint") == 0)
		ereport(ERROR,
				(errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
				 errmsg("nanotimestamptz out of range for bigint"),
				 errdetail("bigint nanoseconds since 1970 cover only 1677-09-21 00:12:43.145224192 to 2262-04-11 23:47:16.854775807 UTC.")));
	ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
			 errmsg("nanotimestamptz8 out of range"),
			 errdetail("nanotimestamptz8 covers only 1677-09-21 00:12:43.145224192 to 2262-04-11 23:47:16.854775807 UTC."),
			 errhint("Use nanotimestamptz (16 bytes) for values outside this range.")));
}

static int64
nt_to_ns64(const NanoTimestamp *t, const char *what)
{
	int64		r;
	int64		sec = t->sec,
				nsec = t->nsec;

	/* for negative sec, borrow one second so the intermediate can reach INT64_MIN */
	if (sec < 0 && nsec > 0)
	{
		sec += 1;
		nsec -= NS_PER_SEC;
	}
	if (__builtin_mul_overflow(sec, NS_PER_SEC, &r) ||
		__builtin_add_overflow(r, nsec, &r))
		ns64_range_error(what);
	return r;
}

PG_FUNCTION_INFO_V1(nanotimestamptz_to_int8);
Datum
nanotimestamptz_to_int8(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(nt_to_ns64(PG_GETARG_NT(0), "bigint"));
}

/* --------------------------- clocks ------------------------------------ */

static void
read_clock(int64 *sec, int64 *nsec)
{
	struct timespec ts;

	if (clock_gettime(CLOCK_REALTIME, &ts) != 0)
		ereport(ERROR, (errmsg("clock_gettime failed: %m")));
	*sec = (int64) ts.tv_sec;
	*nsec = (int64) ts.tv_nsec;
}

PG_FUNCTION_INFO_V1(clock_ns);
Datum
clock_ns(PG_FUNCTION_ARGS)
{
	int64		s,
				n;

	read_clock(&s, &n);
	PG_RETURN_POINTER(nt_make(s, n));
}

/*
 * now_ns() / statement_ns(): the clock is read in ExecutorStart_hook at the
 * first executor start of a transaction / of a statement, and cached keyed
 * by the local transaction id and statement_timestamp(). If the library was
 * not loaded yet when the statement started, the first call reads the clock.
 */
static ExecutorStart_hook_type prev_ExecutorStart = NULL;
static LocalTransactionId xact_lxid = InvalidLocalTransactionId;
static int64 xact_sec,
			xact_nsec;
static LocalTransactionId stmt_lxid = InvalidLocalTransactionId;
static TimestampTz stmt_key = 0;
static int64 stmt_sec,
			stmt_nsec;

static void
capture_times(void)
{
	TimestampTz sk = GetCurrentStatementStartTimestamp();

	if (MyProc == NULL)
		return;
	if (xact_lxid != MY_LXID)
	{
		read_clock(&xact_sec, &xact_nsec);
		xact_lxid = MY_LXID;
		/* first statement of a transaction shares the same reading */
		stmt_lxid = MY_LXID;
		stmt_key = sk;
		stmt_sec = xact_sec;
		stmt_nsec = xact_nsec;
	}
	else if (stmt_lxid != MY_LXID || stmt_key != sk)
	{
		read_clock(&stmt_sec, &stmt_nsec);
		stmt_lxid = MY_LXID;
		stmt_key = sk;
	}
}

static void
nt_ExecutorStart(QueryDesc *queryDesc, int eflags)
{
	capture_times();
	if (prev_ExecutorStart)
		prev_ExecutorStart(queryDesc, eflags);
	else
		standard_ExecutorStart(queryDesc, eflags);
}

PG_FUNCTION_INFO_V1(now_ns);
Datum
now_ns(PG_FUNCTION_ARGS)
{
	capture_times();
	PG_RETURN_POINTER(nt_make(xact_sec, xact_nsec));
}

PG_FUNCTION_INFO_V1(statement_ns);
Datum
statement_ns(PG_FUNCTION_ARGS)
{
	capture_times();
	PG_RETURN_POINTER(nt_make(stmt_sec, stmt_nsec));
}

void		_PG_init(void);
void
_PG_init(void)
{
	prev_ExecutorStart = ExecutorStart_hook;
	ExecutorStart_hook = nt_ExecutorStart;
}

/* ===================== nanotimestamptz8 (8 bytes) ======================= */

static inline NanoTimestamp
ns64_split(int64 v)
{
	NanoTimestamp t;

	t.sec = floordiv(v, NS_PER_SEC);
	t.nsec = floormod(v, NS_PER_SEC);
	return t;
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_in);
Datum
nanotimestamptz8_in(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(nt_to_ns64(nt_parse(PG_GETARG_CSTRING(0)), "nanotimestamptz8"));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_out);
Datum
nanotimestamptz8_out(PG_FUNCTION_ARGS)
{
	NanoTimestamp t = ns64_split(PG_GETARG_INT64(0));

	PG_RETURN_CSTRING(nt_format(&t));
}

/* 16B -> 8B (errors out of range); 8B -> 16B is always exact */
PG_FUNCTION_INFO_V1(nanotimestamptz8_from_nanotimestamptz);
Datum
nanotimestamptz8_from_nanotimestamptz(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(nt_to_ns64(PG_GETARG_NT(0), "nanotimestamptz8"));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_to_timestamptz);
Datum
nanotimestamptz8_to_timestamptz(PG_FUNCTION_ARGS)
{
	NanoTimestamp t = ns64_split(PG_GETARG_INT64(0));

	PG_RETURN_TIMESTAMPTZ(nt_to_pg_us(&t));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_from_timestamptz);
Datum
nanotimestamptz8_from_timestamptz(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(nt_to_ns64(nt_from_pg_us(PG_GETARG_TIMESTAMPTZ(0), 0), "nanotimestamptz8"));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_to_nanotimestamptz);
Datum
nanotimestamptz8_to_nanotimestamptz(PG_FUNCTION_ARGS)
{
	NanoTimestamp t = ns64_split(PG_GETARG_INT64(0));

	PG_RETURN_POINTER(nt_make(t.sec, t.nsec));
}

static Datum
ns64_from_parts(int64 sec, int64 nsec)
{
	NanoTimestamp t = {sec, nsec};

	return Int64GetDatum(nt_to_ns64(&t, "nanotimestamptz8"));
}

PG_FUNCTION_INFO_V1(clock_ns8);
Datum
clock_ns8(PG_FUNCTION_ARGS)
{
	int64		s,
				n;

	read_clock(&s, &n);
	return ns64_from_parts(s, n);
}

PG_FUNCTION_INFO_V1(now_ns8);
Datum
now_ns8(PG_FUNCTION_ARGS)
{
	capture_times();
	return ns64_from_parts(xact_sec, xact_nsec);
}

PG_FUNCTION_INFO_V1(statement_ns8);
Datum
statement_ns8(PG_FUNCTION_ARGS)
{
	capture_times();
	return ns64_from_parts(stmt_sec, stmt_nsec);
}

/* ============================ Phase 2 ==================================== */
/*
 * All arithmetic is done on int128 total nanoseconds, which can hold any
 * value or difference of the 16-byte types without overflow; results are
 * range-checked before being stored.
 */

typedef NanoTimestamp NanoInterval;	/* same layout: {sec, nsec 0..999999999} */
#define PG_GETARG_NI(n)	((NanoInterval *) PG_GETARG_POINTER(n))

#define NT_MIN_TOTAL	((int128) NT_MIN_SEC * NS_PER_SEC)
#define NT_MAX_TOTAL	((int128) NT_END_SEC * NS_PER_SEC - 1)
/* nanointerval covers every possible difference of two nanotimestamptz */
#define NI_MAX_TOTAL	(NT_MAX_TOTAL - NT_MIN_TOTAL)

static inline int128
nt_total(const NanoTimestamp *t)
{
	return (int128) t->sec * NS_PER_SEC + t->nsec;
}

static inline int128
floordiv128(int128 a, int128 b)
{
	int128		q = a / b;

	if ((a % b != 0) && ((a < 0) != (b < 0)))
		q--;
	return q;
}

static void
split128(int128 v, int64 *sec, int64 *nsec)
{
	int128		q = floordiv128(v, NS_PER_SEC);

	*sec = (int64) q;
	*nsec = (int64) (v - q * NS_PER_SEC);
}

static NanoTimestamp *
nt_from_total(int128 v)
{
	int64		s,
				n;

	if (v < NT_MIN_TOTAL || v > NT_MAX_TOTAL)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("nanotimestamptz out of range")));
	split128(v, &s, &n);
	return nt_make(s, n);
}

static int64
ns64_from_total(int128 v)
{
	if (v < PG_INT64_MIN || v > PG_INT64_MAX)
		ns64_range_error("nanotimestamptz8");
	return (int64) v;
}

static void
ni_range_error(void)
{
	ereport(ERROR,
			(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
			 errmsg("nanointerval out of range")));
}

static NanoInterval *
ni_make(int128 v)
{
	NanoInterval *r;

	if (v < -NI_MAX_TOTAL || v > NI_MAX_TOTAL)
		ni_range_error();
	r = (NanoInterval *) palloc(sizeof(NanoInterval));
	split128(v, &r->sec, &r->nsec);
	return r;
}

/* decimal string of an int128 */
static char *
int128_to_cstring(int128 v)
{
	char		buf[48];
	char	   *p = buf + sizeof(buf) - 1;
	bool		neg = v < 0;

	*p = '\0';
	do
	{
		int			d = (int) (v % 10);

		*--p = '0' + (d < 0 ? -d : d);
		v /= 10;
	} while (v != 0);
	if (neg)
		*--p = '-';
	return pstrdup(p);
}

/* ------------------------- nanointerval text I/O ------------------------- */

typedef struct
{
	const char *name;
	int64		ns;				/* 0 = unsupported calendar unit */
} NiUnit;

static const NiUnit ni_units[] = {
	{"ns", 1}, {"nsec", 1}, {"nsecs", 1}, {"nanosecond", 1}, {"nanoseconds", 1},
	{"us", 1000}, {"usec", 1000}, {"usecs", 1000}, {"microsecond", 1000}, {"microseconds", 1000},
	{"ms", 1000000}, {"msec", 1000000}, {"msecs", 1000000}, {"millisecond", 1000000}, {"milliseconds", 1000000},
	{"s", NS_PER_SEC}, {"sec", NS_PER_SEC}, {"secs", NS_PER_SEC}, {"second", NS_PER_SEC}, {"seconds", NS_PER_SEC},
	{"m", 60 * NS_PER_SEC}, {"min", 60 * NS_PER_SEC}, {"mins", 60 * NS_PER_SEC}, {"minute", 60 * NS_PER_SEC}, {"minutes", 60 * NS_PER_SEC},
	{"h", 3600 * NS_PER_SEC}, {"hr", 3600 * NS_PER_SEC}, {"hrs", 3600 * NS_PER_SEC}, {"hour", 3600 * NS_PER_SEC}, {"hours", 3600 * NS_PER_SEC},
	{"d", 86400 * NS_PER_SEC}, {"day", 86400 * NS_PER_SEC}, {"days", 86400 * NS_PER_SEC},
	{"w", 7 * 86400 * NS_PER_SEC}, {"week", 7 * 86400 * NS_PER_SEC}, {"weeks", 7 * 86400 * NS_PER_SEC},
	{"mon", 0}, {"mons", 0}, {"month", 0}, {"months", 0},
	{"y", 0}, {"yr", 0}, {"yrs", 0}, {"year", 0}, {"years", 0},
	{"decade", 0}, {"decades", 0}, {"century", 0}, {"centuries", 0},
	{"millennium", 0}, {"millennia", 0}, {"millenniums", 0},
	{NULL, 0}
};

static void
ni_syntax_error(const char *str)
{
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_DATETIME_FORMAT),
			 errmsg("invalid input syntax for type nanointerval: \"%s\"", str)));
}

static void
ni_calendar_error(const char *str)
{
	ereport(ERROR,
			(errcode(ERRCODE_INVALID_DATETIME_FORMAT),
			 errmsg("nanointerval does not support months or years: \"%s\"", str),
			 errhint("nanointerval stores a fixed number of nanoseconds; use interval for calendar units.")));
}

/* parse digits [. digits]; returns false if no digits */
static bool
ni_parse_number(const char **pp, int128 *ipart, int128 *fpart, int *fdig, const char *str)
{
	const char *p = *pp;
	bool		any = false;

	*ipart = 0;
	*fpart = 0;
	*fdig = 0;
	while (isdigit((unsigned char) *p))
	{
		if (*ipart > (int128) 1000000000000000000LL * 100000)	/* > 1e23: beyond any range */
			ni_range_error();
		*ipart = *ipart * 10 + (*p - '0');
		p++;
		any = true;
	}
	if (*p == '.')
	{
		p++;
		while (isdigit((unsigned char) *p))
		{
			if (*fdig < 18)
			{
				*fpart = *fpart * 10 + (*p - '0');
				(*fdig)++;
			}
			else if (*p != '0')
				ereport(ERROR,
						(errcode(ERRCODE_INVALID_DATETIME_FORMAT),
						 errmsg("too many fractional digits in nanointerval input: \"%s\"", str)));
			p++;
			any = true;
		}
	}
	*pp = p;
	return any;
}

static int128
ni_scale(int128 ipart, int128 fpart, int fdig, int64 unit, const char *str)
{
	int128		v,
				f,
				pow10 = 1;
	int			i;

	if (__builtin_mul_overflow(ipart, (int128) unit, &v))
		ni_range_error();
	for (i = 0; i < fdig; i++)
		pow10 *= 10;
	f = fpart * unit;			/* fpart < 1e18, unit < 1e15: fits */
	if (f % pow10 != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_DATETIME_FORMAT),
				 errmsg("nanointerval input is more precise than 1 nanosecond: \"%s\"", str)));
	v += f / pow10;
	if (v > NI_MAX_TOTAL)
		ni_range_error();
	return v;
}

static int128
ni_parse_iso(const char *p, const char *str)
{
	int128		total = 0;
	bool		in_time = false;
	bool		any = false;

	p++;						/* skip P */
	while (*p)
	{
		int128		ip,
					fp;
		int			fd;
		int64		unit;
		bool		neg = false;

		if (*p == 'T' || *p == 't')
		{
			in_time = true;
			p++;
			continue;
		}
		if (*p == '-')
		{
			neg = true;
			p++;
		}
		else if (*p == '+')
			p++;
		if (!ni_parse_number(&p, &ip, &fp, &fd, str))
			ni_syntax_error(str);
		switch (toupper((unsigned char) *p))
		{
			case 'Y':
				ni_calendar_error(str);
				break;
			case 'M':
				if (!in_time)
					ni_calendar_error(str);
				unit = 60 * NS_PER_SEC;
				break;
			case 'W':
				unit = 7 * 86400 * NS_PER_SEC;
				break;
			case 'D':
				unit = 86400 * NS_PER_SEC;
				break;
			case 'H':
				unit = 3600 * NS_PER_SEC;
				break;
			case 'S':
				unit = NS_PER_SEC;
				break;
			default:
				ni_syntax_error(str);
				unit = 0;
		}
		if ((toupper((unsigned char) *p) == 'H' || toupper((unsigned char) *p) == 'S') && !in_time)
			ni_syntax_error(str);
		p++;
		total += neg ? -ni_scale(ip, fp, fd, unit, str) : ni_scale(ip, fp, fd, unit, str);
		any = true;
	}
	if (!any)
		ni_syntax_error(str);
	return total;
}

static int128
ni_parse(const char *str)
{
	const char *p = str;
	int128		total = 0;
	bool		any = false;
	bool		ago = false;

	while (isspace((unsigned char) *p))
		p++;
	if (*p == '@')
		p++;
	while (isspace((unsigned char) *p))
		p++;
	if (*p == 'P' || *p == 'p')
		total = ni_parse_iso(p, str), any = true, p += strlen(p);

	while (*p)
	{
		int128		ip,
					fp,
					v;
		int			fd;
		bool		neg = false;
		char		word[32];
		int			wl = 0;

		while (isspace((unsigned char) *p))
			p++;
		if (!*p)
			break;
		if (ago)
			ni_syntax_error(str);
		if (pg_strncasecmp(p, "ago", 3) == 0 && !isalnum((unsigned char) p[3]))
		{
			if (!any)
				ni_syntax_error(str);
			ago = true;
			p += 3;
			continue;
		}
		if (*p == '-')
		{
			neg = true;
			p++;
		}
		else if (*p == '+')
			p++;
		if (!ni_parse_number(&p, &ip, &fp, &fd, str))
			ni_syntax_error(str);
		if (*p == ':')
		{
			/* [-]HH:MM[:SS[.f]] */
			int128		mi,
						se = 0,
						sf = 0,
						dummy;
			int			sd = 0,
						dd;

			if (fd != 0)
				ni_syntax_error(str);
			p++;
			if (!isdigit((unsigned char) *p) || !ni_parse_number(&p, &mi, &dummy, &dd, str) || dd != 0 || mi > 59)
				ni_syntax_error(str);
			if (*p == ':')
			{
				p++;
				if (!isdigit((unsigned char) *p) || !ni_parse_number(&p, &se, &sf, &sd, str) || se > 59)
					ni_syntax_error(str);
			}
			v = ni_scale(ip, 0, 0, 3600 * NS_PER_SEC, str) + mi * 60 * NS_PER_SEC +
				ni_scale(se, sf, sd, NS_PER_SEC, str);
		}
		else
		{
			const NiUnit *u;
			int64		unit = -1;

			while (isspace((unsigned char) *p))
				p++;
			while (isalpha((unsigned char) *p) && wl < 31)
				word[wl++] = pg_tolower((unsigned char) *p++);
			word[wl] = '\0';
			if (isalpha((unsigned char) *p))
				ni_syntax_error(str);
			if (wl == 0 || strcmp(word, "ago") == 0)
			{
				/* bare number = seconds (as in PostgreSQL) */
				unit = NS_PER_SEC;
				if (wl)
					ago = true;
			}
			else
			{
				for (u = ni_units; u->name; u++)
					if (strcmp(u->name, word) == 0)
					{
						if (u->ns == 0)
							ni_calendar_error(str);
						unit = u->ns;
						break;
					}
				if (unit < 0)
					ni_syntax_error(str);
			}
			v = ni_scale(ip, fp, fd, unit, str);
		}
		total += neg ? -v : v;
		if (total > NI_MAX_TOTAL || total < -NI_MAX_TOTAL)
			ni_range_error();
		any = true;
	}
	if (!any)
		ni_syntax_error(str);
	return ago ? -total : total;
}

PG_FUNCTION_INFO_V1(nanointerval_in);
Datum
nanointerval_in(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ni_make(ni_parse(PG_GETARG_CSTRING(0))));
}

PG_FUNCTION_INFO_V1(nanointerval_out);
Datum
nanointerval_out(PG_FUNCTION_ARGS)
{
	int128		v = nt_total(PG_GETARG_NI(0));
	bool		neg = v < 0;
	int128		a = neg ? -v : v;
	int128		days = a / ((int128) 86400 * NS_PER_SEC);
	int64		rem = (int64) (a % ((int128) 86400 * NS_PER_SEC));
	int64		h = rem / (3600 * NS_PER_SEC),
				m = rem / (60 * NS_PER_SEC) % 60,
				sec = rem / NS_PER_SEC % 60,
				ns = rem % NS_PER_SEC;
	const char *sg = neg ? "-" : "";
	char	   *tpart = psprintf("%s%02lld:%02lld:%02lld.%09lld", sg,
								 (long long) h, (long long) m, (long long) sec, (long long) ns);

	if (days == 0)
		PG_RETURN_CSTRING(tpart);
	if (rem == 0)
		PG_RETURN_CSTRING(psprintf("%s%s day%s", sg, int128_to_cstring(days), days == 1 ? "" : "s"));
	PG_RETURN_CSTRING(psprintf("%s%s day%s %s", sg, int128_to_cstring(days),
							   days == 1 ? "" : "s", tpart));
}

PG_FUNCTION_INFO_V1(nanointerval_recv);
Datum
nanointerval_recv(PG_FUNCTION_ARGS)
{
	StringInfo	b = (StringInfo) PG_GETARG_POINTER(0);
	int64		sec = pq_getmsgint64(b);
	int64		nsec = pq_getmsgint64(b);

	if (nsec < 0 || nsec >= NS_PER_SEC)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_BINARY_REPRESENTATION),
				 errmsg("invalid nanosecond field in external nanointerval")));
	PG_RETURN_POINTER(ni_make((int128) sec * NS_PER_SEC + nsec));
}

/* ------------------------- nanointerval arithmetic ----------------------- */

PG_FUNCTION_INFO_V1(nanointerval_um);
Datum
nanointerval_um(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ni_make(-nt_total(PG_GETARG_NI(0))));
}

PG_FUNCTION_INFO_V1(nanointerval_pl);
Datum
nanointerval_pl(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ni_make(nt_total(PG_GETARG_NI(0)) + nt_total(PG_GETARG_NI(1))));
}

PG_FUNCTION_INFO_V1(nanointerval_mi);
Datum
nanointerval_mi(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ni_make(nt_total(PG_GETARG_NI(0)) - nt_total(PG_GETARG_NI(1))));
}

PG_FUNCTION_INFO_V1(nanointerval_mul_int8);
Datum
nanointerval_mul_int8(PG_FUNCTION_ARGS)
{
	int128		r;

	if (__builtin_mul_overflow(nt_total(PG_GETARG_NI(0)), (int128) PG_GETARG_INT64(1), &r))
		ni_range_error();
	PG_RETURN_POINTER(ni_make(r));
}

/* division rounds half away from zero, like numeric round() */
PG_FUNCTION_INFO_V1(nanointerval_div_int8);
Datum
nanointerval_div_int8(PG_FUNCTION_ARGS)
{
	int128		a = nt_total(PG_GETARG_NI(0));
	int128		b = PG_GETARG_INT64(1);
	int128		q,
				r;

	if (b == 0)
		ereport(ERROR, (errcode(ERRCODE_DIVISION_BY_ZERO), errmsg("division by zero")));
	q = a / b;
	r = a % b;
	if (r != 0 && 2 * (r < 0 ? -r : r) >= (b < 0 ? -b : b))
		q += ((a < 0) != (b < 0)) ? -1 : 1;
	PG_RETURN_POINTER(ni_make(q));
}

/* total nanoseconds as numeric, and back (numeric is rounded first) */
PG_FUNCTION_INFO_V1(nanointerval_to_ns_numeric);
Datum
nanointerval_to_ns_numeric(PG_FUNCTION_ARGS)
{
	return DirectFunctionCall3(numeric_in,
							   CStringGetDatum(int128_to_cstring(nt_total(PG_GETARG_NI(0)))),
							   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
}

PG_FUNCTION_INFO_V1(nanointerval_from_ns_numeric);
Datum
nanointerval_from_ns_numeric(PG_FUNCTION_ARGS)
{
	Datum		rounded = DirectFunctionCall2(numeric_round, PG_GETARG_DATUM(0), Int32GetDatum(0));
	char	   *s = DatumGetCString(DirectFunctionCall1(numeric_out, rounded));
	char	   *p = s;
	bool		neg = false;
	int128		v = 0;

	if (*p == '-')
		neg = true, p++;
	if (strcmp(p, "NaN") == 0 || strcmp(p, "Infinity") == 0)
		ni_range_error();
	for (; isdigit((unsigned char) *p); p++)
	{
		v = v * 10 + (*p - '0');
		if (v > NI_MAX_TOTAL)
			ni_range_error();
	}
	PG_RETURN_POINTER(ni_make(neg ? -v : v));
}

/* ------------------------- nanointerval casts ---------------------------- */

PG_FUNCTION_INFO_V1(nanointerval_from_interval);
Datum
nanointerval_from_interval(PG_FUNCTION_ARGS)
{
	Interval   *iv = PG_GETARG_INTERVAL_P(0);

	if (INTERVAL_NOT_FINITE(iv))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("infinite intervals are not supported by nanointerval")));
	if (iv->month != 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("cannot convert interval with months or years to nanointerval"),
				 errdetail("nanointerval stores a fixed number of nanoseconds; days are converted as 24 hours, but months have no fixed length.")));
	PG_RETURN_POINTER(ni_make((int128) iv->day * 86400 * NS_PER_SEC + (int128) iv->time * NS_PER_USEC));
}

PG_FUNCTION_INFO_V1(nanointerval_to_interval);
Datum
nanointerval_to_interval(PG_FUNCTION_ARGS)
{
	int128		us = floordiv128(nt_total(PG_GETARG_NI(0)), NS_PER_USEC);
	Interval   *r;

	if (us < PG_INT64_MIN || us > PG_INT64_MAX)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("nanointerval out of range for interval")));
	r = (Interval *) palloc(sizeof(Interval));
	r->month = 0;
	r->day = 0;
	r->time = (int64) us;
	PG_RETURN_INTERVAL_P(r);
}

PG_FUNCTION_INFO_V1(nanointerval_from_int8);
Datum
nanointerval_from_int8(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ni_make(PG_GETARG_INT64(0)));
}

PG_FUNCTION_INFO_V1(nanointerval_to_int8);
Datum
nanointerval_to_int8(PG_FUNCTION_ARGS)
{
	int128		v = nt_total(PG_GETARG_NI(0));

	if (v < PG_INT64_MIN || v > PG_INT64_MAX)
		ereport(ERROR,
				(errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
				 errmsg("nanointerval out of range for bigint")));
	PG_RETURN_INT64((int64) v);
}

/* ------------------------- timestamp arithmetic -------------------------- */

static inline NanoTimestamp
nt8_struct(int64 v)
{
	return ns64_split(v);
}

PG_FUNCTION_INFO_V1(nanotimestamptz_mi);
Datum
nanotimestamptz_mi(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ni_make(nt_total(PG_GETARG_NT(0)) - nt_total(PG_GETARG_NT(1))));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_mi);
Datum
nanotimestamptz8_mi(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ni_make((int128) PG_GETARG_INT64(0) - PG_GETARG_INT64(1)));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_pl_nanointerval);
Datum
nanotimestamptz_pl_nanointerval(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_from_total(nt_total(PG_GETARG_NT(0)) + nt_total(PG_GETARG_NI(1))));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_mi_nanointerval);
Datum
nanotimestamptz_mi_nanointerval(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_from_total(nt_total(PG_GETARG_NT(0)) - nt_total(PG_GETARG_NI(1))));
}

PG_FUNCTION_INFO_V1(nanointerval_pl_nanotimestamptz);
Datum
nanointerval_pl_nanotimestamptz(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_from_total(nt_total(PG_GETARG_NI(0)) + nt_total(PG_GETARG_NT(1))));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_pl_nanointerval);
Datum
nanotimestamptz8_pl_nanointerval(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(ns64_from_total((int128) PG_GETARG_INT64(0) + nt_total(PG_GETARG_NI(1))));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_mi_nanointerval);
Datum
nanotimestamptz8_mi_nanointerval(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(ns64_from_total((int128) PG_GETARG_INT64(0) - nt_total(PG_GETARG_NI(1))));
}

PG_FUNCTION_INFO_V1(nanointerval_pl_nanotimestamptz8);
Datum
nanointerval_pl_nanotimestamptz8(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(ns64_from_total(nt_total(PG_GETARG_NI(0)) + (int128) PG_GETARG_INT64(1)));
}

/*
 * ts +/- PostgreSQL interval: the microsecond part goes through PostgreSQL's
 * own timestamptz +/- interval (calendar months/days in the session time
 * zone, DST-aware, same errors), the sub-microsecond remainder is kept.
 */
static NanoTimestamp *
nt_interval_op(const NanoTimestamp *t, Interval *iv, bool minus)
{
	TimestampTz us = nt_to_pg_us(t);
	int64		rem = t->nsec % NS_PER_USEC;
	TimestampTz r;

	r = DatumGetTimestampTz(DirectFunctionCall2(minus ? timestamptz_mi_interval : timestamptz_pl_interval,
												TimestampTzGetDatum(us), IntervalPGetDatum(iv)));
	return nt_from_pg_us(r, rem);
}

PG_FUNCTION_INFO_V1(nanotimestamptz_pl_interval);
Datum
nanotimestamptz_pl_interval(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_interval_op(PG_GETARG_NT(0), PG_GETARG_INTERVAL_P(1), false));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_mi_interval);
Datum
nanotimestamptz_mi_interval(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_interval_op(PG_GETARG_NT(0), PG_GETARG_INTERVAL_P(1), true));
}

PG_FUNCTION_INFO_V1(interval_pl_nanotimestamptz);
Datum
interval_pl_nanotimestamptz(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_interval_op(PG_GETARG_NT(1), PG_GETARG_INTERVAL_P(0), false));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_pl_interval);
Datum
nanotimestamptz8_pl_interval(PG_FUNCTION_ARGS)
{
	NanoTimestamp t = nt8_struct(PG_GETARG_INT64(0));

	PG_RETURN_INT64(nt_to_ns64(nt_interval_op(&t, PG_GETARG_INTERVAL_P(1), false), "nanotimestamptz8"));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_mi_interval);
Datum
nanotimestamptz8_mi_interval(PG_FUNCTION_ARGS)
{
	NanoTimestamp t = nt8_struct(PG_GETARG_INT64(0));

	PG_RETURN_INT64(nt_to_ns64(nt_interval_op(&t, PG_GETARG_INTERVAL_P(1), true), "nanotimestamptz8"));
}

PG_FUNCTION_INFO_V1(interval_pl_nanotimestamptz8);
Datum
interval_pl_nanotimestamptz8(PG_FUNCTION_ARGS)
{
	NanoTimestamp t = nt8_struct(PG_GETARG_INT64(1));

	PG_RETURN_INT64(nt_to_ns64(nt_interval_op(&t, PG_GETARG_INTERVAL_P(0), false), "nanotimestamptz8"));
}

/* ------------------------- time_bucket_ns -------------------------------- */

/*
 * bucket = origin + floor((ts - origin) / width) * width.
 * A bucket that would start before the type's minimum is clamped to the
 * minimum (the value itself is always valid, only its bucket's start is not
 * representable); the end side cannot overflow because bucket <= ts.
 */
static int128
bucket128(int128 width, int128 ts, int128 origin, int128 minv)
{
	int128		b;

	if (width <= 0)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_PARAMETER_VALUE),
				 errmsg("time_bucket_ns width must be greater than zero")));
	b = origin + floordiv128(ts - origin, width) * width;
	return b < minv ? minv : b;
}

PG_FUNCTION_INFO_V1(time_bucket_ns);
Datum
time_bucket_ns(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_from_total(bucket128(nt_total(PG_GETARG_NI(0)), nt_total(PG_GETARG_NT(1)),
											  nt_total(PG_GETARG_NT(2)), NT_MIN_TOTAL)));
}

PG_FUNCTION_INFO_V1(time_bucket_ns8);
Datum
time_bucket_ns8(PG_FUNCTION_ARGS)
{
	PG_RETURN_INT64(ns64_from_total(bucket128(nt_total(PG_GETARG_NI(0)), PG_GETARG_INT64(1),
											  PG_GETARG_INT64(2), PG_INT64_MIN)));
}

/* ------------------------- date_trunc / extract -------------------------- */

static bool
is_ns_unit(text *unit)
{
	char	   *u = text_to_cstring(unit);

	return pg_strcasecmp(u, "nanosecond") == 0 || pg_strcasecmp(u, "nanoseconds") == 0 ||
		pg_strcasecmp(u, "ns") == 0;
}

static NanoTimestamp *
nt_trunc(text *unit, const NanoTimestamp *t, text *zone)
{
	Datum		r;

	if (is_ns_unit(unit))
		return nt_make(t->sec, t->nsec);
	if (zone)
		r = DirectFunctionCall3(timestamptz_trunc_zone, PointerGetDatum(unit),
								TimestampTzGetDatum(nt_to_pg_us(t)), PointerGetDatum(zone));
	else
		r = DirectFunctionCall2(timestamptz_trunc, PointerGetDatum(unit),
								TimestampTzGetDatum(nt_to_pg_us(t)));
	return nt_from_pg_us(DatumGetTimestampTz(r), 0);
}

PG_FUNCTION_INFO_V1(nanotimestamptz_trunc);
Datum
nanotimestamptz_trunc(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_trunc(PG_GETARG_TEXT_PP(0), PG_GETARG_NT(1),
							   PG_NARGS() > 2 ? PG_GETARG_TEXT_PP(2) : NULL));
}

PG_FUNCTION_INFO_V1(nanotimestamptz8_trunc);
Datum
nanotimestamptz8_trunc(PG_FUNCTION_ARGS)
{
	NanoTimestamp t = nt8_struct(PG_GETARG_INT64(1));

	PG_RETURN_INT64(nt_to_ns64(nt_trunc(PG_GETARG_TEXT_PP(0), &t,
										PG_NARGS() > 2 ? PG_GETARG_TEXT_PP(2) : NULL), "nanotimestamptz8"));
}

static Datum
numeric_from_cstring(const char *s)
{
	return DirectFunctionCall3(numeric_in, CStringGetDatum(s),
							   ObjectIdGetDatum(InvalidOid), Int32GetDatum(-1));
}

static char *
fixed9(int128 total)
{
	bool		neg = total < 0;
	int128		a = neg ? -total : total;

	return psprintf("%s%s.%09lld", neg ? "-" : "", int128_to_cstring(a / NS_PER_SEC),
					(long long) (a % NS_PER_SEC));
}

/* field "seconds within the minute" scaled; sec_in_min is 0..60 */
static Datum
sub_minute_field(const char *f, int64 sec_in_min, int64 nsec, bool *handled)
{
	*handled = true;
	if (!pg_strcasecmp(f, "nanosecond") || !pg_strcasecmp(f, "nanoseconds"))
		return NumericGetDatum(int64_to_numeric(sec_in_min * NS_PER_SEC + nsec));
	if (!pg_strcasecmp(f, "microsecond") || !pg_strcasecmp(f, "microseconds"))
		return numeric_from_cstring(psprintf("%lld.%03lld", (long long) (sec_in_min * 1000000 + nsec / 1000),
											 (long long) (nsec % 1000)));
	if (!pg_strcasecmp(f, "millisecond") || !pg_strcasecmp(f, "milliseconds"))
		return numeric_from_cstring(psprintf("%lld.%06lld", (long long) (sec_in_min * 1000 + nsec / 1000000),
											 (long long) (nsec % 1000000)));
	if (!pg_strcasecmp(f, "second") || !pg_strcasecmp(f, "seconds"))
		return numeric_from_cstring(psprintf("%lld.%09lld", (long long) sec_in_min, (long long) nsec));
	*handled = false;
	return (Datum) 0;
}

PG_FUNCTION_INFO_V1(nanotimestamptz_extract);
Datum
nanotimestamptz_extract(PG_FUNCTION_ARGS)
{
	text	   *field = PG_GETARG_TEXT_PP(0);
	NanoTimestamp *t = PG_GETARG_NT(1);
	char	   *f = text_to_cstring(field);
	bool		handled;
	Datum		r;
	struct pg_tm tm;
	fsec_t		fsec;
	int			tz;

	if (!pg_strcasecmp(f, "epoch"))
		return numeric_from_cstring(fixed9(nt_total(t)));
	if (timestamp2tm((t->sec - PG_UNIX_EPOCH_DIFF_SECS) * USECS_PER_SEC, &tz, &tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR, (errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE), errmsg("nanotimestamptz out of range")));
	r = sub_minute_field(f, tm.tm_sec, t->nsec, &handled);
	if (handled)
		return r;
	return DirectFunctionCall2(extract_timestamptz, PointerGetDatum(field),
							   TimestampTzGetDatum(nt_to_pg_us(t)));
}

PG_FUNCTION_INFO_V1(nanointerval_extract);
Datum
nanointerval_extract(PG_FUNCTION_ARGS)
{
	char	   *f = text_to_cstring(PG_GETARG_TEXT_PP(0));
	int128		v = nt_total(PG_GETARG_NI(1));
	bool		neg = v < 0;
	int128		a = neg ? -v : v;
	int128		days = a / ((int128) 86400 * NS_PER_SEC);
	int64		rem = (int64) (a % ((int128) 86400 * NS_PER_SEC));
	int128		out;
	bool		handled;
	Datum		r;

	if (!pg_strcasecmp(f, "epoch"))
		return numeric_from_cstring(fixed9(v));
	if (!pg_strcasecmp(f, "day") || !pg_strcasecmp(f, "days"))
		out = days;
	else if (!pg_strcasecmp(f, "hour") || !pg_strcasecmp(f, "hours"))
		out = rem / (3600 * NS_PER_SEC);
	else if (!pg_strcasecmp(f, "minute") || !pg_strcasecmp(f, "minutes"))
		out = rem / (60 * NS_PER_SEC) % 60;
	else
	{
		r = sub_minute_field(f, rem / NS_PER_SEC % 60, rem % NS_PER_SEC, &handled);
		if (!handled)
			ereport(ERROR,
					(errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
					 errmsg("unit \"%s\" not supported for type nanointerval", f)));
		return neg ? DirectFunctionCall1(numeric_uminus, r) : r;
	}
	return numeric_from_cstring(int128_to_cstring(neg ? -out : out));
}

/* ===================== nanotimestamp (without time zone) ================== */
/*
 * Same 16-byte layout as nanotimestamptz; sec counts wall-clock seconds from
 * 1970-01-01 00:00:00 (no zone), exactly as PostgreSQL's timestamp stores
 * wall-clock microseconds. Comparison, hashing, send and ts - ts reuse the
 * nanotimestamptz C functions (identical math). Range equals timestamp.
 */

static void
ntl_check_total(int128 v)
{
	if (v < NT_MIN_TOTAL || v > NT_MAX_TOTAL)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("nanotimestamp out of range")));
}

static NanoTimestamp *
ntl_from_total(int128 v)
{
	ntl_check_total(v);
	return nt_from_total(v);
}

/* Timestamp (wall-clock us since 2000) -> nanotimestamp */
static NanoTimestamp *
ntl_from_pg_us(Timestamp us, int64 extra_ns)
{
	if (TIMESTAMP_NOT_FINITE(us))
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("infinite timestamps are not supported by nanotimestamp")));
	return ntl_from_total(((int128) us + (int128) PG_UNIX_EPOCH_DIFF_SECS * USECS_PER_SEC) * NS_PER_USEC + extra_ns);
}

PG_FUNCTION_INFO_V1(nanotimestamp_in);
Datum
nanotimestamp_in(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(nt_parse_ex(PG_GETARG_CSTRING(0), true));
}

PG_FUNCTION_INFO_V1(nanotimestamp_out);
Datum
nanotimestamp_out(PG_FUNCTION_ARGS)
{
	PG_RETURN_CSTRING(nt_format_ex(PG_GETARG_NT(0), true));
}

PG_FUNCTION_INFO_V1(nanotimestamp_recv);
Datum
nanotimestamp_recv(PG_FUNCTION_ARGS)
{
	StringInfo	buf = (StringInfo) PG_GETARG_POINTER(0);
	int64		sec = pq_getmsgint64(buf);
	int64		nsec = pq_getmsgint64(buf);

	if (nsec < 0 || nsec >= NS_PER_SEC)
		ereport(ERROR,
				(errcode(ERRCODE_INVALID_BINARY_REPRESENTATION),
				 errmsg("invalid nanoseconds in external nanotimestamp value")));
	if (sec < NT_MIN_SEC || sec >= NT_END_SEC)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("nanotimestamp out of range")));
	PG_RETURN_POINTER(nt_make(sec, nsec));
}

/* casts */
PG_FUNCTION_INFO_V1(nanotimestamp_from_timestamp);
Datum
nanotimestamp_from_timestamp(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_from_pg_us(PG_GETARG_TIMESTAMP(0), 0));
}

PG_FUNCTION_INFO_V1(nanotimestamp_to_timestamp);
Datum
nanotimestamp_to_timestamp(PG_FUNCTION_ARGS)
{
	PG_RETURN_TIMESTAMP(nt_to_pg_us(PG_GETARG_NT(0)));	/* floor to us */
}

PG_FUNCTION_INFO_V1(nanotimestamp_from_date);
Datum
nanotimestamp_from_date(PG_FUNCTION_ARGS)
{
	Timestamp	us = DatumGetTimestamp(DirectFunctionCall1(date_timestamp, PG_GETARG_DATUM(0)));

	PG_RETURN_POINTER(ntl_from_pg_us(us, 0));
}

PG_FUNCTION_INFO_V1(nanotimestamp_to_date);
Datum
nanotimestamp_to_date(PG_FUNCTION_ARGS)
{
	return DirectFunctionCall1(timestamp_date, TimestampGetDatum(nt_to_pg_us(PG_GETARG_NT(0))));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_to_date);
Datum
nanotimestamptz_to_date(PG_FUNCTION_ARGS)
{
	return DirectFunctionCall1(timestamptz_date, TimestampTzGetDatum(nt_to_pg_us(PG_GETARG_NT(0))));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_from_date);
Datum
nanotimestamptz_from_date(PG_FUNCTION_ARGS)
{
	TimestampTz us = DatumGetTimestampTz(DirectFunctionCall1(date_timestamptz, PG_GETARG_DATUM(0)));

	PG_RETURN_POINTER(nt_from_pg_us(us, 0));
}

/*
 * nanotimestamp <-> nanotimestamptz through the session time zone. Zone
 * offsets are whole seconds, so the sub-microsecond part carries over.
 */
PG_FUNCTION_INFO_V1(nanotimestamp_to_nanotimestamptz);
Datum
nanotimestamp_to_nanotimestamptz(PG_FUNCTION_ARGS)
{
	NanoTimestamp *t = PG_GETARG_NT(0);
	TimestampTz r = DatumGetTimestampTz(DirectFunctionCall1(timestamp_timestamptz,
															 TimestampGetDatum(nt_to_pg_us(t))));

	PG_RETURN_POINTER(nt_from_pg_us(r, t->nsec % NS_PER_USEC));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_to_nanotimestamp);
Datum
nanotimestamptz_to_nanotimestamp(PG_FUNCTION_ARGS)
{
	NanoTimestamp *t = PG_GETARG_NT(0);
	Timestamp	r = DatumGetTimestamp(DirectFunctionCall1(timestamptz_timestamp,
														  TimestampTzGetDatum(nt_to_pg_us(t))));

	PG_RETURN_POINTER(ntl_from_pg_us(r, t->nsec % NS_PER_USEC));
}

/* AT TIME ZONE equivalents: timezone(zone, nanotimestamp) -> nanotimestamptz and back */
PG_FUNCTION_INFO_V1(nanotimestamp_zone);
Datum
nanotimestamp_zone(PG_FUNCTION_ARGS)
{
	NanoTimestamp *t = PG_GETARG_NT(1);
	TimestampTz r = DatumGetTimestampTz(DirectFunctionCall2(timestamp_zone, PG_GETARG_DATUM(0),
															 TimestampGetDatum(nt_to_pg_us(t))));

	PG_RETURN_POINTER(nt_from_pg_us(r, t->nsec % NS_PER_USEC));
}

PG_FUNCTION_INFO_V1(nanotimestamptz_zone);
Datum
nanotimestamptz_zone(PG_FUNCTION_ARGS)
{
	NanoTimestamp *t = PG_GETARG_NT(1);
	Timestamp	r = DatumGetTimestamp(DirectFunctionCall2(timestamptz_zone, PG_GETARG_DATUM(0),
														  TimestampTzGetDatum(nt_to_pg_us(t))));

	PG_RETURN_POINTER(ntl_from_pg_us(r, t->nsec % NS_PER_USEC));
}

PG_FUNCTION_INFO_V1(nanotimestamp_from_int8);
Datum
nanotimestamp_from_int8(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_from_total(PG_GETARG_INT64(0)));
}

PG_FUNCTION_INFO_V1(nanotimestamp_to_int8);
Datum
nanotimestamp_to_int8(PG_FUNCTION_ARGS)
{
	int128		v = nt_total(PG_GETARG_NT(0));

	if (v < PG_INT64_MIN || v > PG_INT64_MAX)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("nanotimestamp out of range for bigint")));
	PG_RETURN_INT64((int64) v);
}

/* arithmetic */
PG_FUNCTION_INFO_V1(nanotimestamp_pl_nanointerval);
Datum
nanotimestamp_pl_nanointerval(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_from_total(nt_total(PG_GETARG_NT(0)) + nt_total(PG_GETARG_NI(1))));
}

PG_FUNCTION_INFO_V1(nanotimestamp_mi_nanointerval);
Datum
nanotimestamp_mi_nanointerval(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_from_total(nt_total(PG_GETARG_NT(0)) - nt_total(PG_GETARG_NI(1))));
}

PG_FUNCTION_INFO_V1(nanointerval_pl_nanotimestamp);
Datum
nanointerval_pl_nanotimestamp(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_from_total(nt_total(PG_GETARG_NT(1)) + nt_total(PG_GETARG_NI(0))));
}

static NanoTimestamp *
ntl_interval_op(const NanoTimestamp *t, Interval *iv, bool minus)
{
	Timestamp	r = DatumGetTimestamp(DirectFunctionCall2(minus ? timestamp_mi_interval : timestamp_pl_interval,
														  TimestampGetDatum(nt_to_pg_us(t)), IntervalPGetDatum(iv)));

	return ntl_from_pg_us(r, t->nsec % NS_PER_USEC);
}

PG_FUNCTION_INFO_V1(nanotimestamp_pl_interval);
Datum
nanotimestamp_pl_interval(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_interval_op(PG_GETARG_NT(0), PG_GETARG_INTERVAL_P(1), false));
}

PG_FUNCTION_INFO_V1(nanotimestamp_mi_interval);
Datum
nanotimestamp_mi_interval(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_interval_op(PG_GETARG_NT(0), PG_GETARG_INTERVAL_P(1), true));
}

PG_FUNCTION_INFO_V1(interval_pl_nanotimestamp);
Datum
interval_pl_nanotimestamp(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_interval_op(PG_GETARG_NT(1), PG_GETARG_INTERVAL_P(0), false));
}

PG_FUNCTION_INFO_V1(time_bucket_ns_notz);
Datum
time_bucket_ns_notz(PG_FUNCTION_ARGS)
{
	PG_RETURN_POINTER(ntl_from_total(bucket128(nt_total(PG_GETARG_NI(0)), nt_total(PG_GETARG_NT(1)),
											   nt_total(PG_GETARG_NT(2)), NT_MIN_TOTAL)));
}

PG_FUNCTION_INFO_V1(nanotimestamp_trunc);
Datum
nanotimestamp_trunc(PG_FUNCTION_ARGS)
{
	text	   *unit = PG_GETARG_TEXT_PP(0);
	NanoTimestamp *t = PG_GETARG_NT(1);
	Timestamp	r;

	if (is_ns_unit(unit))
		PG_RETURN_POINTER(nt_make(t->sec, t->nsec));
	r = DatumGetTimestamp(DirectFunctionCall2(timestamp_trunc, PointerGetDatum(unit),
											  TimestampGetDatum(nt_to_pg_us(t))));
	PG_RETURN_POINTER(ntl_from_pg_us(r, 0));
}

PG_FUNCTION_INFO_V1(nanotimestamp_extract);
Datum
nanotimestamp_extract(PG_FUNCTION_ARGS)
{
	text	   *field = PG_GETARG_TEXT_PP(0);
	NanoTimestamp *t = PG_GETARG_NT(1);
	char	   *f = text_to_cstring(field);
	bool		handled;
	Datum		r;
	struct pg_tm tm;
	fsec_t		fsec;

	if (!pg_strcasecmp(f, "epoch"))
		return numeric_from_cstring(fixed9(nt_total(t)));
	if (timestamp2tm((t->sec - PG_UNIX_EPOCH_DIFF_SECS) * USECS_PER_SEC, NULL, &tm, &fsec, NULL, NULL) != 0)
		ereport(ERROR, (errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE), errmsg("nanotimestamp out of range")));
	r = sub_minute_field(f, tm.tm_sec, t->nsec, &handled);
	if (handled)
		return r;
	return DirectFunctionCall2(extract_timestamp, PointerGetDatum(field),
							   TimestampGetDatum(nt_to_pg_us(t)));
}
