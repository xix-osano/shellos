# Ensure iwd service will be started
sudo systemctl enable iwd.service

# Install and enable NetworkManager
sudo pacman -S --needed --noconfirm networkmanager
sudo systemctl enable --now NetworkManager

# Disable systemd-networkd to avoid conflicts with NetworkManager
sudo systemctl disable --now systemd-networkd.service 2>/dev/null || true
sudo systemctl mask systemd-networkd.service 2>/dev/null || true

# Prevent NetworkManager-wait-online timeout on boot
sudo systemctl disable NetworkManager-wait-online.service
sudo systemctl mask NetworkManager-wait-online.service

# Integrating systemd-resolved & networkmanager for DNS management
echo "Symlink resolved stub-resolv to /etc/resolv.conf"
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sudo mkdir -p "/etc/NetworkManager/conf.d"
if ! sudo grep -q "dns=systemd-resolved" "/etc/NetworkManager/conf.d/resolved.conf" 2>/dev/null; then
  echo "Pointing NetworkManager to systemd-resolved …"
  printf "%s\n" "[main]" "dns=systemd-resolved" | sudo tee "/etc/NetworkManager/conf.d/resolved.conf" >/dev/null
  sudo systemctl restart NetworkManager
  echo "NetworkManager restarted successfully."
fi

# Prevent network conflicts with iwd
# sudo mkdir -p /etc/NetworkManager/conf.d
# sudo tee /etc/NetworkManager/conf.d/20-iwd.conf >/dev/null <<EOF
# [device]
# wifi.backend=iwd
# EOF
# sudo systemctl restart NetworkManager.service


