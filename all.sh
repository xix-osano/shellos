#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

#-------------------------------------------------------------------------------
# 0. Prompt for Git user info
#-------------------------------------------------------------------------------

# Ensure we have gum available
if ! command -v gum &>/dev/null; then
  sudo pacman -S --needed --noconfirm gum
fi

# Prompt for Git identity
SHELLOS_USER_NAME=$(gum input --prompt "  Enter your Git username: " --placeholder "Your name")
SHELLOS_USER_EMAIL=$(gum input --prompt "  Enter your Git email: " --placeholder "you@example.com")

# Confirm identity visually
gum style --border normal --margin "1 2" --padding "1 3" --border-foreground 212 \
  "Git Identity Configuration:" \
  "\n    Name : $SHELLOS_USER_NAME" \
  "\n    Email: $SHELLOS_USER_EMAIL"

gum confirm "Proceed with these settings?" || exit 1

#-------------------------------------------------------------------------------
# 1. Define Shellos locations
#-------------------------------------------------------------------------------
export SHELLOS_PATH="$HOME/.local/share/shellos"
export SHELLOS_INSTALL="$SHELLOS_PATH/install"
export SHELLOS_INSTALL_LOG_FILE="/var/log/shellos-install.log"
export PATH="$SHELLOS_PATH/bin:$PATH"
export SHELLOS_USER_NAME
export SHELLOS_USER_EMAIL

#-------------------------------------------------------------------------------
# 2. Begin modular installation
#-------------------------------------------------------------------------------
source "$SHELLOS_INSTALL/helpers/all.sh"
source "$SHELLOS_INSTALL/preflight/all.sh"
source "$SHELLOS_INSTALL/packaging/all.sh"
source "$SHELLOS_INSTALL/config/all.sh"
source "$SHELLOS_INSTALL/login/all.sh"
source "$SHELLOS_INSTALL/post-install/all.sh"