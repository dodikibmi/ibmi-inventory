#!/QOpenSys/pkgs/bin/bash
# Start the inventory REST API on the IBM i.
# One command from a PC (opens the SSH tunnel and starts the server):
#   ssh -t -p 2222 -L 48400:127.0.0.1:48400 USER@pub400.com \
#       /QOpenSys/pkgs/bin/bash /home/USER/inventory/api/start_api.sh
# Then open http://localhost:48400/api/health on the PC. Ctrl+C stops it.
#
# The database password is asked here without echo and kept only in this
# process' environment: it is not stored in a file or the shell history.

export INV_USER=${INV_USER:-$(id -un)}
export INV_DB=${INV_DB:-PUB400}
export INV_SCHEMA=${INV_SCHEMA:-DODIKIBMI2}
export PORT=${PORT:-48400}

if [ -z "$INV_PASSWORD" ]; then
  read -r -s -p "Database password for $INV_USER: " INV_PASSWORD
  echo
  export INV_PASSWORD
fi

cd "$(dirname "$0")" || exit 1
exec /QOpenSys/pkgs/bin/python3.9 server.py
