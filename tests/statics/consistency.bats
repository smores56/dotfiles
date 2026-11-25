#!/usr/bin/env bats
# Cross-file consistency: the checkout root, the clean-bare clone, the git get
# instructions, the SDLC registries, and the ssh agent forwarding.
load ../helpers

@test "the checkout root matches in repos_root, bootstrap, and the link script" {
    var_root=$(sed -n 's|^repos_root = "\(/[^"]*\)"$|\1|p' "$dotfiles_root/mise.identity.toml" | head -1)
    boot_root=$(sed -n 's|^ROOT=${BOOTSTRAP_ROOT:-\(/[^}]*\)}$|\1|p' "$dotfiles_root/scripts/bootstrap.sh" | head -1)
    link_root=$(sed -n 's|^checkout=${DOTFILES_CHECKOUT:-\(/srv/git\)/.*|\1|p' \
        "$dotfiles_root/scripts/link-dotfiles-checkout.sh" | head -1)
    run test -n "$var_root" -a "$var_root" = "$boot_root" -a "$var_root" = "$link_root"
    assert_success
}

@test "bootstrap and git get make the same clean-bare clone, on personal machines only" {
    run sh -c "grep -qF 'git clone --bare -c remote.origin.fetch=' '$dotfiles_root/scripts/bootstrap.sh' \
        && grep -qF 'git clone --bare -c remote.origin.fetch=' '$dotfiles_root/identity/.config/git/machine.inc.tera' \
        && ! grep -q '{{ vars.repos_root }}' '$dotfiles_root/work/.config/git/machine.inc.tera'"
    assert_success
}

@test "the agent docs tell agents to clone with git get" {
    offenders=''
    for doc in "$dotfiles_root/home/.claude/CLAUDE.md" "$dotfiles_root/home/.config/maki/AGENTS.md"; do
        grep -qF '`git get <owner/repo>`' "$doc" || offenders="$offenders ${doc#"$dotfiles_root"/}"
    done
    assert_equal "$offenders" ""
}

@test "the personal SDLC registry is hardcoded" {
    run grep -q 'SDLC_REPO=smores56/sdlc' "$dotfiles_root/home/.config/shell/env.sh"
    assert_success
}

@test "the work SDLC registry is hardcoded" {
    run grep -q 'SDLC_REPO=smohr-blitzy/sdlc' "$dotfiles_root/work/.config/shell/env.d/work.sh"
    assert_success
}

# sudo's touch factor is a signature from the client's agent, so the agent has to
# travel with the session (design #767). Scoped to the smortress host and never a
# global default: the forwarded socket is a signature oracle that any process
# running as the login user on the far end can drive.
@test "ForwardAgent is scoped to the smortress route" {
    run sh -c "[ \"\$(grep -cx '    ForwardAgent yes' '$dotfiles_root/home/.ssh/smortress.conf')\" = 1 ] \
     && ! grep -qi forwardagent '$dotfiles_root/work/.ssh/config'"
    assert_success
}

# A session that joins an existing ControlMaster cannot add agent forwarding, and
# the forwarded socket is what pam_rssh authenticates against, so multiplexing
# here fails as a silent password prompt.
@test "smortress never multiplexes, so the agent is really forwarded" {
    run sh -c "[ \"\$(grep -cx '    ControlMaster no' '$dotfiles_root/home/.ssh/smortress.conf')\" = 1 ]"
    assert_success
}
