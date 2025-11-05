if [ "$(plymouth-set-default-theme)" != "shellos" ]; then
  sudo cp -r "$HOME/.local/share/shellos/default/plymouth" /usr/share/plymouth/themes/shellos/
  sudo plymouth-set-default-theme shellos
fi
