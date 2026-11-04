# Autocomplétion bash de la commande `agents` (noms des agents = sessions screen de la VM).
_agents() {
  local cur="${COMP_WORDS[COMP_CWORD]}" prev="${COMP_WORDS[COMP_CWORD-1]}"
  local subs="ls new attach title rm help"
  if [ "$COMP_CWORD" -eq 1 ]; then
    COMPREPLY=( $(compgen -W "$subs $(agents _names 2>/dev/null)" -- "$cur") )
  elif [ "$COMP_CWORD" -eq 2 ]; then
    case "$prev" in
      attach|title|rm|new) COMPREPLY=( $(compgen -W "$(agents _names 2>/dev/null)" -- "$cur") ) ;;
    esac
  fi
}
complete -F _agents agents
