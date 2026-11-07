#!/QOpenSys/pkgs/bin/bash
# Compile and run the iRPGUnit suite of service program DATEUTIL.
# iRPGUnit (commands RUCRTRPG / RUCALLTST) is installed in $RULIB.
set -euo pipefail
export PATH=/QOpenSys/pkgs/bin:/QOpenSys/usr/bin:/usr/bin
OBJLIB=${OBJLIB:-DODIKIBMI1} RULIB=${RULIB:-DODIKIBMI2}
cd "$(dirname "$0")/.."
mkdir -p .logs

system "$RULIB/RUCRTRPG TSTPGM($OBJLIB/DATEUTILT) SRCSTMF('$PWD/qrpglesrc/dateutilt.rpgle') BNDSRVPGM(($OBJLIB/DATEUTIL)) TGTCCSID(*JOB)"
# RUCALLTST ends with an escape message (non-zero exit) when a test fails
system "$RULIB/RUCALLTST TSTPGM($OBJLIB/DATEUTILT) DETAIL(*ALL)" 2>&1 | tee .logs/rpgunit.txt
grep -q "Success" .logs/rpgunit.txt
