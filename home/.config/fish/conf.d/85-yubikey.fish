# Every machine, but inert without a YubiKey it can talk to: ykman needs PC/SC,
# and only the work Mac installs it. A code is minted here and
# inserted at the prompt, so the touch happens where the human is. Alt+o is
# unbound in fish's defaults.
status is-interactive; or return
command -q ykman; or return

function smortress-totp --description 'insert the smortress sudo TOTP code'
    set -l code (command ykman oath accounts code -s smortress 2>/dev/null)
    test -n "$code"; or return
    commandline -i -- $code
end

bind \eo smortress-totp
