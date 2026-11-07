"""Turn the compiler's EVFEVENT files (.evfevent/, written by OPTION(*EVENTF))
into GitHub annotations on the source lines, so a failed build shows the RPG/CL/DDS
message next to the line in the pull request or run summary.

EVFEVENT records used:
  FILEID <ver> <file-id> <line> <path-length> <path> <timestamp> <flag>
  ERROR  <ver> <file-id> <annot-class> <stmt-line> <start-line> <start-col>
         <end-line> <end-col> <msg-id> <sev-char> <sev-num> <length> <text>
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REMOTE = sys.argv[1] if len(sys.argv) > 1 else ""   # project directory on the IBM i
seen = set()
for f in sorted((ROOT / ".evfevent").glob("*.evfevent")):
    files = {}
    for rec in f.read_text(encoding="utf-8", errors="replace").splitlines():
        parts = rec.split()
        if not parts:
            continue
        m = re.match(r"FILEID\s+\d+\s+(\d+)\s+\d+\s+(\d+) (.*)", rec)
        if m:
            files[m.group(1)] = m.group(3)[:int(m.group(2))]   # the path may be empty
        elif parts[0] == "ERROR" and len(parts) >= 13:
            sev = int(parts[11])
            if sev < 20:
                continue
            path = files.get(parts[2], "")
            if REMOTE and path.startswith(REMOTE):
                path = path[len(REMOTE):].lstrip("/")
            line, msg = str(int(parts[5])), " ".join(parts[13:])
            key = (path, line, parts[9])
            if key in seen:
                continue
            seen.add(key)
            kind = "error" if sev >= 30 else "warning"
            where = f"file={path},line={line}," if path and not path.startswith("/") else ""
            print(f"::{kind} {where}title={parts[9]} sev {sev}::{f.stem}: {msg}")
