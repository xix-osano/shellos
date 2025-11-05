#!/usr/bin/env bash

#-------------------------------------------------------------------------------
# 0. Basics
#-------------------------------------------------------------------------------
EFI=false
[[ -d /sys/firmware/efi ]] && EFI=true
BOOTMODE=$([[ $EFI == true ]] && echo "UEFI" || echo "BIOS")

GRUB_CFG=/etc/default/grub
GRUB_DST=/boot/grub/grub.cfg
THEME_SRC="$HOME/.local/share/shellos/install/Vixy"
THEME_DST=/boot/grub/themes/Vixy

#-------------------------------------------------------------------------------
# 1. Helpers
#-------------------------------------------------------------------------------
backup_grub() {
  local ts=$(date +%Y%m%d%H%M%S)
  sudo cp "$GRUB_CFG" "${GRUB_CFG}.bak.${ts}"
  echo "Backed up $GRUB_CFG → ${GRUB_CFG}.bak.${ts}"
}

# idempotent key=value editor
set_grub() {
  local key=$1 val=$2
  if grep -q "^${key}=" "$GRUB_CFG"; then
    sudo sed -i "s|^${key}=.*|${key}=${val}|" "$GRUB_CFG"
  else
    echo "${key}=${val}" | sudo tee -a "$GRUB_CFG" > /dev/null
  fi
}

#-------------------------------------------------------------------------------
# 2. GRUB packages & installation
#-------------------------------------------------------------------------------
echo -e "\e[34m==> Installing GRUB (${BOOTMODE}) …\e[0m"

pkg=(grub snapper inotify-tools grub-btrfs)
$EFI && pkg+=(efibootmgr)
sudo pacman -S --noconfirm --needed "${pkg[@]}"

# mkinitcpio hooks
sudo tee /etc/mkinitcpio.conf.d/shellos_hooks.conf >/dev/null <<'EOF'
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs)
EOF

# install boot loader
if $EFI; then
  sudo grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --modules="tpm" --disable-shim-lock --recheck
else
  DISK=$(lsblk -no pkname "$(findmnt -n -o SOURCE /)")
  sudo grub-install --target=i386-pc "/dev/$DISK"
fi

#-------------------------------------------------------------------------------
# 3. Snapper configs
#-------------------------------------------------------------------------------
for pair in /:root /home:home; do
  dir="${pair%%:*}"     # before colon
  snapcfg="${pair##*:}" # after colon

  [[ -d "$dir" ]] || continue
  sudo snapper list-configs | grep -qw "$snapcfg" && continue
  sudo snapper -c "$snapcfg" create-config "$dir"
done

# tighten retention
for cfg in /etc/snapper/configs/{root,home}; do
  [[ -f $cfg ]] || continue
  sudo sed -i -E 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' "$cfg"
  sudo sed -i -E 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="10"/' "$cfg"
  sudo sed -i -E 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="10"/' "$cfg"
done
#-------------------------------------------------------------------------------
# 4. GRUB tuning
#-------------------------------------------------------------------------------
[[ -f $GRUB_CFG ]] && backup_grub

# theme
if [[ -d $THEME_SRC ]]; then
  sudo mkdir -p "$(dirname "$THEME_DST")"
  sudo cp -r "$THEME_SRC" "$THEME_DST"
else
  echo "Theme not found at $THEME_SRC — skipping theme setup."
fi

set_grub GRUB_THEME "\"$THEME_DST/theme.txt\""
set_grub GRUB_GFXMODE '"1920x1080,auto"'
set_grub GRUB_BTRFS_SHOW_SNAPSHOTS_SUBMENU '"y"'

# kernel cmdline
CMD=$(sudo grep -m1 '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CFG" | cut -d'"' -f2)
for word in splash quiet; do
  [[ $CMD =~ $word ]] && continue
  CMD+=" $word"
done
set_grub GRUB_CMDLINE_LINUX_DEFAULT "\"${CMD# }\""

#-------------------------------------------------------------------------------
# 5. Finalise
#-------------------------------------------------------------------------------
sudo systemctl enable --now grub-btrfsd.service
sudo grub-mkconfig -o /boot/grub/grub.cfg

echo -e "\e[32m==> GRUB + Snapper ready.\e[0m"
echo "   Snapshots will appear in the submenu ‘Arch Linux Snapshots’."
echo "   Re-run ‘grub-mkconfig -o $GRUB_DST’ after manual snapshots."