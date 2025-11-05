# Show installation environment variables
gum log --level info "Installation Environment:"

env | grep -E "^(SHELLOS_ONLINE_INSTALL|SHELLOS_USER_NAME|SHELLOS_USER_EMAIL|USER|HOME|SHELLOS_REPO|SHELLOS_REF|SHELLOS_PATH)=" | sort | while IFS= read -r var; do
  gum log --level info "  $var"
done
