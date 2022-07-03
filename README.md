# Installation

## git settings
	ln -s ~/.jyny/git/gitconfig ~/.gitconfig

## vim settings
	ln -s ~/.jyny/vim/vimrc ~/.vimrc

## tmux settings
	ln -s ~/.jyny/tmux/tmux.conf ~/.tmux.conf

## zsh settings
	ln -s ~/.jyny/zsh/zshrc ~/.zshrc
	ln -s ~/.jyny/zsh/zprofile ~/.zprofile

## htop settings
	ln -s ~/.jyny/htop/htoprc ~/.config/htop/htoprc

## ssh-agnet
	ln -s ~/.jyny/ssh-agent/ssh-agent.service ~/.config/systemd/user/ssh-agent.service
	systemctl enable --now --user ssh-agent
