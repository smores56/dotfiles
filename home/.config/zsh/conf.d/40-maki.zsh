# Maki's provider keys live outside the repository in ~/.config/secrets.env
# (mode 600, NAME=value lines). They are passed to the maki process only, so
# no other command from this shell inherits them, and nothing prints a value.
maki() {
  emulate -L zsh
  local secrets=$HOME/.config/secrets.env
  if [[ ! -e $secrets ]]; then
    print -u2 "maki: $secrets is missing; the providers will reject the session"
    command maki "$@"
    return
  fi
  local mode
  zmodload -F zsh/stat b:zstat 2>/dev/null
  mode=$(zstat -L +mode -o $secrets 2>/dev/null)
  [[ -n $mode && $mode != *600 ]] && print -u2 "maki: $secrets is mode ${mode: -3}, expected 600"
  local neuralwatt= tinyfish= line name value lineno=0
  while IFS= read -r line || [[ -n $line ]]; do
    (( lineno++ ))
    [[ $line == [[:space:]]#(\#*|) ]] && continue
    if [[ $line != *=* ]]; then
      print -u2 "maki: $secrets:$lineno: skipped (no =)"
      continue
    fi
    name=${${line%%=*}//[[:space:]]/}
    value=${${line#*=}##[[:space:]]#}
    value=${value%%[[:space:]]#}
    # One layer of matching quotes is cosmetic.
    [[ $value == \"*\" || $value == \'*\' ]] && value=${value[2,-2]}
    case $name in
      NEURALWATT_API_KEY) neuralwatt=$value ;;
      TINYFISH_API_KEY) tinyfish=$value ;;
      *) print -u2 "maki: $secrets:$lineno: skipped ($name is not a Maki provider key)" ;;
    esac
  done <$secrets
  NEURALWATT_API_KEY=$neuralwatt TINYFISH_API_KEY=$tinyfish command maki "$@"
}
