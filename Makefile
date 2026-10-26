EXTENSION  = pg_nanotime
MODULE_big = pg_nanotime
OBJS       = src/pg_nanotime.o
DATA       = sql/pg_nanotime--0.1.0.sql sql/pg_nanotime--0.2.0.sql sql/pg_nanotime--0.3.0.sql sql/pg_nanotime--0.1.0--0.2.0.sql sql/pg_nanotime--0.2.0--0.3.0.sql
REGRESS    = basic io casts clocks index compact interval arith bucket notz migrate monotonic global agg series coverage range timescale_missing examples
ifdef WITH_TIMESCALEDB
REGRESS += timescale
endif
REGRESS_OPTS = --inputdir=test --outputdir=test
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
PG_MAJOR := $(shell $(PG_CONFIG) --version | sed -E 's/^PostgreSQL ([0-9]+).*/\1/')
ifeq ($(shell test "$(PG_MAJOR)" -ge 17 2>/dev/null && echo ok),)
$(error pg_nanotime requires PostgreSQL 17 or later; $(PG_CONFIG) reports "$(shell $(PG_CONFIG) --version)")
endif
include $(PGXS)

# ---- release packaging (PGXN) ----
EXTVERSION := $(shell sed -n "s/^default_version *= *'\(.*\)'/\1/p" pg_nanotime.control)
DISTNAME   := pg_nanotime-$(EXTVERSION)

.PHONY: dist
dist:
	git archive --format zip --prefix=$(DISTNAME)/ -o $(DISTNAME).zip HEAD
	@echo "created $(DISTNAME).zip from HEAD (commit first; uncommitted changes are not included)"

# ---- docs consistency: docs/EXAMPLES.md vs the examples regression test ----
.PHONY: check-docs
check-docs:
	python3 tools/check_examples.py
