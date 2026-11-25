#!/usr/bin/env bats
# The global lockfiles cover every pinned tool on every platform it runs on.
load ../helpers

lock_coverage() {
    python3 - "$dotfiles_root/global" <<'PY'
import pathlib, sys, tomllib
root = pathlib.Path(sys.argv[1])
all_platforms = {"linux-x64", "linux-arm64", "macos-arm64"}
os_platforms = {"linux": {"linux-x64", "linux-arm64"}, "macos": {"macos-arm64"}}
missing = []
for config in sorted(root.glob("config*.toml")):
    env = config.stem.removeprefix("config").lstrip(".")
    lock_path = root / (f"mise.{env}.lock" if env else "mise.lock")
    tools = tomllib.loads(config.read_text()).get("tools", {})
    locked = tomllib.loads(lock_path.read_text()).get("tools", {}) if lock_path.exists() else {}
    for name, spec in tools.items():
        # `platforms` is this check's key, not mise's: a tool upstream does not
        # build for every architecture in its os list names what it publishes.
        if isinstance(spec, dict) and "platforms" in spec:
            want = set(spec["platforms"])
        elif isinstance(spec, dict) and "os" in spec:
            want = set().union(*(os_platforms[o] for o in spec["os"]))
        else:
            want = all_platforms
        pin = spec["version"] if isinstance(spec, dict) else spec
        entries = [e for e in locked.get(name, []) if e.get("version") == pin]
        if not entries:
            missing.append(f"{config.name}: {name} = {pin} is not in {lock_path.name} (stale lock?)")
            continue
        have = {p.removeprefix("platforms.") for e in entries for p, v in e.items()
                if p.startswith("platforms.") and isinstance(v, dict) and v.get("checksum")}
        # mise records only the version for pipx tools; a uv lock pins them by hash.
        if name.startswith("pipx:"):
            uv_lock = root / "locks" / name.replace(":", "-") / pin / "uv.lock"
            text = uv_lock.read_text() if uv_lock.exists() else ""
            if f'version = "{pin}"' not in text or "sha256:" not in text:
                missing.append(f"{config.name}: {name} = {pin} has no hashed uv lock at {uv_lock.relative_to(root)}")
            continue
        for platform in sorted(want - have):
            missing.append(f"{config.name}: {name} has no checksummed {platform} entry in {lock_path.name}")
print("\n".join(missing))
sys.exit(1 if missing else 0)
PY
}

@test "the global lockfiles cover every pinned tool on its platforms" {
    python3 -c 'import tomllib' >/dev/null 2>&1 || skip "python3 tomllib missing"
    run lock_coverage
    assert_success
}
