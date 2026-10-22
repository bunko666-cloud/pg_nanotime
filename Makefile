EXTENSION  = pg_nanotime
MODULE_big = pg_nanotime
OBJS       = src/pg_nanotime.o
DATA       = sql/pg_nanotime--0.1.0.sql
REGRESS    = basic io casts clocks index compact interval arith bucket notz migrate
REGRESS_OPTS = --inputdir=test --outputdir=test
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
PG_MAJOR := $(shell $(PG_CONFIG) --version | sed -E 's/^PostgreSQL ([0-9]+).*/\1/')
ifeq ($(shell test "$(PG_MAJOR)" -ge 17 2>/dev/null && echo ok),)
$(error pg_nanotime requires PostgreSQL 17 or later; $(PG_CONFIG) reports "$(shell $(PG_CONFIG) --version)")
endif
include $(PGXS)
