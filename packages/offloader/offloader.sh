#!/usr/bin/env bash
set -euo pipefail

new_run_id() {
  local timestamp

  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr "[:upper:]" "[:lower:]"
  else
    timestamp="$(date -u +%Y%m%d-%H%M%S)"
    printf '%s-%s%s\n' "${timestamp}" "${RANDOM}" "${RANDOM}"
  fi
}

die() {
  echo "offloader: $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: offloader [options] -- COMMAND [ARG...]

Launch a command in a worktree for the git repo containing $PWD, on a remote
machine reached through a transport command.

Options:
  --command COMMAND               Shell command to run from the worktree.
  --transport TRANSPORT           Command that runs the work on the remote.

Provide a command with --command, OFFLOADER_COMMAND, or -- COMMAND [ARG...].

The transport is a single command string whose job is to take a script on its
stdin, run it on the remote machine/container, and forward stdout/stderr and the
exit status. The adapters offloader-ssh, offloader-tailscale, and offloader-fly
provide this; you can also point it at anything else (e.g. kubectl exec).

Set it with --transport or OFFLOADER_TRANSPORT, for example:
  OFFLOADER_TRANSPORT='offloader-ssh box.lab'
  OFFLOADER_TRANSPORT='offloader-tailscale box.lab'
  OFFLOADER_TRANSPORT='offloader-fly --app my-app --machine 0123456789'

Examples:
  offloader -- npm run dev
  offloader -- bash scripts/start.sh --port 3000
  offloader --command 'npm run dev'
  offloader --transport 'offloader-ssh box.lab' -- npm run dev

Other useful env overrides:
  OFFLOADER_REPO_ROOT, OFFLOADER_REPO_URL, OFFLOADER_REMOTE_NAME,
  OFFLOADER_REPO_PATH, OFFLOADER_TRANSPORT, OFFLOADER_RUN_ID,
  OFFLOADER_WORKTREE_NAME, OFFLOADER_RUN_BRANCH, OFFLOADER_REMOTE_ROOT,
  OFFLOADER_REMOTE_DIR, OFFLOADER_WORKTREE_DIR, OFFLOADER_COMMAND
USAGE
}

COMMAND_MODE=
RUN_COMMAND=()
TRANSPORT_OVERRIDE=

if [[ -n "${OFFLOADER_COMMAND:-}" ]]; then
  COMMAND_MODE=shell
  RUN_COMMAND=("${OFFLOADER_COMMAND}")
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --command)
      [[ $# -ge 2 ]] || die "--command requires a value"
      COMMAND_MODE=shell
      RUN_COMMAND=("$2")
      shift 2
      ;;
    --command=*)
      COMMAND_MODE=shell
      RUN_COMMAND=("${1#*=}")
      shift
      ;;
    --transport)
      [[ $# -ge 2 ]] || die "--transport requires a value"
      TRANSPORT_OVERRIDE="$2"
      shift 2
      ;;
    --transport=*)
      TRANSPORT_OVERRIDE="${1#*=}"
      shift
      ;;
    --)
      shift
      [[ $# -gt 0 ]] || die "-- must be followed by a command"
      COMMAND_MODE=argv
      RUN_COMMAND=("$@")
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ ${#RUN_COMMAND[@]} -gt 0 && -n "${RUN_COMMAND[0]}" ]] || die "command must not be empty"

if ! command -v git >/dev/null 2>&1; then
  echo "git required" >&2
  exit 1
fi

detect_remote_name() {
  local upstream remote remotes

  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -n "${upstream}" && "${upstream}" == */* ]]; then
    remote="${upstream%%/*}"
    if git remote get-url "${remote}" >/dev/null 2>&1; then
      printf '%s\n' "${remote}"
      return 0
    fi
  fi

  if git remote get-url origin >/dev/null 2>&1; then
    printf '%s\n' origin
    return 0
  fi

  remotes="$(git remote)"
  while IFS= read -r remote; do
    [[ -n "${remote}" ]] || continue
    printf '%s\n' "${remote}"
    return 0
  done <<< "${remotes}"
}

sanitize_path_segment() {
  local segment="$1"

  segment="${segment//[^A-Za-z0-9._-]/-}"
  while [[ "${segment}" == -* ]]; do
    segment="${segment#-}"
  done
  while [[ "${segment}" == *- ]]; do
    segment="${segment%-}"
  done
  if [[ -z "${segment}" || "${segment}" == "." || "${segment}" == ".." ]]; then
    segment="unknown"
  fi
  printf '%s\n' "${segment}"
}

repo_path_from_url() {
  local url path owner repo name owner_segment repo_segment name_segment

  url="${1%/}"
  url="${url%%\?*}"
  url="${url%%#*}"

  case "${url}" in
    git@github.com:*)
      path="${url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      path="${url#ssh://git@github.com/}"
      ;;
    https://github.com/*)
      path="${url#https://github.com/}"
      ;;
    http://github.com/*)
      path="${url#http://github.com/}"
      ;;
    git://github.com/*)
      path="${url#git://github.com/}"
      ;;
    github.com/*)
      path="${url#github.com/}"
      ;;
    github.com:*)
      path="${url#github.com:}"
      ;;
    *)
      path=""
      ;;
  esac

  if [[ -n "${path}" && "${path}" == */* ]]; then
    owner="${path%%/*}"
    repo="${path#*/}"
    repo="${repo%%/*}"
    repo="${repo%.git}"

    owner_segment="$(sanitize_path_segment "${owner}")"
    repo_segment="$(sanitize_path_segment "${repo}")"
    printf 'gh/%s/%s\n' "${owner_segment}" "${repo_segment}"
    return 0
  fi

  name="${url##*/}"
  name="${name%.git}"
  name_segment="$(sanitize_path_segment "${name}")"
  printf 'git/%s\n' "${name_segment}"
}

base64_encode() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

base64_array_lines() {
  local encoded word

  for word in "$@"; do
    encoded="$(base64_encode "${word}")"
    printf "  '%s'\n" "${encoded}"
  done
}

default_worktree_name() {
  sanitize_path_segment "$1"
}

REPO_ROOT="${OFFLOADER_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[[ -n "${REPO_ROOT}" ]] || die "run this from inside a git repository"
cd "${REPO_ROOT}"

REPO_URL="${OFFLOADER_REPO_URL:-}"
if [[ -z "${REPO_URL}" ]]; then
  REMOTE_NAME="${OFFLOADER_REMOTE_NAME:-$(detect_remote_name)}"
  [[ -n "${REMOTE_NAME:-}" ]] || die "no git remote configured; set OFFLOADER_REPO_URL"
  REPO_URL="$(git remote get-url "${REMOTE_NAME}")"
fi

OFFLOADER_REPO_PATH="${OFFLOADER_REPO_PATH:-$(repo_path_from_url "${REPO_URL}")}"

# Transport: --transport flag, else OFFLOADER_TRANSPORT. No default; offloader is provider-agnostic.
OFFLOADER_TRANSPORT="${TRANSPORT_OVERRIDE:-${OFFLOADER_TRANSPORT:-}}"
[[ -n "${OFFLOADER_TRANSPORT}" ]] \
  || die "no transport configured: set OFFLOADER_TRANSPORT (e.g. 'offloader-ssh box.lab') or pass --transport"

TRANSPORT_BIN="${OFFLOADER_TRANSPORT%% *}"
command -v "${TRANSPORT_BIN}" >/dev/null 2>&1 \
  || die "transport command '${TRANSPORT_BIN}' not found on PATH (from OFFLOADER_TRANSPORT='${OFFLOADER_TRANSPORT}')"

OFFLOADER_RUN_ID="${OFFLOADER_RUN_ID:-$(new_run_id)}"
OFFLOADER_RUN_ID="$(sanitize_path_segment "${OFFLOADER_RUN_ID}")"
OFFLOADER_RUN_BRANCH="${OFFLOADER_RUN_BRANCH:-offloader/${OFFLOADER_RUN_ID}}"
OFFLOADER_WORKTREE_NAME="${OFFLOADER_WORKTREE_NAME:-$(default_worktree_name "${OFFLOADER_RUN_BRANCH}")}"
OFFLOADER_REMOTE_ROOT="${OFFLOADER_REMOTE_ROOT:-}"
OFFLOADER_REMOTE_DIR="${OFFLOADER_REMOTE_DIR:-}"
OFFLOADER_WORKTREE_DIR="${OFFLOADER_WORKTREE_DIR:-}"

git check-ref-format "refs/heads/${OFFLOADER_RUN_BRANCH}" \
  || die "invalid OFFLOADER_RUN_BRANCH: ${OFFLOADER_RUN_BRANCH}"

COMMAND_STRING=
COMMAND_ARGV_B64_LINES=
if [[ "${COMMAND_MODE}" == "shell" ]]; then
  COMMAND_STRING="${RUN_COMMAND[0]}"
else
  COMMAND_ARGV_B64_LINES="$(base64_array_lines "${RUN_COMMAND[@]}")"
fi

LOCAL_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -n "${LOCAL_BRANCH}" ]]; then
  git push "${REPO_URL}" "HEAD:${LOCAL_BRANCH}"
fi

git push "${REPO_URL}" "HEAD:${OFFLOADER_RUN_BRANCH}"

OFFLOADER_REMOTE_DIR_B64="$(base64_encode "${OFFLOADER_REMOTE_DIR}")"
OFFLOADER_REMOTE_ROOT_B64="$(base64_encode "${OFFLOADER_REMOTE_ROOT}")"
OFFLOADER_REPO_PATH_B64="$(base64_encode "${OFFLOADER_REPO_PATH}")"
OFFLOADER_RUN_BRANCH_B64="$(base64_encode "${OFFLOADER_RUN_BRANCH}")"
OFFLOADER_WORKTREE_NAME_B64="$(base64_encode "${OFFLOADER_WORKTREE_NAME}")"
OFFLOADER_WORKTREE_DIR_B64="$(base64_encode "${OFFLOADER_WORKTREE_DIR}")"
COMMAND_STRING_B64="$(base64_encode "${COMMAND_STRING}")"
REPO_URL_B64="$(base64_encode "${REPO_URL}")"

REMOTE_SCRIPT=$(cat <<SCRIPT
set -euo pipefail

b64_decode_into() {
  local __name="\$1" encoded="\$2" decoded
  if ! decoded="\$(printf '%s' "\${encoded}" | base64 -d; printf .)"; then
    echo "offloader: remote failed to decode base64 payload for \${__name}" >&2
    exit 1
  fi
  decoded="\${decoded%.}"
  printf -v "\${__name}" '%s' "\${decoded}"
}

command -v base64 >/dev/null 2>&1 \
  || { echo "offloader: remote missing required command: base64" >&2; exit 127; }

b64_decode_into REPO_URL '${REPO_URL_B64}'
b64_decode_into OFFLOADER_REPO_PATH '${OFFLOADER_REPO_PATH_B64}'
b64_decode_into OFFLOADER_REMOTE_ROOT '${OFFLOADER_REMOTE_ROOT_B64}'
b64_decode_into OFFLOADER_REMOTE_DIR '${OFFLOADER_REMOTE_DIR_B64}'
b64_decode_into OFFLOADER_WORKTREE_NAME '${OFFLOADER_WORKTREE_NAME_B64}'
b64_decode_into OFFLOADER_WORKTREE_DIR '${OFFLOADER_WORKTREE_DIR_B64}'
b64_decode_into OFFLOADER_RUN_BRANCH '${OFFLOADER_RUN_BRANCH_B64}'
b64_decode_into COMMAND_STRING '${COMMAND_STRING_B64}'
COMMAND_MODE=${COMMAND_MODE}

COMMAND_ARGV_B64=(
${COMMAND_ARGV_B64_LINES}
)
COMMAND_ARGV=()
for encoded_arg in "\${COMMAND_ARGV_B64[@]}"; do
  b64_decode_into decoded_arg "\${encoded_arg}"
  COMMAND_ARGV+=("\${decoded_arg}")
done

: "\${OFFLOADER_REMOTE_ROOT:=\${HOME}/.remote-work}"
: "\${OFFLOADER_REMOTE_DIR:=\${OFFLOADER_REMOTE_ROOT}/repos/\${OFFLOADER_REPO_PATH}}"
: "\${OFFLOADER_WORKTREE_DIR:=\${OFFLOADER_REMOTE_DIR}/.worktrees/\${OFFLOADER_WORKTREE_NAME}}"

mkdir -p "\$(dirname "\${OFFLOADER_REMOTE_DIR}")"
setup_lock="\${OFFLOADER_REMOTE_DIR}.offloader-setup-lock"
setup_attempt=0
while ! mkdir "\${setup_lock}" 2>/dev/null; do
  setup_attempt=\$((setup_attempt + 1))
  if [ "\${setup_attempt}" -ge 600 ]; then
    echo "offloader: timed out waiting for target repo setup lock: \${setup_lock}" >&2
    exit 1
  fi
  sleep 0.1
done
release_setup_lock() {
  rmdir "\${setup_lock}" 2>/dev/null || true
}
trap release_setup_lock EXIT

if [ ! -e "\${OFFLOADER_REMOTE_DIR}" ]; then
  git clone "\${REPO_URL}" "\${OFFLOADER_REMOTE_DIR}"
elif [ ! -d "\${OFFLOADER_REMOTE_DIR}/.git" ]; then
  echo "offloader: target repo path is not a normal Git checkout: \${OFFLOADER_REMOTE_DIR}" >&2
  exit 1
fi

run_ref="refs/remotes/offloader/\${OFFLOADER_RUN_BRANCH}"
git -C "\${OFFLOADER_REMOTE_DIR}" fetch "\${REPO_URL}" \
  "+refs/heads/\${OFFLOADER_RUN_BRANCH}:\${run_ref}"

exclude="\$(git -C "\${OFFLOADER_REMOTE_DIR}" rev-parse --path-format=absolute --git-path info/exclude)"
mkdir -p "\$(dirname "\${exclude}")"
touch "\${exclude}"
grep -Fqx '/.worktrees/' "\${exclude}" || printf '%s\n' '/.worktrees/' >>"\${exclude}"

mkdir -p "\$(dirname "\${OFFLOADER_WORKTREE_DIR}")"
if [ -d "\${OFFLOADER_WORKTREE_DIR}/.git" ] || [ -f "\${OFFLOADER_WORKTREE_DIR}/.git" ]; then
  git -C "\${OFFLOADER_WORKTREE_DIR}" checkout "\${OFFLOADER_RUN_BRANCH}"
  git -C "\${OFFLOADER_WORKTREE_DIR}" reset --hard "\${run_ref}"
else
  if [ -e "\${OFFLOADER_WORKTREE_DIR}" ] || [ -L "\${OFFLOADER_WORKTREE_DIR}" ]; then
    echo "offloader: worktree path already exists and is not a Git worktree: \${OFFLOADER_WORKTREE_DIR}" >&2
    exit 1
  fi
  git -C "\${OFFLOADER_REMOTE_DIR}" worktree add -b "\${OFFLOADER_RUN_BRANCH}" \
    "\${OFFLOADER_WORKTREE_DIR}" "\${run_ref}"
fi
release_setup_lock
trap - EXIT

cd "\${OFFLOADER_WORKTREE_DIR}"
if [ "\${COMMAND_MODE}" = "shell" ]; then
  exec bash -lc "\${COMMAND_STRING}"
fi
exec "\${COMMAND_ARGV[@]}"
SCRIPT
)

printf '%s\n' "${REMOTE_SCRIPT}" | bash -c "${OFFLOADER_TRANSPORT}"
