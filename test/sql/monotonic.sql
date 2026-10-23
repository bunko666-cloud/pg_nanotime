-- Phase 3: per-backend strictly increasing clocks, regression tracking, clock source
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pg_nanotime;
RESET client_min_messages;

SELECT proname, provolatile, proparallel FROM pg_proc
 WHERE proname IN ('clock_ns_monotonic','clock_ns8_monotonic','clock_ns_global','clock_ns8_global','nanotime_clock_status','nanotime_now_int8')
 ORDER BY 1;

-- 200k calls in one statement: strictly increasing, no duplicates
WITH s AS (SELECT g, clock_ns_monotonic() t FROM generate_series(1, 200000) g),
     d AS (SELECT t, lag(t) OVER (ORDER BY g) p FROM s)
SELECT count(*) AS n, count(*) FILTER (WHERE t <= p) AS not_increasing,
       count(DISTINCT t) AS distinct_values FROM d;
WITH s AS (SELECT g, clock_ns8_monotonic() t FROM generate_series(1, 200000) g),
     d AS (SELECT t, lag(t) OVER (ORDER BY g) p FROM s)
SELECT count(*) AS n, count(*) FILTER (WHERE t <= p) AS not_increasing,
       count(DISTINCT t) AS distinct_values FROM d;
-- 16B and 8B share one per-backend counter
SELECT clock_ns_monotonic() < clock_ns8_monotonic() AND clock_ns8_monotonic() < clock_ns_monotonic() AS shared_counter;
-- close to the real clock
SELECT abs(extract_ns('epoch', clock_ns_monotonic() - clock_ns())) < 0.01 AS near_clock;

-- simulated clock regression: step the clock back 2 s (test-only GUC)
SELECT nanotime_reset_stats();
CREATE TEMP TABLE r(k int, t nanotimestamptz, c nanotimestamptz);
INSERT INTO r SELECT 1, clock_ns_monotonic(), clock_ns();
SET nanotime.debug_clock_offset_us = -2000000;
INSERT INTO r SELECT 2, clock_ns_monotonic(), clock_ns();
INSERT INTO r SELECT 3, clock_ns_monotonic(), clock_ns();
SELECT a.t < b.t AND b.t < c.t AS still_increasing,
       b.t - a.t = '1 ns'::nanointerval AS held_at_last_plus_1ns,
       b.c < a.c AS raw_clock_went_back
  FROM r a, r b, r c WHERE a.k = 1 AND b.k = 2 AND c.k = 3;
SELECT local_regressions >= 1 AS regression_counted,
       local_max_regression_ns BETWEEN 1900000000 AND 2100000000 AS magnitude_about_2s,
       local_bumps >= 2 AS bumped,
       local_lead_ns BETWEEN 1900000000 AND 2100000000 AS lead_about_2s
  FROM nanotime_clock_status();
-- clock_ns() itself follows the (regressed) clock; only *_monotonic holds
SELECT clock_ns() < (SELECT t FROM r WHERE k = 1) AS plain_clock_is_behind;
RESET nanotime.debug_clock_offset_us;
SELECT clock_ns_monotonic() > (SELECT t FROM r WHERE k = 3) AS increasing_after_catch_up;
SELECT local_regressions AS regressions_after_forward_step FROM nanotime_clock_status();
-- only superusers may shift the clock
CREATE ROLE nt_plain;
SET ROLE nt_plain;
SET nanotime.debug_clock_offset_us = 1;
SELECT nanotime_reset_stats();
RESET ROLE;
DROP ROLE nt_plain;

-- clock source
SELECT nanotime_reset_stats();
SHOW nanotime.clock_source;
SET nanotime.clock_source = tai;
SELECT clock_source, tai_offset_s >= 0 AS tai_offset_known FROM nanotime_clock_status();
SELECT abs(extract_ns('epoch', clock_ns() - now_ns())) < 3600 AS tai_reading_sane;
SET nanotime.clock_source = realtime;
SELECT local_regressions AS switching_source_is_not_a_regression FROM nanotime_clock_status();
SET nanotime.clock_source = gps;
SET nanotime.bogus = 1;
