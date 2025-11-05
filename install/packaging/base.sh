# Install all base packages
mapfile -t packages < <(grep -v '^#' "$SHELLOS_INSTALL/shellos-base.packages" | grep -v '^$')
sudo pacman -S --noconfirm --needed "${packages[@]}"
