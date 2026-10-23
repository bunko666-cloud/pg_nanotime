#include "postgres.h"
#include "fmgr.h"
#include "libpq/pqformat.h"
#include "utils/builtins.h"
#include "common/hashfn.h"
#include <time.h>
PG_MODULE_MAGIC;
#define NS 1000000000LL
/* ---------- layout A: {int64 sec, int64 nsec}, 16B by-ref ---------- */
typedef struct { int64 sec; int64 nsec; } ns16;
static ns16 *mk(int64 s,int64 n){ns16 *r=palloc(sizeof(ns16));r->sec=s;r->nsec=n;return r;}
static int cmp(const ns16*a,const ns16*b){ if(a->sec!=b->sec) return a->sec<b->sec?-1:1; if(a->nsec!=b->nsec) return a->nsec<b->nsec?-1:1; return 0;}
#define A ((ns16*)PG_GETARG_POINTER(0))
#define B ((ns16*)PG_GETARG_POINTER(1))
static ns16 *from_i64(int64 v){int64 s=v/NS,n=v%NS; if(n<0){n+=NS;s--;} return mk(s,n);}
/* input: integer ns (int64) or "sec.nnnnnnnnn" with sec any int64 */
PG_FUNCTION_INFO_V1(ns16_in); Datum ns16_in(PG_FUNCTION_ARGS){ char *s=PG_GETARG_CSTRING(0); char *dot=strchr(s,'.');
  if(!dot){ errno=0; long long v=strtoll(s,NULL,10); if(errno) ereport(ERROR,(errmsg("ns16 out of range"))); PG_RETURN_POINTER(from_i64(v)); }
  PG_RETURN_POINTER(mk(strtoll(s,NULL,10), strtoll(dot+1,NULL,10)));}
PG_FUNCTION_INFO_V1(ns16_out); Datum ns16_out(PG_FUNCTION_ARGS){ ns16*a=A; PG_RETURN_CSTRING(psprintf("%lld.%09lld",(long long)a->sec,(long long)a->nsec));}
PG_FUNCTION_INFO_V1(ns16_recv); Datum ns16_recv(PG_FUNCTION_ARGS){StringInfo b=(StringInfo)PG_GETARG_POINTER(0); int64 s=pq_getmsgint64(b); int64 n=pq_getmsgint64(b); PG_RETURN_POINTER(mk(s,n));}
PG_FUNCTION_INFO_V1(ns16_send); Datum ns16_send(PG_FUNCTION_ARGS){ns16*a=A; StringInfoData b; pq_begintypsend(&b); pq_sendint64(&b,a->sec); pq_sendint64(&b,a->nsec); PG_RETURN_BYTEA_P(pq_endtypsend(&b));}
PG_FUNCTION_INFO_V1(ns16_from_int8); Datum ns16_from_int8(PG_FUNCTION_ARGS){ PG_RETURN_POINTER(from_i64(PG_GETARG_INT64(0)));}
PG_FUNCTION_INFO_V1(ns16_to_int8); Datum ns16_to_int8(PG_FUNCTION_ARGS){ ns16*a=A; int64 r; if(__builtin_mul_overflow(a->sec,NS,&r)||__builtin_add_overflow(r,a->nsec,&r)) ereport(ERROR,(errcode(ERRCODE_DATETIME_VALUE_OUT_OF_RANGE),errmsg("ns16 out of bigint range"))); PG_RETURN_INT64(r);}
/* saturating, monotonic non-decreasing partition function */
PG_FUNCTION_INFO_V1(ns16_part); Datum ns16_part(PG_FUNCTION_ARGS){ ns16*a=A; int64 r; if(__builtin_mul_overflow(a->sec,NS,&r)||__builtin_add_overflow(r,a->nsec,&r)) PG_RETURN_INT64(a->sec<0?PG_INT64_MIN:PG_INT64_MAX); PG_RETURN_INT64(r);}
PG_FUNCTION_INFO_V1(ns16_cmp); Datum ns16_cmp(PG_FUNCTION_ARGS){PG_RETURN_INT32(cmp(A,B));}
PG_FUNCTION_INFO_V1(ns16_lt); Datum ns16_lt(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp(A,B)<0);}
PG_FUNCTION_INFO_V1(ns16_le); Datum ns16_le(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp(A,B)<=0);}
PG_FUNCTION_INFO_V1(ns16_eq); Datum ns16_eq(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp(A,B)==0);}
PG_FUNCTION_INFO_V1(ns16_ge); Datum ns16_ge(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp(A,B)>=0);}
PG_FUNCTION_INFO_V1(ns16_gt); Datum ns16_gt(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp(A,B)>0);}
PG_FUNCTION_INFO_V1(ns16_hash); Datum ns16_hash(PG_FUNCTION_ARGS){ return hash_any((unsigned char*)A,sizeof(ns16));}
PG_FUNCTION_INFO_V1(clock_ns); Datum clock_ns(PG_FUNCTION_ARGS){struct timespec t;clock_gettime(CLOCK_REALTIME,&t);PG_RETURN_INT64((int64)t.tv_sec*NS+t.tv_nsec);}
PG_FUNCTION_INFO_V1(clock_ns16); Datum clock_ns16(PG_FUNCTION_ARGS){struct timespec t;clock_gettime(CLOCK_REALTIME,&t);PG_RETURN_POINTER(mk(t.tv_sec,t.tv_nsec));}
/* ---------- layout B: single __int128 ns, 16B by-ref ---------- */
typedef __int128 i128;
#define C ((i128*)PG_GETARG_POINTER(0))
#define D ((i128*)PG_GETARG_POINTER(1))
static i128 *mk128(i128 v){i128 *r=palloc(sizeof(i128)); memcpy(r,&v,16); return r;}
static inline i128 ld(const void *p){i128 v; memcpy(&v,p,16); return v;}
static int cmp128(const void*a,const void*b){i128 x=ld(a),y=ld(b); return x<y?-1:(x>y?1:0);}
PG_FUNCTION_INFO_V1(ns128_in); Datum ns128_in(PG_FUNCTION_ARGS){ char*s=PG_GETARG_CSTRING(0); int neg=0; i128 v=0; if(*s=='-'){neg=1;s++;} for(;*s;s++){ if(*s<'0'||*s>'9') ereport(ERROR,(errmsg("invalid ns128"))); v=v*10+(*s-'0'); } PG_RETURN_POINTER(mk128(neg?-v:v));}
PG_FUNCTION_INFO_V1(ns128_out); Datum ns128_out(PG_FUNCTION_ARGS){ i128 v=ld(C); char buf[48]; int i=47; int neg=v<0; unsigned __int128 u= neg? -(unsigned __int128)v : (unsigned __int128)v; buf[i]=0; do{buf[--i]='0'+(int)(u%10);u/=10;}while(u); if(neg) buf[--i]='-'; PG_RETURN_CSTRING(pstrdup(buf+i));}
PG_FUNCTION_INFO_V1(ns128_recv); Datum ns128_recv(PG_FUNCTION_ARGS){StringInfo b=(StringInfo)PG_GETARG_POINTER(0); int64 hi=pq_getmsgint64(b); uint64 lo=(uint64)pq_getmsgint64(b); PG_RETURN_POINTER(mk128(((i128)hi<<64)|lo));}
PG_FUNCTION_INFO_V1(ns128_send); Datum ns128_send(PG_FUNCTION_ARGS){i128 v=ld(C); StringInfoData b; pq_begintypsend(&b); pq_sendint64(&b,(int64)(v>>64)); pq_sendint64(&b,(int64)(uint64)v); PG_RETURN_BYTEA_P(pq_endtypsend(&b));}
PG_FUNCTION_INFO_V1(ns128_from_int8); Datum ns128_from_int8(PG_FUNCTION_ARGS){PG_RETURN_POINTER(mk128(PG_GETARG_INT64(0)));}
PG_FUNCTION_INFO_V1(ns128_part); Datum ns128_part(PG_FUNCTION_ARGS){ i128 v=ld(C); if(v>PG_INT64_MAX) PG_RETURN_INT64(PG_INT64_MAX); if(v<PG_INT64_MIN) PG_RETURN_INT64(PG_INT64_MIN); PG_RETURN_INT64((int64)v);}
PG_FUNCTION_INFO_V1(ns128_cmp); Datum ns128_cmp(PG_FUNCTION_ARGS){PG_RETURN_INT32(cmp128(C,D));}
PG_FUNCTION_INFO_V1(ns128_lt); Datum ns128_lt(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp128(C,D)<0);}
PG_FUNCTION_INFO_V1(ns128_le); Datum ns128_le(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp128(C,D)<=0);}
PG_FUNCTION_INFO_V1(ns128_eq); Datum ns128_eq(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp128(C,D)==0);}
PG_FUNCTION_INFO_V1(ns128_ge); Datum ns128_ge(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp128(C,D)>=0);}
PG_FUNCTION_INFO_V1(ns128_gt); Datum ns128_gt(PG_FUNCTION_ARGS){PG_RETURN_BOOL(cmp128(C,D)>0);}
PG_FUNCTION_INFO_V1(ns128_hash); Datum ns128_hash(PG_FUNCTION_ARGS){ return hash_any((unsigned char*)C,16);}
PG_FUNCTION_INFO_V1(clock_ns128); Datum clock_ns128(PG_FUNCTION_ARGS){struct timespec t;clock_gettime(CLOCK_REALTIME,&t);PG_RETURN_POINTER(mk128((i128)t.tv_sec*NS+t.tv_nsec));}
