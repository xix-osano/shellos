#!/bin/bash

# Set install mode to online since install.sh is used for curl installations
export SHELLOS_ONLINE_INSTALL=true

ansi_art='
    █████████╗███╗    ███╗█████████╗███╗      ███╗      ███████████╗█████████╗
    ███╔═════╝███║    ███║███╔═════╝███║      ███║      ███╔════███║███╔═════╝
    ███║      ████  █████║███║      ███║      ███║      ███║    ███║███║
    █████████╗███ ███ ███║███████╗  ███║      ███║      ███║    ███║█████████╗
    ╚═════███║█████  ████║███╔═══╝  ███║      ███║      ███║    ███║      ███║
          ███║███╔════███║███║      ███╚═════╗███╚═════╗███║    ███║      ███║
    █████████║███║    ███║█████████╗█████████║█████████║███████████║█████████║
    ╚════════╝╚══╝    ╚══╝╚════════╝╚════════╝╚════════╝╚══════════╝╚════════╝  '

clear
echo -e "\n$ansi_art\n"

sudo pacman -Syu --noconfirm --needed git

# Use custom repo if specified, otherwise default to xix-osano/shellos
SHELLOS_REPO="${SHELLOS_REPO:-xix-osano/shellos}"

echo -e "\nCloning Shellos from: https://github.com/${SHELLOS_REPO}.git"
rm -rf ~/.local/share/shellos/
git clone "https://github.com/${SHELLOS_REPO}.git" ~/.local/share/shellos >/dev/null

# Use custom branch if instructed, otherwise default to master
SHELLOS_REF="${SHELLOS_REF:-master}"
if [[ $SHELLOS_REF != "master" ]]; then
  echo -e "\e[32mUsing branch: $SHELLOS_REF\e[0m"
  cd ~/.local/share/shellos
  git fetch origin "${SHELLOS_REF}" && git checkout "${SHELLOS_REF}"
  cd -
fi

echo -e "\nInstallation starting..."
source ~/.local/share/shellos/all.sh
