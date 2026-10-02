# zsh plugin entry point for gwt: sources the core and registers completion.
# Works whether the plugin manager runs compinit before or after loading it.

0=${${ZERO:-${0:#$ZSH_ARGZERO}}:-${(%):-%N}}
0=${${(M)0:#/*}:-$PWD/$0}

source "${0:h}/gwt.sh"

(( ${fpath[(Ie)${0:h}/completions]} )) || fpath+=("${0:h}/completions")
if (( $+functions[compdef] )); then
  autoload -Uz _gwt
  compdef _gwt gwt
fi
