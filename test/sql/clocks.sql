SET timezone = 'UTC';
SELECT provolatile, proname FROM pg_proc WHERE proname IN ('clock_ns', 'now_ns', 'statement_ns') ORDER BY proname;
-- clock_ns: has sub-microsecond digits available and is close to clock_timestamp()
SELECT abs(extract(epoch FROM clock_ns()::timestamptz - clock_timestamp())) < 1 AS close;
-- clock_ns advances across calls
SELECT count(DISTINCT c) > 1 AS advances FROM (SELECT clock_ns() c FROM generate_series(1, 1000)) s;
-- now_ns is stable within a transaction and >= now() (floor to us)
BEGIN;
SELECT now_ns() AS a \gset
SELECT pg_sleep(0.01);
SELECT now_ns() = :'a'::nanotimestamptz AS same_in_xact, now_ns()::timestamptz >= now() AS not_before_now;
SELECT statement_ns() > now_ns() AS later_statement;
COMMIT;
SELECT now_ns() > :'a'::nanotimestamptz AS new_xact_new_value;
-- statement_ns is constant within one statement
SELECT count(DISTINCT statement_ns()) FROM generate_series(1, 1000);
-- DEFAULT
CREATE TEMP TABLE ev(id int, t1 nanotimestamptz DEFAULT clock_ns(), t2 nanotimestamptz DEFAULT now_ns());
INSERT INTO ev(id) SELECT g FROM generate_series(1, 1000) g;
SELECT count(DISTINCT t1) > 1 AS clock_varies, count(DISTINCT t2) AS now_constant FROM ev;
SELECT bool_and(t1 >= t2) AS clock_after_now FROM ev;
