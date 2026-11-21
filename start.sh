#!/usr/bin/env bash
# Launches pi in the pi-sandbox image, after asking what to mount.
# Mode per mount: no | ro | rw.
#   ~/.pi/agent, ~/.agents: default ro;  current dir (/workspace): default rw.
# Pre-answer with --agent=MODE, --agents=MODE, --workspace=MODE, or with
# PI_MOUNT_AGENT, PI_MOUNT_AGENTS, PI_MOUNT_WORKSPACE (no|ro|rw, or 0 = no, 1 = default).
# --agent / --agents / --workspace alone take the default mode; --no-agent,
# --no-agents, --no-workspace skip the mount.
# Yes/no mounts (git identity, https, ssh) are pre-answered with --identity/--no-identity,
# --https/--no-https, --ssh/--no-ssh, or PI_MOUNT_IDENTITY, PI_MOUNT_HTTPS, PI_MOUNT_SSH (0 or 1).
# Without a TTY every question takes its default.
set -euo pipefail

IMAGE="${PI_IMAGE:-pi-sandbox}"

usage() {
  cat <<'EOF'
usage: start.sh [--agent[=no|ro|rw]] [--agents[=no|ro|rw]] [--workspace[=no|ro|rw]]
                [--identity|--no-identity] [--https|--no-https] [--ssh|--no-ssh]
                [-h] [-- pi-args...]
EOF
}

die() { printf '%s\n' "$*" >&2; exit 1; }

mount_agent="${PI_MOUNT_AGENT:-}"
mount_agents="${PI_MOUNT_AGENTS:-}"
mount_project="${PI_MOUNT_WORKSPACE:-}"
mount_identity="${PI_MOUNT_IDENTITY:-}"
mount_https="${PI_MOUNT_HTTPS:-}"
mount_ssh="${PI_MOUNT_SSH:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --agent=*)      mount_agent=${1#--agent=} ;;
    --agent)        mount_agent=1 ;;
    --no-agent)     mount_agent=no ;;
    --agents=*)     mount_agents=${1#--agents=} ;;
    --agents)       mount_agents=1 ;;
    --no-agents)    mount_agents=no ;;
    --workspace=*)  mount_project=${1#--workspace=} ;;
    --workspace)    mount_project=1 ;;
    --no-workspace) mount_project=no ;;
    --identity)     mount_identity=1 ;;
    --no-identity)  mount_identity=0 ;;
    --https)        mount_https=1 ;;
    --no-https)     mount_https=0 ;;
    --ssh)          mount_ssh=1 ;;
    --no-ssh)       mount_ssh=0 ;;
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

ask() { # ask <var-name> <prompt> <y|n default>; a preset value skips the prompt
  local name=$1 value=1
  if [ -n "${!name}" ]; then
    case "${!name}" in 0) value=0 ;; 1) value=1 ;; *) die "invalid value for $name: ${!name} (use 0 or 1)" ;; esac
  else
    confirm "$2" "$3" || value=0
  fi
  printf -v "$name" '%s' "$value"
}

mode_value() { # mode_value <preset> <default mode> -> prints no|ro|rw
  case "$1" in
    0|no) echo no ;;
    1)    echo "$2" ;;
    ro|rw) echo "$1" ;;
    *)    die "invalid mount mode: $1 (use no, ro or rw)" ;;
  esac
}

ask_mode() { # ask_mode <var-name> <prompt> <default mode>; a preset value skips the prompt
  local name=$1 def=$3 answer='' mode
  if [ -n "${!name}" ]; then
    mode=$(mode_value "${!name}" "$def")
  else
    mode=$def
    if [ -t 0 ]; then
      read -r -p "$2 [no/ro/rw, default $def] " answer || true
      case "$answer" in
        n|no) mode=no ;;
        ro)   mode=ro ;;
        rw)   mode=rw ;;
      esac
    fi
  fi
  printf -v "$name" '%s' "$mode"
}

ask_mode mount_agent  "Mount ~/.pi/agent (config, sessions, credentials)?" ro
ask_mode mount_agents "Mount ~/.agents (shared skills)?" ro
ask_mode mount_project "Mount current dir as /workspace?" rw
ask mount_identity "Mount git identity (~/.gitconfig, read-only)?" y
ask mount_https    "Mount HTTPS git credentials (~/.git-credentials, ~/.config/git)?" n
ask mount_ssh      "Mount SSH keys and config (~/.ssh) and the ssh-agent socket?" n

command -v docker >/dev/null 2>&1 || die "docker not found"
docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image '$IMAGE' not found - run ./build.sh"

args=(docker run --rm -it -e ANTHROPIC_API_KEY)
mounted=()

if [ "$mount_agent" != no ]; then
  mkdir -p "$HOME/.pi/agent"
  args+=(-v "$HOME/.pi/agent:/root/.pi/agent:$mount_agent")
  mounted+=("~/.pi/agent:$mount_agent")
fi
if [ "$mount_agents" != no ]; then
  mkdir -p "$HOME/.agents"
  args+=(-v "$HOME/.agents:/root/.agents:$mount_agents")
  mounted+=("~/.agents:$mount_agents")
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
if [ "$mount_project" != no ]; then
  args+=(-v "$PWD:/workspace:$mount_project" -w /workspace)
  mounted+=("/workspace:$mount_project")
fi

if [ ${#mounted[@]} -eq 0 ]; then
  echo "mounts: none"
else
  printf 'mounts: %s\n' "${mounted[*]}"
fi
exec "${args[@]}" "$IMAGE" "$@"
