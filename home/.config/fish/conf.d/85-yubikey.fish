# Every machine, but inert without a YubiKey it can talk to: ykman needs PC/SC,
# and only the work Mac installs it. Alt+o is unbound in fish's defaults.
#
# What it does: at a fish prompt it inserts the current code into the edit
# buffer, so the human taps the key and types nothing. What it cannot do:
# answer sudo's prompt, where fish is not reading the terminal, so the code must
# be typed there by hand (or copied from `ykman oath accounts code -s
# smortress`).
status is-interactive; or return
command -q ykman; or return

function smortress-totp --description 'insert the smortress sudo TOTP code'
    set -l code (command ykman oath accounts code -s smortress 2>/dev/null)
    test -n "$code"; or return
    commandline -i -- $code
end

bind \eo smortress-totp
