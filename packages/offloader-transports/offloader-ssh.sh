#!/usr/bin/env bash
set -euo pipefail

# offloader transport: run the script on stdin under `bash -s` on an SSH host.
# Args go to ssh as-is, e.g. OFFLOADER_TRANSPORT='offloader-ssh box.lab'.

if [[ $# -lt 1 ]]; then
  echo "offloader-ssh: usage: offloader-ssh DESTINATION [ssh-option...]" >&2
  exit 2
fi

exec ssh "$@" bash -s
