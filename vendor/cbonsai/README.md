# cbonsai

Vendored from upstream tag `v1.4.2`:

- <https://gitlab.com/jallbrit/cbonsai>
- commit `06b06f0d23ba194a89319cd98d0ad83c5500d258`
- upstream `cbonsai.c` sha256 `7a1900d505fb3947356b4e9f99fa8a8bf42d3e69fe7fdbc5eaa33ca3d2488fe4`
- local patch: `printstdscr` treats the default color pair's `-1` foreground as
  reset; upstream emitted `ESC[3-1m`, which terminals rendered as a stray `m`
  between cells. Patched file sha256
  `3d74a154447a14b93e3c7d868eea51c5ccb770d8454de8f3541d887e89eb2622`.

Only `cbonsai.c` and `LICENSE` are copied. The man page, completions, tests,
and Makefile are not; the Makefile only adds scdoc and install steps, and the
version is the tag recorded above.

cbonsai is GPL-3.0-or-later; see `LICENSE`.
