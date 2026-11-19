# Container environment (pi-sandbox image)

You are inside a Docker dev container. This file is baked into the image at `/`
and pi loads it as a context file from **every** working directory in the container.

## Persistent state

Only these survive the session; everything else dies with the container:

- `/workspace` — the host project (bind mount; **root-owned**, so files you create are
  root-owned on the host).
- `/root/.pi/agent` — pi config, sessions, credentials (bind mount, may be absent).
- `/root/.agents` — shared agent resources (bind mount, may be absent).

## Toolchain

- **Python:** one uv-managed CPython 3.12 at `/opt/python`; `python`/`python3` in
  `/usr/local/bin` are symlinks to the same interpreter uv uses. No conda, no system
  python, `pip` is **not** on `PATH` (`python -m pip` works).
  Use `uv venv` / `uv add` / `uv run` / `uv tool install`. Never install into the
  shared interpreter; do not hand-roll virtualenvs.
- **C/C++:** `clang`, `clang++`, `lld`, `cmake`, `ninja`, `pkg-config`, `make`.
  `CC=clang`, `CXX=clang++`. There is **no gcc/g++/cpp** binary — port/configure scripts
  that hard-code `gcc` fail; prefer `$CC` or `cc`.
- **Rust:** `rustup`/`cargo`/`rustc` (stable, minimal profile) with
  `CARGO_HOME=/usr/local/cargo`, `RUSTUP_HOME=/usr/local/rustup`. Only the build
  host's own target is installed (`x86_64-unknown-linux-gnu` on amd64,
  `aarch64-unknown-linux-gnu` on arm64); other targets need `rustup target add`.
- **Node:** `node` 24, `npm`, `pnpm`, `yarn` (1.x classic). Corepack is present but not
  enabled.
- `git`, `rg`, `curl`, `bzip2`, `libssl-dev`, `pre-commit` (a uv tool).

## Gotchas

- `git` trusts all paths (`safe.directory '*'`) because `/workspace` is host-owned.
- git identity, credentials and SSH keys come from the host (`~/.gitconfig`,
  `~/.git-credentials`, `~/.ssh`, ssh-agent socket) when `start.sh` mounts them; if
  they are absent, set `user.name`/`user.email` yourself before committing.
- `pre-commit install` is per-repo and must be re-run after a fresh clone.
