#!/usr/bin/env bash
# ~/.local/bin/smortress-ssh, ssh's ProxyCommand for smortress: the Access
# service token must reach cloudflared's environment and nothing else, and a
# token file other accounts can read must be refused.
set -uo pipefail
# shellcheck source=tests/lib.sh
. "$(dirname -- "$0")/lib.sh"

wrapper=$root/home/.local/bin/smortress-ssh
mkdir -p "$tmp/bin" "$tmp/home" "$tmp/config/cloudflare"
env_file=$tmp/config/cloudflare/access.env

cat >"$tmp/bin/cloudflared" <<'EOF'
#!/bin/sh
printf 'args:%s\n' "$*" >>"$CF_LOG"
printf 'id:%s\n' "${TUNNEL_SERVICE_TOKEN_ID-}" >>"$CF_LOG"
printf 'secret:%s\n' "${TUNNEL_SERVICE_TOKEN_SECRET-}" >>"$CF_LOG"
EOF
chmod +x "$tmp/bin/cloudflared"

# A PATH without cloudflared, so the missing-client case is reachable.
bare_bin=$tmp/bare
mkdir -p "$bare_bin"
ln -sf /usr/bin/sed /usr/bin/head /usr/bin/tr "$bare_bin/"

run() {
    env -i HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
        PATH="${RUN_PATH:-$tmp/bin:/usr/bin:/bin}" CF_LOG="$tmp/log" \
        "$wrapper" "$@"
}
logged() { grep -qx "$1" "$tmp/log"; }

assert_not "a missing token file fails" run
contains "the failure names the token file" "no Access service token at $env_file" "$out"

printf 'CLOUDFLARE_ACCESS_CLIENT_ID=id\nCLOUDFLARE_ACCESS_CLIENT_SECRET=secret-value\n' >"$env_file"
chmod 644 "$env_file"
assert_not "a group- or world-readable token file is refused" run
contains "the failure names the mode" "is mode 644, not 600" "$out"

chmod 600 "$env_file"
: >"$tmp/log"
assert "a provisioned wrapper execs cloudflared" run
assert "cloudflared gets the Access transport and the default host" \
    logged 'args:access ssh --hostname ssh.sammohr.dev'
assert "the client id reaches cloudflared" logged 'id:id'
assert "the secret reaches cloudflared" logged 'secret:secret-value'
# ssh passes the hostname it resolved from ~/.ssh/smortress.conf.
: >"$tmp/log"
run ssh.sammohr.dev >/dev/null 2>&1
assert "the hostname argument reaches cloudflared" logged 'args:access ssh --hostname ssh.sammohr.dev'
# `ps` would show an argument.
assert_not "the secret stays out of cloudflared's argv" grep -q '^args:.*secret-value' "$tmp/log"

# exec replaces the wrapper, so the ssh that ran it keeps a clean env.
expect "the token never enters the caller's environment" 0 \
    "$(env -i HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" PATH="$tmp/bin:/usr/bin:/bin" CF_LOG="$tmp/log" \
        sh -c '"$1" >/dev/null 2>&1; env' sh "$wrapper" | grep -c '^TUNNEL_SERVICE_TOKEN')"

# An incomplete token file is an error, not a browser login prompt.
printf 'CLOUDFLARE_ACCESS_CLIENT_ID=id\n' >"$env_file"
assert_not "a token file without a secret fails" run

RUN_PATH=$bare_bin assert_not "a missing cloudflared fails" run
contains "the failure points at mise bootstrap" 'cloudflared is not on PATH' "$out"

# `IdentitiesOnly yes` means ssh tries no key the block does not name, so a
# dropped line removes that key from the route silently. `ssh -G` is the same
# resolution ssh performs before it offers anything.
conf=$root/home/.ssh/smortress.conf
if command -v ssh >/dev/null 2>&1; then
    resolved=$(ssh -G -F "$conf" smortress 2>/dev/null)
    identities=$(sed -n 's/^identityfile //p' <<<"$resolved")
    # ssh -G prints the paths as written, tilde included, and none of ssh's own
    # defaults: the block names one key and ssh offers that one.
    # shellcheck disable=SC2088
    sk='~/.ssh/id_smortress'
    expect "the tailnet block offers only the sops key" "$sk" "$identities"
    assert "the tailnet block offers nothing beyond its own keys" \
        grep -qx 'identitiesonly yes' <<<"$resolved"
    assert "the tailnet block resolves through MagicDNS" grep -qx 'hostname smortress' <<<"$resolved"
    assert "the tailnet block accepts a new host key" \
        grep -qx 'stricthostkeychecking accept-new' <<<"$resolved"
    # A ProxyCommand here would route the tailnet name back through Cloudflare.
    assert_not "the tailnet block needs no tunnel" grep -q '^proxycommand ' <<<"$resolved"

    # The tunnel block stays until the cutover: the one key secrets.sh delivers,
    # and the wrapper. A second IdentityFile here would only warn that the file
    # is missing.
    legacy=$(ssh -G -F "$conf" ssh.sammohr.dev 2>/dev/null)
    legacy_identities=$(sed -n 's/^identityfile //p' <<<"$legacy")
    expect "the tunnel block offers only the key secrets.sh delivers" \
        "$sk" "$legacy_identities"
    assert "the tunnel block offers nothing beyond its own keys" \
        grep -qx 'identitiesonly yes' <<<"$legacy"
    assert "the tunnel host still uses the wrapper" \
        grep -qxF 'proxycommand $HOME/.local/bin/smortress-ssh %h' <<<"$legacy"
else
    printf 'skip identity assertions: ssh is not installed\n'
fi

# ProxyCommand expands a fixed token list without %d, and an unknown token
# aborts the connection. $HOME works because the command runs through a shell.
assert_not "the ssh block does not use %d in ProxyCommand" grep -q 'ProxyCommand .*%d' "$conf"
assert "the ssh block reaches the wrapper through \$HOME" \
    grep -q 'ProxyCommand \$HOME/\.local/bin/smortress-ssh %h' "$conf"

finish
