#!/usr/bin/env python3
"""Check that docs/EXAMPLES.md stays in sync with the examples regression test.

The regression test (test/sql/examples.sql + test/expected/examples.out) is the
source of truth. Rules:
  1. Every fenced code block in docs/EXAMPLES.md must appear, line for line,
     as a contiguous run of test/expected/examples.out, and the blocks must
     appear in the same order as in the test.
  2. Together the blocks must cover the whole example region of the .out file
     (from the first "-- ex1" marker up to "RESET search_path"), except the
     "-- exN:" section-marker comment lines, so nothing is silently dropped.
  3. Every non-blank line of the example region of examples.sql must appear,
     in order, in examples.out (the .out echoes the SQL), so a SQL edit that
     was not re-recorded is caught without running PostgreSQL.
Only trailing whitespace is normalized. No dependencies besides Python 3.
"""
import difflib, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOC = os.path.join(ROOT, "docs", "EXAMPLES.md")
SQL = os.path.join(ROOT, "test", "sql", "examples.sql")
OUT = os.path.join(ROOT, "test", "expected", "examples.out")
MARKER = re.compile(r"^-- ex\d+:")

def lines(path):
    with open(path, encoding="utf-8") as f:
        return [l.rstrip() for l in f.read().splitlines()]

def region(ls, path):
    start = next((i for i, l in enumerate(ls) if MARKER.match(l)), None)
    end = next((i for i, l in enumerate(ls) if l == "RESET search_path;"), None)
    if start is None or end is None:
        sys.exit(f"{path}: cannot find '-- ex1:' marker or 'RESET search_path;'")
    return start, end

def doc_blocks(ls):
    blocks, section, cur, start = [], "(before first heading)", None, 0
    for i, l in enumerate(ls, 1):
        if cur is None and l.startswith("## "):
            section = l[3:].strip()
        elif l.startswith("```"):
            if cur is None:
                cur, start = [], i + 1
            else:
                while cur and cur[-1] == "":
                    cur.pop()
                blocks.append((section, start, cur))
                cur = None
        elif cur is not None:
            cur.append(l)
    return blocks

def find(hay, needle, frm):
    n = len(needle)
    for i in range(frm, len(hay) - n + 1):
        if hay[i:i + n] == needle:
            return i
    return -1

def main():
    errors = []
    out = lines(OUT)
    os_, oe = region(out, OUT)
    blocks = doc_blocks(lines(DOC))
    if not blocks:
        errors.append("docs/EXAMPLES.md: no code blocks found")
    covered = set()
    pos = os_
    for section, start, blk in blocks:
        if not blk:
            continue
        i = find(out, blk, pos)
        if i < 0 or i + len(blk) > oe:
            # locate best-matching spot for a useful diff
            anchor = find(out, blk[:1], os_)
            ref = out[anchor:anchor + len(blk)] if anchor >= 0 else out[pos:pos + len(blk)]
            diff = "\n".join(difflib.unified_diff(
                ref, blk, "test/expected/examples.out", "docs/EXAMPLES.md", lineterm=""))
            where = "found elsewhere (out of order)" if find(out, blk, os_) >= 0 else "does not match the test"
            errors.append(f"docs/EXAMPLES.md section '{section}' (code block at line {start}) {where}:\n{diff}")
            continue
        covered.update(range(i, i + len(blk)))
        pos = i + len(blk)
    missing = [k for k in range(os_, oe)
               if k not in covered and out[k] != "" and not MARKER.match(out[k])]
    if missing and not errors:
        errors.append("test/expected/examples.out lines not shown in docs/EXAMPLES.md:\n" +
                      "\n".join(f"  out:{k + 1}: {out[k]}" for k in missing))
    sql = lines(SQL)
    ss, se = region(sql, SQL)
    p = os_
    for k in range(ss, se):
        l = sql[k]
        if not l:
            continue
        while p < oe and out[p] != l:
            p += 1
        if p >= oe:
            errors.append(f"test/sql/examples.sql:{k + 1} not found (in order) in "
                          f"test/expected/examples.out; re-record the expected output:\n  {l}")
            break
        p += 1
    if errors:
        print("check_examples: FAILED\n\n" + "\n\n".join(errors), file=sys.stderr)
        print("\nThe regression test is the source of truth: update docs/EXAMPLES.md "
              "(and test/expected/examples.out after a SQL change), then run 'make check-docs'.",
              file=sys.stderr)
        return 1
    print(f"check_examples: OK ({len(blocks)} doc blocks match test/expected/examples.out)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
