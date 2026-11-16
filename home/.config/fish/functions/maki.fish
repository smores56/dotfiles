# Maki's provider keys live outside the repository: ~/.config/secrets.env,
# mode 600, plain NAME=value lines. They are exported into the `maki` process
# only, so no other command started from this shell inherits them, and nothing
# prints a value.
function maki --description 'run Maki with the provider keys from ~/.config/secrets.env'
    set -l secrets $HOME/.config/secrets.env
    set -l neuralwatt ""
    set -l tinyfish ""
    if not test -e $secrets
        printf 'maki: %s is missing; the providers will reject the session\n' $secrets >&2
        command maki $argv
        return $status
    end
    set -l mode (stat -c %a $secrets 2>/dev/null; or stat -f %Lp $secrets 2>/dev/null)
    if test -n "$mode"; and test "$mode" != 600
        printf 'maki: %s is mode %s, expected 600\n' $secrets $mode >&2
    end
    set -l lineno 0
    for line in (string split \n -- (string collect <$secrets))
        set lineno (math $lineno + 1)
        string match -qr '^\s*(#|$)' -- $line; and continue
        set -l pair (string split -m1 = -- $line)
        if test (count $pair) -ne 2
            printf 'maki: %s:%s: skipped (no =)\n' $secrets $lineno >&2
            continue
        end
        set -l name (string trim -- $pair[1])
        set -l value (string trim -- $pair[2])
        # One layer of matching quotes is cosmetic; the value is what is inside.
        if string match -qr '^".*"$' -- $value; or string match -qr "^'.*'\$" -- $value
            set value (string sub -s 2 -e -1 -- $value)
        end
        switch $name
            case NEURALWATT_API_KEY
                set neuralwatt $value
            case TINYFISH_API_KEY
                set tinyfish $value
            case '*'
                printf 'maki: %s:%s: skipped (%s is not a Maki provider key)\n' \
                    $secrets $lineno $name >&2
        end
    end
    set -lx NEURALWATT_API_KEY $neuralwatt
    set -lx TINYFISH_API_KEY $tinyfish
    command maki $argv
end
