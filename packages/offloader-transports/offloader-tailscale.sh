#!/usr/bin/env bash
set -euo pipefail

# offloader transport: run the script on stdin under `bash -s` over Tailscale SSH.
# Args go to `tailscale ssh` as-is, e.g. 'offloader-tailscale box.lab' (MagicDNS name).

if [[ $# -lt 1 ]]; then
  echo "offloader-tailscale: usage: offloader-tailscale DESTINATION [ssh-option...]" >&2
  exit 2
fi

exec tailscale ssh "$@" bash -s
