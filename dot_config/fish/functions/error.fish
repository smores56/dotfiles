function error --description "Print error to stderr"
    echo (tput setaf 1)"error: $argv"(tput sgr0) 1>&2
    return 1
end
