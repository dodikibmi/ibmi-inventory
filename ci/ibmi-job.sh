#!/QOpenSys/pkgs/bin/bash
# Everything the pipeline does on the IBM i, in ONE SSH session: PUB400 refuses
# more than about two SSH logins in a short time, so build and tests cannot be
# separate SSH calls. The ::group:: lines are GitHub Actions workflow commands:
# the runner turns them into collapsible sections of the job log.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

echo "::group::Build with Bob (makei)"
# CI always does a full build: make compares file times with the objects, and
# the copied files carry the commit time, which can be older than the objects
find . -type f -exec touch {} +
bash ci/build.sh; rc=$?
echo "::endgroup::"
if [ "$rc" -ne 0 ]; then echo "::error::Build failed (exit $rc)"; exit "$rc"; fi

echo "::group::Unit tests (iRPGUnit)"
bash ci/test.sh; rc=$?
echo "::endgroup::"
if [ "$rc" -ne 0 ]; then echo "::error::Unit tests failed (exit $rc)"; exit "$rc"; fi
