# Interactive startup only.
#
# Nothing here may touch the network: a login shell has to work offline, on a
# fresh machine, and inside a container before mise has installed anything.
# Everything that configures the environment lives in conf.d/*.fish.
if status is-interactive
    set -g fish_greeting
end
