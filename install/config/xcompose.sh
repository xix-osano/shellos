# Set default XCompose that is triggered with CapsLock
tee ~/.XCompose >/dev/null <<EOF
include "%H/.local/share/shellos/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$SHELLOS_USER_NAME"
<Multi_key> <space> <e> : "$SHELLOS_USER_EMAIL"
EOF
