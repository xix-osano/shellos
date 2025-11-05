echo "============================================"
echo "     Archy Linux Lazyvim Setup"
echo "============================================"
echo

# ---------- config ----------
LAZYVIM_REPO="https://github.com/LazyVim/starter"
# ----------------------------

command -v nvim >/dev/null || {
  echo "==> Installing neovim ..."
  sudo pacman -S --needed --noconfirm neovim
}

conf_dir="$HOME/.config/nvim"
backup_dir="${conf_dir}.bak.$(date +%Y%m%d%H%M%S)"

if [[ -d "$conf_dir" ]]; then
  sudo mv "$conf_dir" "$backup_dir"
fi

# ==> Cloning LazyVim starter
git clone --depth=1 "$LAZYVIM_REPO" "$conf_dir"

# remove the upstream .git so it becomes *your* dot-folder
sudo rm -rf "$conf_dir/.git"

# --- Launch Neovim to trigger bootstrap ---
nvim --headless "+Lazy! sync" +qa

# -------------- Done -------------------------
echo "✔ LazyVim installed."
echo "  Open nvim once to download plugins / LSP / treesitter"
echo "  Then read the docs inside"
