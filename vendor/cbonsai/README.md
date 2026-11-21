# cbonsai

Vendored from upstream tag `v1.4.2`:

- <https://gitlab.com/jallbrit/cbonsai>
- commit `06b06f0d23ba194a89319cd98d0ad83c5500d258`
- `cbonsai.c` sha256 `7a1900d505fb3947356b4e9f99fa8a8bf42d3e69fe7fdbc5eaa33ca3d2488fe4`

Only `cbonsai.c` and `LICENSE` are copied. The man page, completions, tests,
and Makefile are not. `scripts/build-cbonsai.sh` passes the version on the
command line because upstream's Makefile derives it from `git describe`, which
a vendored copy has no access to.

cbonsai is GPL-3.0-or-later; see `LICENSE`.
