"""Static checks that run on the GitHub runner, without an IBM i.

1. /COPY and /INCLUDE must not name a library: the source in Git is what gets built
   (only the iRPGUnit copybook QINCLUDE,TESTCASE comes from the installed product).
2. No tab characters in IBM i source (the compilers count columns).
3. Fixed-format RPG and DDS lines fit in 80 columns.
4. Every RPG program that is not a NOMAIN module or a copybook has a control spec
   with DFTACTGRP(*NO) (an ILE program, not the OPM-compatible default).
5. Rules.mk and the source tree agree: every source named in a rule exists and
   every compilable source is built by some rule.

Problems are printed as GitHub annotations; exit code 1 when there is one.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_EXT = {".rpgle", ".sqlrpgle", ".rpgleinc", ".clle", ".dspf", ".prtf", ".bnd"}
# not built by Bob: copybooks, and the test suite (built by ci/test.sh with RUCRTRPG)
NOT_BUILT = {"dateutilt.rpgle"}
problems = 0


def report(path, line, msg):
    global problems
    problems += 1
    print(f"::error file={path.relative_to(ROOT).as_posix()},line={line}::{msg}")


sources = sorted(p for p in ROOT.rglob("*") if p.is_file() and p.suffix.lower() in SRC_EXT
                 and ".git" not in p.parts)

for p in sources:
    lines = p.read_text(encoding="utf-8").splitlines()
    free = bool(lines) and lines[0].strip().upper().startswith("**FREE")
    fixed_rpg = p.suffix.lower() in {".rpgle", ".sqlrpgle", ".rpgleinc"} and not free
    for n, line in enumerate(lines, 1):
        if "\t" in line:
            report(p, n, "tab character in source")
        m = re.match(r"\s*/(COPY|INCLUDE)\s+(\S+)", line, re.I)
        if m and "/" in m.group(2).split(",")[0] and not m.group(2).upper().endswith("QINCLUDE,TESTCASE"):
            report(p, n, f"/{m.group(1).upper()} names a library ({m.group(2)}); use the stream file")
        if (fixed_rpg or p.suffix.lower() in {".dspf", ".prtf"}) and len(line) > 80:
            report(p, n, f"line is {len(line)} columns, fixed format allows 80")
    if p.suffix.lower() in {".rpgle", ".sqlrpgle"} and p.name not in NOT_BUILT:
        text = "\n".join(lines).upper()
        if "NOMAIN" not in text and "DFTACTGRP(*NO)" not in text:
            report(p, 1, "program has no control spec with DFTACTGRP(*NO)")

# Rules.mk <-> sources
built = set()
for rules in ROOT.rglob("Rules.mk"):
    for n, line in enumerate(rules.read_text(encoding="utf-8").splitlines(), 1):
        m = re.match(r"^([A-Z0-9_]+\.[A-Z]+):\s*(?!private)(\S+)", line)
        if m and "." in m.group(2) and not m.group(2).isupper():
            src = rules.parent / m.group(2)
            built.add(src.resolve())
            if not src.exists():
                report(rules, n, f"{m.group(1)} is built from {m.group(2)}, which does not exist")
        for dep in re.findall(r"\b[a-z0-9_]+\.rpgleinc\b", line):
            built.add((rules.parent / dep).resolve())
for p in sources:
    if p.resolve() not in built and p.name not in NOT_BUILT:
        report(p, 1, "source is not built by any Rules.mk rule")

print(f"lint: {len(sources)} source files, {problems} problem(s)")
sys.exit(1 if problems else 0)
