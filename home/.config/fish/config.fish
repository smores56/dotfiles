# Interactive fish. The environment came from conf.d/00-env.fish and the
# abbreviations from the rest of conf.d, which fish reads before this file.
status is-interactive; or return

# Settings the plugins read when they load.
set -g async_prompt_functions _pure_prompt_git
# pure probes /proc/1/cgroup for containers, which hidepid hides on smortress.
set -g pure_enable_container_detection false
set -g __done_min_cmd_duration 10000
set -g __done_exclude '^(hx|lazygit|yazi|zellij|maki|claude|bat)\b' '^git (?!push|pull|fetch)'

# Pinned clones from mise.toml [bootstrap.repos], in load order: async-prompt
# wraps pure's prompt functions, so pure comes first. No plugin manager.
for plugin in ~/.local/share/fish-plugins/{pure,async-prompt,done}
    test -d $plugin/functions
    and set fish_function_path $fish_function_path[1] $plugin/functions $fish_function_path[2..]
    for f in $plugin/conf.d/*.fish
        source $f
    end
end

# pure's fish_title prepends the full path and repeats the command. Zellij shows
# this as the tab name, so keep only the command, capped at 30 columns; an empty
# prompt title would leave the last command in place, hence the blank.
function fish_title
    if set -q argv[1]
        echo -- (string shorten -m 30 -- $argv[1])
        return
    end
    echo -n ' '
end

command -q zoxide; and zoxide init fish --cmd c | source

function fish_greeting
    command -q pfetch; and pfetch
end
