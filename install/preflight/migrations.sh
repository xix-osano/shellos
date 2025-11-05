SHELLOS_MIGRATIONS_STATE_PATH=~/.local/state/shellos/migrations
mkdir -p $SHELLOS_MIGRATIONS_STATE_PATH

for file in ~/.local/share/shellos/migrations/*.sh; do
  touch "$SHELLOS_MIGRATIONS_STATE_PATH/$(basename "$file")"
done
