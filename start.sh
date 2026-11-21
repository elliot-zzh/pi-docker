#!/usr/bin/env bash
# Launches pi in the pi-sandbox image, after asking what to mount.
# Pre-answer the questions with --agent/--no-agent, --agents/--no-agents,
# --identity/--no-identity, --https/--no-https, --ssh/--no-ssh,
# --workspace/--no-workspace, or with PI_MOUNT_AGENT, PI_MOUNT_AGENTS,
# PI_MOUNT_IDENTITY, PI_MOUNT_HTTPS, PI_MOUNT_SSH, PI_MOUNT_WORKSPACE (0 or 1).
# Without a TTY every question takes its default (shown as [Y/n] or [y/N]).
set -euo pipefail

IMAGE="${PI_IMAGE:-pi-sandbox}"

usage() {
  cat <<'EOF'
usage: start.sh [--agent|--no-agent] [--agents|--no-agents]
                [--identity|--no-identity] [--https|--no-https] [--ssh|--no-ssh]
                [--workspace|--no-workspace] [-h] [-- pi-args...]
EOF
}

die() { printf '%s\n' "$*" >&2; exit 1; }

mount_agent="${PI_MOUNT_AGENT:-}"
mount_agents="${PI_MOUNT_AGENTS:-}"
mount_identity="${PI_MOUNT_IDENTITY:-}"
mount_https="${PI_MOUNT_HTTPS:-}"
mount_ssh="${PI_MOUNT_SSH:-}"
mount_project="${PI_MOUNT_WORKSPACE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --agent)        mount_agent=1 ;;
    --no-agent)     mount_agent=0 ;;
    --agents)       mount_agents=1 ;;
    --no-agents)    mount_agents=0 ;;
    --identity)     mount_identity=1 ;;
    --no-identity)  mount_identity=0 ;;
    --https)        mount_https=1 ;;
    --no-https)     mount_https=0 ;;
    --ssh)          mount_ssh=1 ;;
    --no-ssh)       mount_ssh=0 ;;
    --workspace)    mount_project=1 ;;
    --no-workspace) mount_project=0 ;;
    -h|--help)      usage; exit 0 ;;
    --)             shift; break ;;
    -*)             usage >&2; die "unknown option: $1" ;;
    *)              break ;;
  esac
  shift
done

confirm() { # confirm <prompt> <y|n default> -> 0 = yes; no prompt without a TTY
  local answer='' hint='[y/N]'
  [ "$2" = y ] && hint='[Y/n]'
  if [ ! -t 0 ]; then [ "$2" = y ]; return; fi
  read -r -p "$1 $hint " answer || true
  case "$answer" in
    [yY]*) return 0 ;;
    [nN]*) return 1 ;;
    *)     [ "$2" = y ] ;;
  esac
}

ask() { # ask <var-name> <prompt> <y|n default>; skipped when the variable is preset
  local name=$1 value=1
  if [ -n "${!name}" ]; then return 0; fi
  confirm "$2" "$3" || value=0
  printf -v "$name" '%s' "$value"
}

ask mount_agent    "Mount ~/.pi/agent (config, sessions, credentials)?" y
ask mount_agents   "Mount ~/.agents (shared skills)?" y
ask mount_identity "Mount git identity (~/.gitconfig, read-only)?" y
ask mount_https    "Mount HTTPS git credentials (~/.git-credentials, ~/.config/git)?" n
ask mount_ssh      "Mount SSH keys and config (~/.ssh) and the ssh-agent socket?" n
ask mount_project  "Mount current dir as /workspace?" y

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
if [ "$mount_identity" = 1 ]; then
  if [ -f "$HOME/.gitconfig" ]; then
    args+=(-v "$HOME/.gitconfig:/root/.gitconfig:ro")
    mounted+=("gitconfig")
  fi
fi
if [ "$mount_https" = 1 ]; then
  if [ -f "$HOME/.git-credentials" ]; then
    # store helper is enabled only here; the file is read-only, so git reads tokens but cannot rewrite them
    args+=(-v "$HOME/.git-credentials:/root/.git-credentials:ro"
           -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=credential.helper -e GIT_CONFIG_VALUE_0=store)
    mounted+=("git-credentials")
  fi
  if [ -d "$HOME/.config/git" ]; then
    args+=(-v "$HOME/.config/git:/root/.config/git:ro")
    mounted+=(".config/git")
  fi
fi
if [ "$mount_ssh" = 1 ]; then
  if [ -d "$HOME/.ssh" ]; then
    args+=(-v "$HOME/.ssh:/root/.ssh:ro")
    mounted+=("ssh")
  fi
  if [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "$SSH_AUTH_SOCK" ] && [ "$(uname -s)" != Darwin ]; then
    args+=(-v "$SSH_AUTH_SOCK:/ssh-agent" -e SSH_AUTH_SOCK=/ssh-agent)
    mounted+=("ssh-agent")
  fi
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
