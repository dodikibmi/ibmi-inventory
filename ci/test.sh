#!/QOpenSys/pkgs/bin/bash
# Compile and run the iRPGUnit suite of service program DATEUTIL.
# iRPGUnit (commands RUCRTRPG / RUCALLTST) is installed in $RULIB.
set -euo pipefail
export PATH=/QOpenSys/pkgs/bin:/QOpenSys/usr/bin:/usr/bin
OBJLIB=${OBJLIB:-DODIKIBMI1} RULIB=${RULIB:-DODIKIBMI2}
cd "$(dirname "$0")/.."
mkdir -p .logs

# the compile listing goes to a file (it is part of the build artifact)
if ! system "$RULIB/RUCRTRPG TSTPGM($OBJLIB/DATEUTILT) SRCSTMF('$PWD/qrpglesrc/dateutilt.rpgle') BNDSRVPGM(($OBJLIB/DATEUTIL)) TGTCCSID(*JOB)" > .logs/dateutilt-compile.txt 2>&1; then
  echo "::error::RUCRTRPG failed"; grep -E "RNF[0-9]{4}|CPF[0-9A-F]{4}|SQL[0-9]{4}" .logs/dateutilt-compile.txt | tail -20; exit 1
fi
echo "Test program DATEUTILT created"
# RUCALLTST ends with an escape message (non-zero exit) when a test fails
system "$RULIB/RUCALLTST TSTPGM($OBJLIB/DATEUTILT) DETAIL(*ALL)" 2>&1 | tee .logs/rpgunit.txt
grep -q "Success" .logs/rpgunit.txt
