# Autocomplétion fish de la commande `agents`.
complete -c agents -f
complete -c agents -n '__fish_use_subcommand' -a 'ls new attach title rm help'
complete -c agents -n '__fish_use_subcommand' -a '(agents _names 2>/dev/null)'
complete -c agents -n '__fish_seen_subcommand_from attach title rm new' -a '(agents _names 2>/dev/null)'
