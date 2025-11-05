# Copy over ShellOS configs
mkdir -p ~/.config
cp -R ~/.local/share/shellos/config/* ~/.config/

# Use default bashrc from ShellOS
cp ~/.local/share/shellos/default/bashrc ~/.bashrc
