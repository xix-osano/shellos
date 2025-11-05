source $SHELLOS_INSTALL/preflight/guard.sh
source $SHELLOS_INSTALL/preflight/begin.sh
run_logged $SHELLOS_INSTALL/preflight/show-env.sh
run_logged $SHELLOS_INSTALL/preflight/pacman.sh
run_logged $SHELLOS_INSTALL/preflight/migrations.sh
run_logged $SHELLOS_INSTALL/preflight/disable-mkinitcpio.sh
