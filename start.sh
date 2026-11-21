#!/usr/bin/env bash
# Launches pi in the pi-sandbox image, after asking what to mount.
# Modes:
#   ~/.pi/agent:  no | limited | rw     default limited
#                 limited = whole dir read-only, sessions/ and tmp/ read-write
#                 rw      = whole dir read-write
#   ~/.agents:    no | ro | rw          default ro
#   /workspace:   no | ro | rw          default rw
# Pre-answer with --agent=MODE, --agents=MODE, --workspace=MODE.
# --agent / --agents / --workspace alone take the default mode; --no-agent,
# --no-agents, --no-workspace skip the mount.
# Yes/no mounts (git identity, https, ssh) are pre-answered with --identity/--no-identity,
# --https/--no-https, --ssh/--no-ssh.
# Without a TTY every question takes its default.
set -euo pipefail

IMAGE="${PI_IMAGE:-pi-sandbox}"

usage() {
  cat <<'EOF'
usage: start.sh [--agent[=no|limited|rw]] [--agents[=no|ro|rw]] [--workspace[=no|ro|rw]]
                [--identity|--no-identity] [--https|--no-https] [--ssh|--no-ssh]
                [-h] [-- pi-args...]
EOF
}

die() { printf '%s\n' "$*" >&2; exit 1; }

mount_agent=
mount_agents=
mount_project=
mount_identity=
mount_https=
mount_ssh=

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

mode_value() { # mode_value <preset> <default mode> <allowed modes...> -> prints a mode
  local value=$1 def=$2 m
  shift 2
  case "$value" in
    0) echo no; return ;;
    1) echo "$def"; return ;;
  esac
  for m in "$@"; do
    if [ "$value" = "$m" ]; then echo "$value"; return; fi
  done
  die "invalid mount mode: $value (use one of: $*)"
}

ask_mode() { # ask_mode <var-name> <prompt> <default mode> <allowed modes...>; a preset value skips the prompt
  local name=$1 prompt=$2 def=$3 answer='' mode m
  shift 3
  if [ -n "${!name}" ]; then
    mode=$(mode_value "${!name}" "$def" "$@")
  else
    mode=$def
    if [ -t 0 ]; then
      read -r -p "$prompt [$(IFS=/; echo "$*"), default $def] " answer || true
      for m in "$@"; do
        if [ "$answer" = "$m" ]; then mode=$m; fi
      done
      case "$answer" in n|no) mode=no ;; esac
    fi
  fi
  printf -v "$name" '%s' "$mode"
}

ask_mode mount_agent   "Mount ~/.pi/agent (config, sessions, credentials)?" limited limited rw no
ask_mode mount_agents  "Mount ~/.agents (shared skills)?" ro ro rw no
ask_mode mount_project "Mount current dir as /workspace?" rw ro rw no
ask mount_identity "Mount git identity (~/.gitconfig, read-only)?" y
ask mount_https    "Mount HTTPS git credentials (~/.git-credentials, ~/.config/git)?" n
ask mount_ssh      "Mount SSH keys and config (~/.ssh) and the ssh-agent socket?" n

command -v docker >/dev/null 2>&1 || die "docker not found"
docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image '$IMAGE' not found - run ./build.sh"

args=(docker run --rm -it -e ANTHROPIC_API_KEY)
mounted=()

case "$mount_agent" in
  rw)
    mkdir -p "$HOME/.pi/agent"
    args+=(-v "$HOME/.pi/agent:/root/.pi/agent")
    mounted+=("~/.pi/agent:rw")
    ;;
  limited)
    # The agent dir itself cannot be a read-only bind mount: pi takes
    # trust.json.lock (a directory) inside it on every start, which fails with EROFS.
    # So /root/.pi/agent is a container-local directory (ephemeral, writable) and
    # each host entry is bind-mounted into it individually: sessions/, tmp/ and
    # trust.json read-write, everything else read-only.
    mkdir -p "$HOME/.pi/agent/sessions" "$HOME/.pi/agent/tmp"
    [ -f "$HOME/.pi/agent/trust.json" ] || echo '{}' > "$HOME/.pi/agent/trust.json"
    for entry in "$HOME"/.pi/agent/* "$HOME"/.pi/agent/.[!.]*; do
      [ -e "$entry" ] || continue
      name=${entry##*/}
      case "$name" in
        sessions|tmp|trust.json) mode=rw ;;
        *) mode=ro ;;
      esac
      args+=(-v "$entry:/root/.pi/agent/$name:$mode")
    done
    mounted+=("~/.pi/agent:ro (sessions,tmp,trust.json:rw)")
    ;;
esac
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
