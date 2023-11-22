# Installation

## git settings
	ln -s ~/.jyny/git/gitconfig ~/.gitconfig
	ln -s ~/.jyny/git/gitignore_global ~/.gitignore_global

## vim settings
	ln -s ~/.jyny/vim/vimrc ~/.vimrc

## tmux settings
	ln -s ~/.jyny/tmux/tmux.conf ~/.tmux.conf

## zsh settings
	ln -s ~/.jyny/zsh/dstj.zsh-theme ~/.oh-my-zsh/themes/dstj.zsh-theme
	ln -s ~/.jyny/zsh/zshrc ~/.zshrc

## htop settings
	ln -s ~/.jyny/htop/htoprc ~/.config/htop/htoprc

## vscode

### settings
	ln -s ~/.jyny/vscode/settings.json ~/Library/Application\ Support/Code/User/settings.json
	New-Item -ItemType SymbolicLink -Path "~/.jyny/vscode/settings.json" -Target "%APPDATA%\Code\User\settings.json"

### extensions
	code --list-extensions > ~/.jyny/vscode/extensions.list

	cat ~/.jyny/vscode/extensions.list | xargs -L 1 echo code --install-extension
	cat ~/.jyny/vscode/extensions.list | % { "code --install-extension $_" }