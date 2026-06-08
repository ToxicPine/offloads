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
  OFFLOADER_WORKTREE_NAME, OFFLOADER_RUN_BRANCH, OFFLOADER_BASE_BRANCH,
  OFFLOADER_REMOTE_ROOT, OFFLOADER_REMOTE_DIR, OFFLOADER_BARE_DIR,
  OFFLOADER_WORKTREE_DIR, OFFLOADER_COMMAND
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

shell_quote_word() {
  local word="$1"

  printf "'"
  while [[ "${word}" == *"'"* ]]; do
    printf "%s'\\''" "${word%%\'*}"
    word="${word#*\'}"
  done
  printf "%s'" "${word}"
}

shell_quote_command() {
  local word sep=""

  for word in "$@"; do
    printf "%s" "${sep}"
    shell_quote_word "${word}"
    sep=" "
  done
  printf "\n"
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
OFFLOADER_BASE_BRANCH="${OFFLOADER_BASE_BRANCH:-$(git symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'main')}"
OFFLOADER_REMOTE_ROOT="${OFFLOADER_REMOTE_ROOT:-}"
OFFLOADER_REMOTE_DIR="${OFFLOADER_REMOTE_DIR:-}"
OFFLOADER_BARE_DIR="${OFFLOADER_BARE_DIR:-}"
OFFLOADER_WORKTREE_DIR="${OFFLOADER_WORKTREE_DIR:-}"

if [[ "${COMMAND_MODE}" == "shell" ]]; then
  COMMAND_STRING="${RUN_COMMAND[0]}"
else
  COMMAND_STRING="$(shell_quote_command "${RUN_COMMAND[@]}")"
fi

LOCAL_BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
if [[ -n "${LOCAL_BRANCH}" ]]; then
  git push "${REPO_URL}" "HEAD:${LOCAL_BRANCH}"
fi

git push "${REPO_URL}" "HEAD:${OFFLOADER_RUN_BRANCH}"

OFFLOADER_BASE_BRANCH_Q="$(shell_quote_word "${OFFLOADER_BASE_BRANCH}")"
OFFLOADER_BARE_DIR_Q="$(shell_quote_word "${OFFLOADER_BARE_DIR}")"
OFFLOADER_REMOTE_DIR_Q="$(shell_quote_word "${OFFLOADER_REMOTE_DIR}")"
OFFLOADER_REMOTE_ROOT_Q="$(shell_quote_word "${OFFLOADER_REMOTE_ROOT}")"
OFFLOADER_REPO_PATH_Q="$(shell_quote_word "${OFFLOADER_REPO_PATH}")"
OFFLOADER_RUN_BRANCH_Q="$(shell_quote_word "${OFFLOADER_RUN_BRANCH}")"
OFFLOADER_WORKTREE_NAME_Q="$(shell_quote_word "${OFFLOADER_WORKTREE_NAME}")"
OFFLOADER_WORKTREE_DIR_Q="$(shell_quote_word "${OFFLOADER_WORKTREE_DIR}")"
COMMAND_STRING_Q="$(shell_quote_word "${COMMAND_STRING}")"
REPO_URL_Q="$(shell_quote_word "${REPO_URL}")"

REMOTE_SCRIPT=$(cat <<SCRIPT
set -euo pipefail
REPO_URL=${REPO_URL_Q}
OFFLOADER_REPO_PATH=${OFFLOADER_REPO_PATH_Q}
OFFLOADER_REMOTE_ROOT=${OFFLOADER_REMOTE_ROOT_Q}
OFFLOADER_REMOTE_DIR=${OFFLOADER_REMOTE_DIR_Q}
OFFLOADER_BARE_DIR=${OFFLOADER_BARE_DIR_Q}
OFFLOADER_WORKTREE_NAME=${OFFLOADER_WORKTREE_NAME_Q}
OFFLOADER_WORKTREE_DIR=${OFFLOADER_WORKTREE_DIR_Q}
OFFLOADER_RUN_BRANCH=${OFFLOADER_RUN_BRANCH_Q}
OFFLOADER_BASE_BRANCH=${OFFLOADER_BASE_BRANCH_Q}
COMMAND_STRING=${COMMAND_STRING_Q}

: "\${OFFLOADER_REMOTE_ROOT:=\${HOME}/.remote-work}"
: "\${OFFLOADER_REMOTE_DIR:=\${OFFLOADER_REMOTE_ROOT}/repos/\${OFFLOADER_REPO_PATH}}"
: "\${OFFLOADER_BARE_DIR:=\${OFFLOADER_REMOTE_DIR}/.bare}"
: "\${OFFLOADER_WORKTREE_DIR:=\${OFFLOADER_REMOTE_DIR}/\${OFFLOADER_WORKTREE_NAME}}"

mkdir -p "\${OFFLOADER_REMOTE_DIR}"
if [ ! -d "\${OFFLOADER_BARE_DIR}" ]; then
  git clone --bare "\${REPO_URL}" "\${OFFLOADER_BARE_DIR}"
fi
git -C "\${OFFLOADER_BARE_DIR}" fetch "\${REPO_URL}" '+refs/heads/*:refs/heads/*'
mkdir -p "\$(dirname "\${OFFLOADER_WORKTREE_DIR}")"
if [ -d "\${OFFLOADER_WORKTREE_DIR}/.git" ] || [ -f "\${OFFLOADER_WORKTREE_DIR}/.git" ]; then
  git -C "\${OFFLOADER_WORKTREE_DIR}" fetch origin
  git -C "\${OFFLOADER_WORKTREE_DIR}" checkout "\${OFFLOADER_RUN_BRANCH}"
  git -C "\${OFFLOADER_WORKTREE_DIR}" reset --hard "\${OFFLOADER_RUN_BRANCH}"
else
  rm -rf "\${OFFLOADER_WORKTREE_DIR}"
  git -C "\${OFFLOADER_BARE_DIR}" worktree add "\${OFFLOADER_WORKTREE_DIR}" "\${OFFLOADER_RUN_BRANCH}"
fi
cd "\${OFFLOADER_WORKTREE_DIR}"
exec bash -lc "\${COMMAND_STRING}"
SCRIPT
)

printf '%s\n' "${REMOTE_SCRIPT}" | bash -c "${OFFLOADER_TRANSPORT}"
