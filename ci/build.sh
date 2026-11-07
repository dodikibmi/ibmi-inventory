#!/QOpenSys/pkgs/bin/bash
# Build the application with IBM Bob (makei) from the stream files in this
# directory. Runs on the IBM i (PASE). Objects go to $OBJLIB, the tables are
# expected in $DTALIB (created once with sql/01_tables.sql).
set -euo pipefail
export PATH=/QOpenSys/pkgs/bin:/QOpenSys/usr/bin:/usr/bin
export OBJLIB=${OBJLIB:-DODIKIBMI1} DTALIB=${DTALIB:-DODIKIBMI2}
cd "$(dirname "$0")/.."

mkdir -p .logs
makei build 2>&1 | tee .logs/build.txt
# makei can end with "Build Successful" and exit code 0 although make stopped on
# an error (a target that was not built is not counted as failed): check both
if grep -Eq "Error [0-9]+$|not remade because of errors|[1-9][0-9]* failed" .logs/build.txt; then
  echo "::error::IBM i build failed"
  grep -E "Error [0-9]+$|not remade|failed|^CPD|^CPF|RNF[0-9]{4}" .logs/build.txt
  exit 1
fi
