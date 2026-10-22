EXTENSION  = pg_nanotime
MODULE_big = pg_nanotime
OBJS       = src/pg_nanotime.o
DATA       = sql/pg_nanotime--0.1.0.sql
REGRESS    = basic io casts clocks index
REGRESS_OPTS = --inputdir=test --outputdir=test
PG_CONFIG ?= pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
