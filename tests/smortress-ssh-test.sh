#!/usr/bin/env bash
# Behavioural tests for ~/.local/bin/smortress-ssh, ssh's ProxyCommand for
# smortress: the Access service token must reach cloudflared's environment and
# nothing else, and a token file other accounts can read must be refused.
set -uo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
wrapper=$root/home/.local/bin/smortress-ssh
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'ok   %s\n' "$*"; }
no() { fail=$((fail + 1)); printf 'FAIL %s\n' "$*" >&2; }

mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

mkdir -p "$tmp/bin" "$tmp/home" "$tmp/config/cloudflare"
env_file=$tmp/config/cloudflare/access.env

cat >"$tmp/bin/cloudflared" <<'EOF'
#!/bin/sh
printf 'args:%s\n' "$*" >>"$CF_LOG"
printf 'id:%s\n' "${TUNNEL_SERVICE_TOKEN_ID-}" >>"$CF_LOG"
printf 'secret:%s\n' "${TUNNEL_SERVICE_TOKEN_SECRET-}" >>"$CF_LOG"
EOF
chmod +x "$tmp/bin/cloudflared"

# PATH without cloudflared, so the missing-client case is reachable.
bare_bin=$tmp/bare
mkdir -p "$bare_bin"
ln -sf /usr/bin/sed "$bare_bin/sed"
ln -sf /usr/bin/head "$bare_bin/head"
ln -sf /usr/bin/tr "$bare_bin/tr"

run() {
    env -i HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
        PATH="${RUN_PATH:-$tmp/bin:/usr/bin:/bin}" CF_LOG="$tmp/log" \
        "$wrapper" "$@"
}

# 1. No token file: fail with the path and the script that writes it.
if out=$(run 2>&1); then
    no "a missing token file fails"
else
    ok "a missing token file fails"
fi
case $out in
    *"no Access service token at $env_file"*) ok "the failure names the token file" ;;
    *) no "the failure names the token file (got '$out')" ;;
esac

# 2. A token file another account can read is refused, not used.
printf 'CLOUDFLARE_ACCESS_CLIENT_ID=id\n' >"$env_file"
printf 'CLOUDFLARE_ACCESS_CLIENT_SECRET=secret-value\n' >>"$env_file"
chmod 644 "$env_file"
if out=$(run 2>&1); then
    no "a group- or world-readable token file is refused"
else
    ok "a group- or world-readable token file is refused"
fi
case $out in
    *"is mode 644, not 600"*) ok "the failure names the mode" ;;
    *) no "the failure names the mode (got '$out')" ;;
esac

# 3. A mode-600 token file reaches cloudflared's environment only.
chmod 600 "$env_file"
: >"$tmp/log"
if run 2>"$tmp/err"; then
    ok "a provisioned wrapper execs cloudflared"
else
    no "a provisioned wrapper execs cloudflared"
    sed 's/^/     /' "$tmp/err" >&2
fi
grep -qx 'args:access ssh --hostname ssh.sammohr.dev' "$tmp/log" \
    && ok "cloudflared gets the Access transport and the default host" \
    || no "cloudflared gets the Access transport and the default host ($(sed -n 1p "$tmp/log"))"
grep -qx 'id:id' "$tmp/log" && ok "the client id reaches cloudflared" \
    || no "the client id reaches cloudflared"
grep -qx 'secret:secret-value' "$tmp/log" && ok "the secret reaches cloudflared" \
    || no "the secret reaches cloudflared"
# ssh passes the hostname it resolved from ~/.ssh/smortress.conf.
: >"$tmp/log"
run ssh.sammohr.dev >/dev/null 2>&1
grep -q 'args:access ssh --hostname ssh.sammohr.dev' "$tmp/log" \
    && ok "the hostname argument reaches cloudflared" \
    || no "the hostname argument reaches cloudflared"

# 4. The secret is never an argument, where `ps` would show it.
if grep '^args:' "$tmp/log" | grep -q 'secret-value'; then
    no "the secret stays out of cloudflared's argv"
else
    ok "the secret stays out of cloudflared's argv"
fi

# 5. exec replaces the wrapper, so the ssh that ran it keeps a clean env.
exported=$(env -i HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/config" \
    PATH="$tmp/bin:/usr/bin:/bin" CF_LOG="$tmp/log" \
    sh -c '"$1" >/dev/null 2>&1; env' sh "$wrapper" | grep -c '^TUNNEL_SERVICE_TOKEN' || true)
if [ "$exported" = 0 ]; then
    ok "the token never enters the caller's environment"
else
    no "the token never enters the caller's environment"
fi

# 6. An incomplete token file is an error, not a browser login prompt.
printf 'CLOUDFLARE_ACCESS_CLIENT_ID=id\n' >"$env_file"
chmod 600 "$env_file"
if out=$(run 2>&1); then
    no "a token file without a secret fails"
else
    ok "a token file without a secret fails"
fi

# 7. Without cloudflared the wrapper points at the bootstrap.
[ "$(mode_of "$env_file")" = 600 ] || chmod 600 "$env_file"
if out=$(RUN_PATH=$bare_bin run 2>&1); then
    no "a missing cloudflared fails"
else
    ok "a missing cloudflared fails"
fi
case $out in
    *'cloudflared is not on PATH'*) ok "the failure points at mise bootstrap" ;;
    *) no "the failure points at mise bootstrap (got '$out')" ;;
esac

# 8. The shared block offers both halves of the login. `IdentitiesOnly yes` means
# ssh tries no key this block does not name, so a dropped line removes that key
# from the route silently. Parsed with `ssh -G`, which is the same resolution ssh
# performs before it offers anything.
if command -v ssh >/dev/null 2>&1; then
    conf=$root/home/.ssh/smortress.conf
    resolved=$(ssh -G -F "$conf" smortress 2>/dev/null)
    identities=$(printf '%s\n' "$resolved" | sed -n 's/^identityfile //p')
    # ssh -G prints the paths as written, so the expectations keep their tilde.
    tilde='~'
    sk=$tilde/.ssh/id_smortress
    file_key=$tilde/.ssh/id_smortress-access
    for key in "$sk" "$file_key"; do
        if printf '%s\n' "$identities" | grep -qxF "$key"; then
            ok "the ssh block offers $key"
        else
            no "the ssh block offers $key (offered: $(printf '%s' "$identities" | tr '\n' ' '))"
        fi
    done
    # The resident handle is the hardware key, so it is tried first; the file key
    # answers only when the token cannot sign.
    if [ "$(printf '%s\n' "$identities" | sed -n 1p)" = "$sk" ]; then
        ok "the ssh block tries the resident handle first"
    else
        no "the ssh block tries the resident handle first (first: $(printf '%s\n' "$identities" | sed -n 1p))"
    fi
    # Without this, ssh would also offer every agent key, and the AND property in
    # the header would not hold.
    if printf '%s\n' "$resolved" | grep -qx 'identitiesonly yes'; then
        ok "the ssh block offers nothing beyond its own keys"
    else
        no "the ssh block offers nothing beyond its own keys"
    fi
else
    printf 'skip identity assertions: ssh is not installed\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
