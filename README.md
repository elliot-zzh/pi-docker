# pi-sandbox

Dev container for running [pi](https://github.com/earendil-works/pi-coding-agent) with a
node / python / rust / C-C++ toolchain. Adds ~1 GB on top of `node:24-bookworm-slim`.

| file | contents |
|---|---|
| `Dockerfile.pi` | the image |
| `build.sh` | build script |
| `start.sh` | runs the container after asking what to mount |
| `container/AGENTS.md` | environment notes for agents; baked to `/AGENTS.md` |
| `LICENSE` | MIT license; baked to `/opt/pi-sandbox/LICENSE` |

## Build and run

```bash
./build.sh          # build image: pi-sandbox
./start.sh
```

Both scripts need only `docker`.

## start.sh usage

Asks what to mount before launching the container;
every question defaults to yes, so pressing Enter is theb normal path.

```
~/.pi/agent   pi config, sessions, credentials
~/.agents     shared skills (~/.agents/skills/<name>/SKILL.md)
git           ~/.gitconfig, ~/.git-credentials, ~/.config/git, ~/.ssh and the
              ssh-agent socket — whichever of them exist
.             current directory, as /workspace
```

Apart from interactive mounting,
you can also skip one with `--no-agent`, `--no-agents`, `--no-git`, `--no-workspace`, or with
`PI_MOUNT_AGENT=0` / `PI_MOUNT_AGENTS=0` / `PI_MOUNT_GIT=0` / `PI_MOUNT_WORKSPACE=0`.
With no TTY (non-interactive shell, CI) nothing is asked and all are mounted.

`PI_IMAGE` picks another image name, `ANTHROPIC_API_KEY` is forwarded when set, and
arguments after `--` go to pi (`./start.sh -- --help`).

## Image contents

| tool | location / version |
|---|---|
| `node`, `npm` | base image (node 24, npm 11) |
| `yarn` | 1.22.22, `/opt/yarn-v1.22.22/bin/yarn` (base image) |
| `pnpm` | global npm package |
| `pi` | global npm package; `ENTRYPOINT` |
| `python` 3.12 | uv-managed CPython at `/opt/python`; `python`, `python3`, `python3.12` in `/usr/local/bin` are links to it |
| `uv` | `/usr/local/bin/uv` |
| `pre-commit` | uv tool, env at `/opt/uv-tools` |
| `rustc`, `cargo`, `rustup` | stable, minimal profile, `RUSTUP_HOME=/usr/local/rustup`, `CARGO_HOME=/usr/local/cargo` |
| `clang`, `clang++`, `lld`, `cmake`, `ninja`, `pkg-config`, `make` | apt; `CC=clang`, `CXX=clang++` |
| `git`, `rg`, `curl`, `bzip2`, `libssl-dev`, `libc6-dev`, `libstdc++-12-dev`, `binutils` | apt |

Note that gcc/g++ is removed and replaced by clang toolchain.

## Baked docs

| path | contents |
|---|---|
| `/AGENTS.md` | persisted paths, skill location, python rule, no-gcc, no-nvcc, no-conda, rust targets (source: `container/AGENTS.md`) |
| `/opt/pi-sandbox/README.md` | copy of this README |
| `/opt/pi-sandbox/LICENSE` | MIT license |

## Extending

Add a `RUN` line to `Dockerfile.pi`, rebuild with `./build.sh`. Installs must target
`/opt` or `/usr/local` (`/root` is not a volume). The apt, npm, uv and rustup layers
use BuildKit cache mounts; the docs `COPY` is first and the frequently updated `pi`
npm layer is last, so edits to `container/AGENTS.md`/`README.md` or a pi version bump rebuild
only cheap layers.

## License

MIT — see `LICENSE`. The license text is baked into the image at
`/opt/pi-sandbox/LICENSE`.
