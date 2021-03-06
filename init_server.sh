#!/usr/bin/env bash
#version="1.3.0"
REV="T_RELEASE_latest" # means git rev/branch/tag
REPO_URL='https://github.com/Infinity666/ffrz-server'
#
INSTALL_DIR='/srv/ffrz-server'
INIT_DATE_FILE='/etc/freifunk-server-initdate'
###
#
#  Freifunk Ratzeburg Server - Installation & Update Script
#
###

check_salt_repo() {
	# repos needs also a check in salt/freifunk/base/salt-minion/init.sls
	case "$1" in
		debian9 )
			wget -O - https://repo.saltstack.com/apt/debian/9/amd64/2019.2/SALTSTACK-GPG-KEY.pub | apt-key add -
			echo 'deb http://repo.saltstack.com/apt/debian/9/amd64/2019.2 stretch main' | tee /etc/apt/sources.list.d/saltstack.list
			;;
		ubuntu16 )
			wget -O - https://repo.saltstack.com/apt/ubuntu/16.04/amd64/2019.2/SALTSTACK-GPG-KEY.pub | apt-key add -
			echo 'deb http://repo.saltstack.com/apt/ubuntu/16.04/amd64/2019.2 xenial main' | tee /etc/apt/sources.list.d/saltstack.list
			;;
	esac
}

install_uci() {
	DL_URL='https://download.ratzeburg.freifunk.net/server/packages'

	# # the pkg version must also be changed in uci/init.sls
	libubox='libubox_20200227_amd64.deb'
	libuci='libuci_20200427_amd64.deb'
	uci='uci_20200427_amd64.deb'

	pkgs=("$libubox" "$libuci" "$uci")

	for PKG in "${pkgs[@]}"; do
		PKG_NAME="$(echo "$PKG" | cut -d'_' -f 1)"
		PKG_VERSION="$(echo "$PKG" | cut -d'_' -f 2 | grep -o '[0-9]*')"
		# check pkg is not installed or has another version
		if [ "$(dpkg-query -W -f='${Status}' "$PKG_NAME" 2>/dev/null | grep -c "ok installed")" -eq 0 ] || \
			[ "$(dpkg-query -W -f='${Version}' "$PKG_NAME")" != "$PKG_VERSION" ]; then
				TEMP_DEB="$(mktemp)" &&
				wget -O "$TEMP_DEB" "$DL_URL/$1/$PKG" &&
				dpkg -i "$TEMP_DEB"
				rm -f "$TEMP_DEB"
		fi
	done
	ldconfig
}


print_usage() {
	printf '\nUsage:\n'
	printf '  # print this help:\n'
	printf '    ./init_server.sh -h\n\n'
	printf '  # install latest stable Release:\n'
	printf '    ./init_server.sh\n\n'
	printf '  DEVELOPMENT:\n'
	printf '  # install master (devel) branch\n'
	printf '    ./init_server.sh -b\n'
	printf '    ./init_server.sh -b <rev/branch/tag>\n\n'
	printf '  # disable git update to use local changes\n'
	printf '    ./init_server.sh -d\n'
	exit 0
}

print_not_supported_os() {
	printf 'OS is not supported! (for more Informations read the Repository README.md)\n'
	printf 'Supported OS List:\n'
	printf ' - Debian (9/10)\n'
	printf ' - Ubuntu Server LTS (16.04/18.04)\n'
	exit 1
}

print_init_notice() {
	printf '%s#\n# Notice:%s\n' "$(tput bold)" "$(tput sgr0)"
	printf ' * Please check your config options in /etc/config/ffrz\n'
	printf ' * /etc/fastd/peers2/\n'
	printf '   # add your first Fastd2 Connection:\n'
	printf '   /etc/init.d/S53backbone-fastd2 add_connect <host> 5002\n'
	printf '   or: /etc/init.d/S53backbone-fastd2 add_connect <host> <port> <key>\n'
	printf '   # and restart Fastd2:\n'
	printf '   /etc/init.d/S53backbone-fastd2 restart\n'
	printf '\nOptional:\n'
	printf ' * /etc/openvpn\n'
	printf '   # To Create a openvpn configuration use:\n'
	printf '   /etc/openvpn/gen-config vpn0 <original-provider-config-file>\n'
	printf ' * /etc/wireguard/\n'
	printf '   # To Create a wireguard configuration use:\n'
	printf '   /etc/wireguard/gen-config vpn1 <original-provider-config-file>\n'
	printf '\n%sPLEASE READ THE NOTICE AND\nREBOOT THE SYSTEM WHEN EVERYTHING IS DONE!%s\n' "$(tput bold)" "$(tput sgr0)"
}


hostname="$(cat /etc/hostname)"
def_if="$(awk '$2 == 00000000 { print $1 }' /proc/net/route)"
def_addr="$(ip addr show dev "$def_if" | awk '/inet/ {printf "%s\n",$2}' | head -1)"
def_ip="${def_addr//\/*/}"

os_id="$(grep -oP '(?<=^ID=).+' /etc/os-release | tr -d '"')"
version_id="$(grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"')"


#
printf '### FFRZ-Server - Initial Setup ###\n'

while getopts ":hbd" opt "${@}"; do
	case $opt in
	  b)
		OPT_BRANCH="$OPTARG"
		[ -z "$OPT_BRANCH" ] && OPT_BRANCH='master'
		;;

	  d)
		OPT_UPDATE="0"
		;;

	  \?)
		printf 'Invalid option: -%s\n' "$OPTARG"
		print_usage
		;;

	  h | *)
		print_usage
		;;
	esac
done

#
# -- Check & Setup System --

printf '\n### Check System ..\n'
if [ "$(id -u)" -ne 0 ]; then printf 'Please run as root!\n'; exit 1 ; fi

if [ ! -f "$INIT_DATE_FILE" ]; then
	printf '\nAre you sure you want to install the FFDD-Server on %s%s%s?\n' "$(tput bold)" "$hostname" "$(tput sgr0)"
	printf 'OS: %s %s | IP: %s\n' "$os_id" "$version_id" "$def_ip"
	select yn in "Yes" "No"; do
	case $yn in
		Yes) break ;;
		No)  exit 1 ; break ;;
	esac ; done
fi

printf '\n# Check github is reachable ..\n'
if ! ping -c1 -W5 github.com >/dev/null ; then
	printf 'network not reachable or name resolution not working!\n'; exit 1
else
	printf '\nOK.\n'
fi

printf '\n# Check tun device is available ..\n'
if [ ! -e /dev/net/tun ]; then
	printf '\tThe TUN device is not available!\nYou need a enabled TUN device (/dev/net/tun) before running this script!\n'
	exit 1
else
	printf '\nOK.\n'
fi

printf '\n# Check users are present ..\n'
for users in freifunk syslog
do
	if ! /usr/bin/id "$users" >/dev/null 2>&1 ; then
		adduser --shell /bin/bash --disabled-login --disabled-password --system --group --no-create-home "$users"
	fi
done
printf '\nOK.\n'


printf '\n# Check System Distribution ..\n'
[ -z "$(command -v wget)" ] && "$PKGMNGR" -y install wget

if [ "$os_id" = 'debian' ]; then
	case "$version_id" in
		9*)     PKGMNGR='apt-get' ; check_salt_repo debian9
				install_uci debian9
		;;
		10*)    PKGMNGR='apt-get'
				install_uci debian10
		;;
		*)      print_not_supported_os ;;
	esac
elif [ "$os_id" = 'ubuntu' ]; then
	case "$version_id" in
		16.04*) PKGMNGR='apt-get' ; check_salt_repo ubuntu16
				install_uci ubuntu16
		;;
		18.04*) PKGMNGR='apt-get'
				install_uci ubuntu18
		;;
		*)      print_not_supported_os ;;
	esac

	printf '\nOK.\n'
else
	print_not_supported_os
fi


printf '\n### Update System ..\n'
"$PKGMNGR" -y update
printf '\n'
"$PKGMNGR" -y dist-upgrade

printf '\n### Install Basic Software ..\n'
"$PKGMNGR" -y install git salt-minion

# run salt-minion only as masterless. disable the service:
systemctl disable salt-minion ; systemctl stop salt-minion &


printf '\n### Install/Update ffdd-server Git-Repository ..\n'

if [ -f /usr/local/bin/nvram ] && [ -f /etc/nvram.conf ] && ! [ -L /etc/nvram.conf ]; then
	CUSTOM_REPO_URL="$(nvram get freifunk_repo)"
	[ -n "$CUSTOM_REPO_URL" ] && [ "$CUSTOM_REPO_URL" != "$REPO_URL" ] && REPO_URL="$CUSTOM_REPO_URL"

	CUSTOM_REV="$(nvram get branch)"
	[ -n "$CUSTOM_REV" ] && [ "$CUSTOM_REV" != "$REV" ] && REV="$CUSTOM_REV"

elif [ -f /usr/local/sbin/uci ] && [ -f /etc/config/ffdd ]; then
	CUSTOM_REPO_URL="$(uci -qX get ffdd.sys.freifunk_repo)"
	[ -n "$CUSTOM_REPO_URL" ] && [ "$CUSTOM_REPO_URL" != "$REPO_URL" ] && REPO_URL="$CUSTOM_REPO_URL"

	CUSTOM_REV="$(uci -qX get ffdd.sys.branch)"
	[ -n "$CUSTOM_REV" ] && [ "$CUSTOM_REV" != "$REV" ] && REV="$CUSTOM_REV"
fi

if [ -d "$INSTALL_DIR" ]; then
	cd "$INSTALL_DIR" || exit 1
	[ "$OPT_UPDATE" != '0' ] && git stash
	git fetch
else
	git clone "$REPO_URL" "$INSTALL_DIR"
	cd "$INSTALL_DIR" || exit 1
fi
if [ "$OPT_UPDATE" != '0' ]; then
	# check rev/branch/tag for initial
	if [ -n "$OPT_BRANCH" ]; then
		git checkout "$OPT_BRANCH"
		git pull -f origin "$OPT_BRANCH"
	else
		# T_RELEASE_latest OR $CUSTOM_REV
		git checkout "$REV"
		git pull -f origin "$REV"
	fi
fi


printf '\n### Backup old User configs ..\n'

cp -vf /root/.bashrc /root/.bashrc_bak >/dev/null 2>&1
test -f /root/.bash_aliases && cp -vf /root/.bash_aliases /root/.bash_aliases_bak >/dev/null 2>&1
mv -vf /etc/inputrc /etc/inputrc_bak >/dev/null 2>&1


# ensure uci and /etc/config/ffdd are present
printf '\n### Check uci Setup ..\n'
# uci config
if [ ! -f /etc/config/ffdd ]; then
	printf '\n# Create New /etc/config/ffdd ..\n'
	[ ! -d /etc/config ] && mkdir /etc/config
	cp -fv "$INSTALL_DIR"/salt/freifunk/base/uci/etc/config/ffdd /etc/config/ffdd
fi

# nvram migration
if [ -f /etc/nvram.conf ] && ! [ -L /etc/nvram.conf ]; then
	printf '\n# migrate old nvram to uci ..\n'
	"$INSTALL_DIR"/salt/freifunk/base/uci/usr/local/bin/nvram-migration.sh

	# remove old nvram
	mv /etc/nvram.conf /etc/nvram.backup
	rm -f /etc/nvram.conf* /etc/nvram_sample.conf /usr/local/bin/nvram
fi

# check basic uci options
# check install_dir
[ "$(uci -qX get ffrz.sys.install_dir)" != "$INSTALL_DIR" ] && uci set ffrz.sys.install_dir="$INSTALL_DIR"

# check repo_url
[ -z "$(uci -qX get ffrz.sys.freifunk_repo)" ] && uci set ffrz.sys.freifunk_repo="$REPO_URL"

# check branch
if [ -n "$OPT_BRANCH" ]; then
	[ "$(uci -qX get ffrz.sys.branch)" != "$OPT_BRANCH" ] && uci set ffrz.sys.branch="$OPT_BRANCH"
else
	# T_RELEASE_latest OR $CUSTOM_REV
	[ "$(uci -qX get ffrz.sys.branch)" != "$REV" ] && uci set ffrz.sys.branch="$REV"
fi

# check autoupdate
[ "$(uci -qX get ffrz.sys.autoupdate)" == '' ] && uci set ffrz.sys.autoupdate='1'
if [ "$OPT_UPDATE" = '0' ]; then
	# disable temporary autoupdate
	tmp_au="$(uci -qX get ffrz.sys.autoupdate)"
	uci set ffrz.sys.autoupdate='0'
fi

# check default Interface
[ "$(uci -qX get ffrz.sys.ifname)" != "$def_if" ] && uci set ffrz.sys.ifname="$def_if"

# ssh_pwauth
[ "$(uci -qX get ffrz.sys.ssh_pwauth)" == '' ] && uci set ffrz.sys.ssh_pwauth='1'
#
uci commit
printf '\nOK.\n'


#
# create clean masterless salt enviroment
printf '\n### Check Salt Enviroment ..\n'

rm -f /etc/salt/minion.d/*.conf

printf '\n# add salt freifunk-masterless.conf\n\n'
tee /etc/salt/minion.d/freifunk-masterless.conf <<EOF
### This file managed by Salt, do not edit by hand! ###
#
# ffdd-server - salt-minion masterless configuration file
#
master_type: disable
file_client: local
file_roots:
  base:
    - $INSTALL_DIR/salt/freifunk/base
EOF
printf '\nOK.\n'

#
# -- Initial System --

salt_call() { salt-call state.highstate --local -l error ; }

_scriptfail='0'
_init_run='0'
if [ -f "$INIT_DATE_FILE" ]; then
	printf '\n### run salt ..\n'
else
	printf '\n### Start Initial System .. please wait! Coffee Time ~ 10min ..\n'
	printf '# Please do not delete this file!\n#\nFFDD-Server - INIT DATE: %s\n' "$(date -u)" > "$INIT_DATE_FILE"
	chmod 600 "$INIT_DATE_FILE"
	_init_run='1'
fi

if salt_call ; then
	printf '\nOK.\n'
else
	printf '\ntry to fix some mistakes ..\n'
	if salt_call ; then
		printf '\nOK.\n'
	else
		printf '\nFAIL!\nSorry, you need to check some errors. Please check your salt-output and logs.\n'
		_scriptfail='1'
	fi
fi

#
# -- Cleanup System & Print Notice --

if [ "$OPT_UPDATE" = '0' ]; then
	# reset temporary disabled autoupdate
	uci set ffdd.sys.autoupdate="$tmp_au"
	uci commit
fi

printf '\n### Cleanup System ..\n\n'
"$PKGMNGR" -y autoremove

printf '\n### .. All done! Exit script.\n'
[ "$_init_run" -eq 1 ] && print_init_notice

#
# -- Exit --
if [ "$_scriptfail" -eq 0 ]; then
	exit 0
else
	exit 1
fi
