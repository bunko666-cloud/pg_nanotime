/*
 * pg_nanotime — nanosecond-precision timestamp types for PostgreSQL.
 *
 * nanotimestamptz: 16 bytes, { int64 sec; int64 nsec; }
 *   sec  = seconds since 1970-01-01 00:00:00 UTC (floor),
 *   nsec = 0 .. 999999999 (always normalized).
 * Valid range equals PostgreSQL timestamptz: 4713-11-24 BC 00:00:00 UTC
 * up to (but excluding) 294277-01-01 00:00:00 UTC.
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
#include "utils/timestamp.h"

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

#if PG_VERSION_NUM >= 170000
#define MY_LXID (MyProc->vxid.lxid)
#else
#define MY_LXID (MyProc->lxid)
#endif

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
PG_FUNCTION_INFO_V1(nanotimestamptz_in);
Datum
nanotimestamptz_in(PG_FUNCTION_ARGS)
{
	char	   *str = PG_GETARG_CSTRING(0);
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

	us = DatumGetTimestampTz(DirectFunctionCall3(timestamptz_in,
												 CStringGetDatum(buf),
												 ObjectIdGetDatum(InvalidOid),
												 Int32GetDatum(-1)));
	PG_RETURN_POINTER(nt_from_pg_us(us, frac_ns));
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

PG_FUNCTION_INFO_V1(nanotimestamptz_out);
Datum
nanotimestamptz_out(PG_FUNCTION_ARGS)
{
	NanoTimestamp *t = PG_GETARG_NT(0);
	TimestampTz whole = (t->sec - PG_UNIX_EPOCH_DIFF_SECS) * USECS_PER_SEC;
	struct pg_tm tm;
	fsec_t		fsec;
	int			tz;
	const char *tzn;
	char		tzbuf[16];
	int			year;

	if (timestamp2tm(whole, &tz, &tm, &fsec, &tzn, NULL) != 0)
		ereport(ERROR,
				(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),
				 errmsg("nanotimestamptz out of range")));
	append_tz(tzbuf, tz);
	year = tm.tm_year > 0 ? tm.tm_year : -(tm.tm_year - 1);
	PG_RETURN_CSTRING(psprintf("%04d-%02d-%02d %02d:%02d:%02d.%09lld%s%s",
							   year, tm.tm_mon, tm.tm_mday,
							   tm.tm_hour, tm.tm_min, tm.tm_sec,
							   (long long) t->nsec, tzbuf,
							   tm.tm_year > 0 ? "" : " BC"));
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

PG_FUNCTION_INFO_V1(nanotimestamptz_to_int8);
Datum
nanotimestamptz_to_int8(PG_FUNCTION_ARGS)
{
	NanoTimestamp *t = PG_GETARG_NT(0);
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
		ereport(ERROR,
				(errcode(ERRCODE_NUMERIC_VALUE_OUT_OF_RANGE),
				 errmsg("nanotimestamptz out of range for bigint"),
				 errdetail("bigint nanoseconds cover only 1677-09-21 to 2262-04-11.")));
	PG_RETURN_INT64(r);
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
