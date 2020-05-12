#!/bin/sh

REV="T_RELEASE_latest"
REPO_URL='https://github.com/Freifunk-Dresden/ffdd-server'
INSTALL_DIR='/srv/ffdd-server'

if [ "$(id -u)" -ne 0 ]; then printf 'Please run as root!\n'; exit 1 ; fi


if [ -f /usr/local/bin/uci ] && [ -f /etc/config/ffdd ]; then
	CUSTOM_REPO_URL="$(uci -qX get ffdd.sys.freifunk_repo)"
	[ -n "$CUSTOM_REPO_URL" ] && [ "$CUSTOM_REPO_URL" != "$REPO_URL" ] && REPO_URL="$CUSTOM_REPO_URL"

	CUSTOM_REV="$(uci -qX get ffdd.sys.branch)"
	[ -n "$CUSTOM_REV" ] && [ "$CUSTOM_REV" != "$REV" ] && REV="$CUSTOM_REV"
fi

cd /srv || exit 1
[ -n "$INSTALL_DIR" ] && rm -rf "$INSTALL_DIR"
git clone "$REPO_URL" "$INSTALL_DIR"
cd "$INSTALL_DIR" && git checkout "$REV"


# nvram migration
if [ -f /etc/nvram.conf ]; then
	printf '\n### migrate old nvram to uci ..\n'
	"$INSTALL_DIR"/salt/freifunk/base/uci/usr/local/bin/nvram-migration.sh

	# remove old nvram
	rm /etc/nvram.config* /etc/nvram_sample.conf /usr/local/bin/nvram
fi


salt-call state.highstate --local -l error

printf '\nPlease check the changelog for the case there are config deprecations, special update steps.\n'
printf '%s/blob/master/CHANGELOG.md\n' "$REPO_URL"

exit 0
