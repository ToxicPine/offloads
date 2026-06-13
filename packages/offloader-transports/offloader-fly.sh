#!/usr/bin/env bash
set -euo pipefail

# offloader transport: run the script on stdin under `bash` on a Fly machine.
# Args go to `fly ssh console`, e.g.
# 'offloader-fly --app my-app --machine 0123456789'.

if [[ $# -lt 1 ]]; then
  echo "offloader-fly: usage: offloader-fly --app APP --machine MACHINE_ID [fly-ssh-console-option...]" >&2
  exit 2
fi

base64_encode() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

sentinel="__OFFLOADER_FLY_EXIT_${RANDOM}_${RANDOM}__"
exit_file="$(mktemp)"
trap 'rm -f "${exit_file}"' EXIT

remote_command=$(cat <<REMOTE
set -euo pipefail
script="\$(mktemp)"
cat > "\${script}"
set +e
bash "\${script}"
code=\$?
rm -f "\${script}"
echo
echo "${sentinel}\${code}"
exit 0
REMOTE
)
remote_command_b64="$(base64_encode "${remote_command}")"

set +e
fly ssh console "$@" --command "bash -c 'command -v base64 >/dev/null 2>&1 || { echo \"offloader-fly: remote missing required command: base64\" >&2; exit 127; }; remote_command=\$(printf %s \"\$1\" | base64 -d) || { echo \"offloader-fly: remote failed to decode bootstrap\" >&2; exit 1; }; bash -c \"\${remote_command}\"' _ ${remote_command_b64}" 2>&1 \
  | while IFS= read -r line; do
      case "${line}" in
        "${sentinel}"*)
          printf '%s\n' "${line#"${sentinel}"}" > "${exit_file}"
          ;;
        *)
          printf '%s\n' "${line}"
          ;;
      esac
    done
fly_status=${PIPESTATUS[0]}
set -e

if [[ ${fly_status} -ne 0 ]]; then
  exit "${fly_status}"
fi

if [[ ! -s "${exit_file}" ]]; then
  echo "offloader-fly: remote command did not report an exit status" >&2
  exit 1
fi

remote_status="$(cat "${exit_file}")"
if [[ ! "${remote_status}" =~ ^[0-9]+$ ]]; then
  echo "offloader-fly: invalid remote exit status: ${remote_status}" >&2
  exit 1
fi

exit "${remote_status}"
