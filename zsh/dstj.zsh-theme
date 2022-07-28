ZSH_THEME_GIT_PROMPT_PREFIX="%{$fg[green]%}"
ZSH_THEME_GIT_PROMPT_SUFFIX="%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[red]%}*!"
ZSH_THEME_GIT_PROMPT_CLEAN=""

PATH_LEN=$(( COLUMNS - ${#${(%n@%M):-$(git_prompt_info):---(%*):-}} ))

function prompt_char {
	if [ $UID -eq 0 ]; then echo "%{$fg[red]%}#%{$reset_color%}"; else echo $; fi
}

PROMPT='%(?, ,%{$fg[red]%}FAIL: $?%{$reset_color%}
)
'
PROMPT+='%{$fg[magenta]%}%n%{$reset_color%}@%{$fg[yellow]%}%m%{$reset_color%}'
PROMPT+='%{$fg_bold[blue]%} %$PATH_LEN<...*<%~%<< %{$reset_color%}'
PROMPT+='$(git_prompt_info)%{$reset_color%}'
PROMPT+='
$(prompt_char) '

RPROMPT='%{$(echotc UP 1)%}%{$fg[cyan]%}%*%{$(echotc DO 1)%}'
