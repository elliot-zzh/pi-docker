#!/usr/bin/env bash
# Launches pi in the pi-sandbox image, after asking what to mount.
# Pre-answer the questions with --no-agent / --no-agents / --no-workspace or
# PI_MOUNT_AGENT=0 / PI_MOUNT_AGENTS=0 / PI_MOUNT_WORKSPACE=0. Without a TTY
# every answer defaults to yes.
set -euo pipefail

IMAGE="${PI_IMAGE:-pi-sandbox}"

usage() {
  cat <<'EOF'
usage: start.sh [--agent|--no-agent] [--agents|--no-agents] [--git|--no-git]
                [--workspace|--no-workspace] [-h] [-- pi-args...]
EOF
}

die() { printf '%s\n' "$*" >&2; exit 1; }

mount_agent="${PI_MOUNT_AGENT:-}"
mount_agents="${PI_MOUNT_AGENTS:-}"
mount_git="${PI_MOUNT_GIT:-}"
mount_project="${PI_MOUNT_WORKSPACE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --agent)        mount_agent=1 ;;
    --no-agent)     mount_agent=0 ;;
    --agents)       mount_agents=1 ;;
    --no-agents)    mount_agents=0 ;;
    --git)          mount_git=1 ;;
    --no-git)       mount_git=0 ;;
    --workspace)    mount_project=1 ;;
    --no-workspace) mount_project=0 ;;
    -h|--help)      usage; exit 0 ;;
    --)             shift; break ;;
    -*)             usage >&2; die "unknown option: $1" ;;
    *)              break ;;
  esac
  shift
done

confirm() { # confirm <prompt> -> 0 = yes; default yes; no prompt without a TTY
  local answer=''
  if [ ! -t 0 ]; then return 0; fi
  read -r -p "$1 [Y/n] " answer || true
  case "$answer" in [nN]*) return 1 ;; *) return 0 ;; esac
}

ask() { # ask <var-name> <prompt>; skipped when the variable is preset
  local name=$1 value=1
  if [ -n "${!name}" ]; then return 0; fi
  confirm "$2" || value=0
  printf -v "$name" '%s' "$value"
}

ask mount_agent   "Mount ~/.pi/agent (config, sessions, credentials)?"
ask mount_agents  "Mount ~/.agents (shared skills)?"
ask mount_git     "Mount git config and SSH keys (~/.gitconfig, ~/.ssh)?"
ask mount_project "Mount current dir as /workspace?"

command -v docker >/dev/null 2>&1 || die "docker not found"
docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image '$IMAGE' not found - run ./build.sh"

args=(docker run --rm -it -e ANTHROPIC_API_KEY)
mounted=()

if [ "$mount_agent" = 1 ]; then
  mkdir -p "$HOME/.pi/agent"
  args+=(-v "$HOME/.pi/agent:/root/.pi/agent")
  mounted+=("~/.pi/agent")
fi
if [ "$mount_agents" = 1 ]; then
  mkdir -p "$HOME/.agents"
  args+=(-v "$HOME/.agents:/root/.agents")
  mounted+=("~/.agents")
fi
if [ "$mount_git" = 1 ]; then
  before=${#args[@]}
  for f in .gitconfig .git-credentials; do
    [ -f "$HOME/$f" ] && args+=(-v "$HOME/$f:/root/$f")
  done
  [ -d "$HOME/.config/git" ] && args+=(-v "$HOME/.config/git:/root/.config/git")
  [ -d "$HOME/.ssh" ] && args+=(-v "$HOME/.ssh:/root/.ssh")
  if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ] && [ "$(uname -s)" != Darwin ]; then
    args+=(-v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent)
  fi
  [ "${#args[@]}" -gt "$before" ] && mounted+=("git")
fi
if [ "$mount_project" = 1 ]; then
  args+=(-v "$PWD:/workspace" -w /workspace)
  mounted+=("/workspace")
fi

if [ ${#mounted[@]} -eq 0 ]; then
  echo "mounts: none"
else
  printf 'mounts: %s\n' "${mounted[*]}"
fi
exec "${args[@]}" "$IMAGE" "$@"
