function pick --description 'pick <tv-channel> <command…>'
    if test (count $argv) -lt 2
        echo 'usage: pick <tv-channel> <command…>' >&2
        return 2
    end
    set -l sel (tv $argv[1]); or return
    set -l sel $sel[1]
    test -n "$sel"; or return
    set -l cmd $argv[2..]
    if contains -- '{name}' $cmd
        set cmd (string replace -- '{name}' (path basename $sel) $cmd)
    else
        set -a cmd $sel
    end
    $cmd
end
