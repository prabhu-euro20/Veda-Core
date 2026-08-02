# Veda-Core Toolchain Milestone 2: LLVM Dev Environment Setup

**Date:** 2026-07-31
**Scope:** install a real LLVM/Clang development environment (needed starting
Toolchain Milestones 5-6, the LLVM-based assembler work) and diagnose the
already-broken `riscv64-unknown-elf-gdb`.

## What was installed (by the user, on their own machine, per their explicit request
to run the commands themselves rather than have this session invoke `sudo`)

`sudo apt-get install -y clang llvm-dev cmake ninja-build`

**Verified, real results, confirmed live**:
- `clang --version` → `Ubuntu clang version 21.1.8 (6ubuntu1)`, `InstalledDir:
  /usr/lib/llvm-21/bin`
- `llvm-config --version` → `21.1.8`
- `cmake --version` → `4.2.3`
- `ninja --version` → `1.13.2`
- `dpkg`/`apt-cache policy` reports the installed `.deb` package version as
  `1:21.1.6-71` for `clang`/`llvm-dev`, while `clang --version`'s own internal
  string reports `21.1.8` — a real, checked, benign Debian/Ubuntu packaging
  nuance (the outer package revision number and the compiler's own internally
  reported version string are tracked independently in Ubuntu's LLVM packaging;
  this is a known, common mismatch, not a broken or inconsistent install).
  `libllvm21` (the runtime library already present before this milestone) is
  installed at `1:21.1.8-6ubuntu1`, matching `clang --version`'s `21.1.8` exactly
  — the versions that actually matter for binary compatibility agree.

Environment setup is real and functional: a complete LLVM 21 toolchain (compiler,
headers, build system) now exists on this machine, none of which existed before
this session (previously only a runtime-only `libllvm21` shared library, pulled in
as some other package's dependency, was present).

## `riscv64-unknown-elf-gdb` — real fix deferred, not silently dropped

The plan's own original guess ("likely `apt install libpython3.12`") was checked
live and found **wrong**: this machine's configured apt repository (Ubuntu
`resolute`) has already moved past Python 3.12 entirely — `apt-cache search
python3.12` returns zero results, and no `libpython3.12` package exists in the
configured repos to install. Further verification: `readelf -d` on the gdb binary
shows a hard `NEEDED` dependency on `libpython3.12.so.1.0` with no `RPATH`/`RUNPATH`
set (relies entirely on the system's normal dynamic-linker search path), and the
`riscv-collab-gcc` toolchain distribution does not bundle its own copy of this
library anywhere alongside the binary. The actual `.so` file's real bytes do exist
on this machine, but only inside Canonical's own snap-package mounts (the `gnome-46
-2404` and `libreoffice` snaps each carry their own private copy) — symlinking one
of those into the system library path would technically work but is fragile (tied
to a snap revision that can silently change or disappear on `snap refresh`).

**Decision**: defer the real fix to Toolchain Milestone 3, when a working
`riscv64-unknown-elf-gdb` client is actually needed for the first time (to `target
remote` into the new GDB stub). At that point, investigate the more durable real
options — fetching an actual Ubuntu-archived `libpython3.12` `.deb` from
`old-releases.ubuntu.com` (or wherever the real, correct archive for this release
turns out to be, verified rather than guessed), or rebuilding `gdb` from source
linked against the currently-installed Python 3.14 — rather than reaching for the
fragile snap-symlink workaround now, before it's actually blocking anything.

## Done / not done

- LLVM/Clang/cmake/ninja: **done, verified**.
- `gdb` fix: **explicitly deferred to Toolchain Milestone 3**, not silently
  skipped — tracked there as a real, open precondition.
