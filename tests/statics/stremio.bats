#!/usr/bin/env bats
# The Stremio quadlet: its build is a want, its image comes from a pinned vendor
# digest, and its state lives in a volume.
load ../helpers

# A hard Requires on the build would keep the server down whenever a rebuild
# fails, even with a usable image still tagged locally.
@test "the Stremio container wants, not requires, its image build" {
    run grep -qE '^Wants=.* stremio-server-build\.service' "$dotfiles_root/desktop/.config/containers/systemd/stremio-server.container"
    assert_success
}

@test "the Stremio container has no hard build dependency" {
    run grep -q '^Requires=' "$dotfiles_root/desktop/.config/containers/systemd/stremio-server.container"
    assert_failure
}

@test "the Stremio image copies server.js from a pinned vendor digest" {
    run grep -q 'docker.io/stremio/server@sha256:' "$dotfiles_root/desktop/.config/containers/systemd/Containerfile"
    assert_success
}

@test "the Stremio image asserts the ffmpeg argument rewrites" {
    run sh -c 'grep -qF "\"-fps_mode\"," "$1" && grep -qF "\"-bsf:v\"," "$1"' sh "$dotfiles_root/desktop/.config/containers/systemd/Containerfile"
    assert_success
}

@test "the Stremio unit keeps its state in a volume" {
    run grep -qx 'Volume=stremio-state.volume:/root/.stremio-server' "$dotfiles_root/desktop/.config/containers/systemd/stremio-server.container"
    assert_success
}
