#!/bin/sh
### Rozhuk Ivan 2009.05-2026
### Make chroot env script.
###


# Exit on error.
set -e

# Init constants.
# To avoid having each word of the reason treated separately.
IFS=$'\n'

CHROOT_DEVFS_RULES="
hide
path fd unhide
path fd/* unhide
path log unhide
path null unhide
path random unhide
path stderr unhide
path stdin unhide
path stdout unhide
path urandom unhide
path zero unhide
"

CHROOT_BASE_DIRS_LIST="
/bin
/dev
/etc
/lib
/libexec
/proc
/sbin
/usr/bin
/usr/lib
/usr/libexec
/usr/local/bin
/usr/local/etc
/usr/local/lib
/usr/sbin
/tmp
/var/db_chroot/ports
/var/run
"

CHROOT_BASE_CP_LIST="
/etc/host.conf
/etc/libmap.conf
/etc/libmap32.conf
/etc/localtime
/etc/login.conf
/etc/networks
/etc/nsswitch.conf
/etc/protocols
/etc/resolv.conf
/etc/services
/etc/ssl
/etc/wall_cmos_clock
/libexec/ld-elf.so.*
/libexec/ld-elf32.so.*
/usr/libexec/ld-elf.so.*
/usr/local/etc/libmap.d
/usr/share/nls
/usr/share/zoneinfo
/var/run/ld-elf.so.hints
"

CHROOT_BASE_EXEC_LIST="
/usr/bin/env
"

CHROOT_BASE_PORTS_FILES_EXCLUDE_LIST="
/usr/local/etc/bash_completion.d/
/usr/local/etc/dbus-1/
/usr/local/etc/devd/
/usr/local/etc/rc.d/
/usr/local/include/
/usr/local/lib/cmake/
/usr/local/lib/python*/test/
/usr/local/share/aclocal/
/usr/local/share/bash-completion/
/usr/local/share/common-lisp/
/usr/local/share/doc/
/usr/local/share/emacs/
/usr/local/share/examples/
/usr/local/share/gdb/
/usr/local/share/glib-2.0/
/usr/local/share/info/
/usr/local/share/licenses/
/usr/local/share/man/
/usr/local/share/pkg/
/usr/local/share/readline/
/usr/local/libdata/pkgconfig/
"


# Defaults.
CHROOT_CFG_DIR='/usr/local/etc/chroot'
CHROOT_MNT_ROOT_ARGS='-o nosuid'
CHROOT_MNT_TMP_SIZE='1m'
CHROOT_MNT_TMP_ARGS='-o noexec -o nosuid -o inodes=1k'
CHROOT_INIT_HOOK='chroot_init_hook_default'
CHROOT_DEINIT_HOOK=''


chroot_cp() { # filename/dir
	local __FN

	for __FN in "${@}"; do
		[ ! -r "${__FN}" ] && continue
		[ -r "${CHROOT_DIR}/${__FN}" ] && continue

		mkdir -p -m 0555 ${CHROOT_DIR}/`dirname "${__FN}"`
		cp -aRL "${__FN}" "${CHROOT_DIR}/${__FN}"
	done

	return 0
}

chroot_cp_bin_withdep() { # filename
	local __FN
	local __DEPS

	for __FN in "${@}"; do
		[ ! -r "${__FN}" ] && continue

		__DEPS=`ldd -a "${__FN}" 2>/dev/null | grep '=>' | sed 's|.*=> ||g' | sed 's| (.*)||g' | sort -u`
		# Fallback, mostly for GO apps.
		if [ -z "${__DEPS}" ]; then
			__DEPS=`readelf --elf-output-style=GNU --needed-libs "${__FN}" 2>/dev/null | grep '  ' | sed -e 's|  ||g' | xargs -L 1 -J % locate % 2>/dev/null | grep -v '/mnt/' | grep -v '/tmp/' | grep -v '/usr/obj/' | grep -v '/usr/src/' | grep -v '/var/' | sort -u`
		fi
		for __DEP in ${__DEPS}; do
			[ -r "${CHROOT_DIR}/${__DEP}" ] && continue
			chroot_cp_bin_withdep "${__DEP}"
		done

		[ -r "${CHROOT_DIR}/${__FN}" ] && continue
		chroot_cp "${__FN}"
	done

	return 0
}

chroot_mount_single() { # ro/rw, filename/dir
	local __DIR

	if [ -d "${2}" ]; then
		mkdir -p -m 0555 "${CHROOT_DIR}/${2}"
		chown root:wheel "${CHROOT_DIR}/${2}"
		mount_nullfs -o "${1}" -o nocache -o noatime -o noexec -o nosuid "${2}" "${CHROOT_DIR}/${2}"
		return 0
	fi

	if [ -f "${2}" ]; then
		__DIR=`dirname ${2}`
		mkdir -p -m 0555 "${CHROOT_DIR}/${__DIR}"
		chown root:wheel "${CHROOT_DIR}/${__DIR}"
		touch "${2}" "${CHROOT_DIR}/${2}"
		chown "${CHROOT_USER}:${CHROOT_GROUP}" "${CHROOT_DIR}/${2}"
		mount_nullfs -o "${1}" -o nocache -o noatime -o noexec -o nosuid "${2}" "${CHROOT_DIR}/${2}"
		return 0
	fi

	echo "Can not mount - not file or dir: ${2}"
	return 1
}

chroot_port_mark_as_done() { # ports names
	local __PORT_NAME
	local __PKG_INFO_RAW
	local __PKG_NAME
	local __PKG_VER
	local __PKG_NAME_VER

	for __PORT_NAME in "${@}"; do
		# Make sure that port name is in proper format.
		__PKG_INFO_RAW=`pkg info --full --quiet "${__PORT_NAME}"`
		__PKG_NAME=`echo "${__PKG_INFO_RAW}" | grep 'Name           : ' | sed -e 's|Name           : ||g' | tr -d '\n'`
		__PKG_VER=`echo "${__PKG_INFO_RAW}" | grep 'Version        : ' | sed -e 's|Version        : ||g' | tr -d '\n'`
		__PKG_NAME_VER="${__PKG_NAME}-${__PKG_VER}"
		touch "${CHROOT_DIR}/var/db_chroot/ports/${__PKG_NAME_VER}"
		touch "${CHROOT_DIR}/var/db_chroot/ports/${__PKG_NAME_VER}.deps"
	done

	return 0
}

chroot_port_clone() { # ports names
	local __PORT_NAME
	local __PKG_INFO_RAW
	local __PKG_NAME
	local __PKG_VER
	local __PKG_NAME_VER
	local __DIR
	local __TAR_EXCLUDE

	for __DIR in ${CHROOT_BASE_PORTS_FILES_EXCLUDE_LIST} ${CHROOT_APP_CP_LIST} ${CHROOT_PORTS_FILES_EXCLUDE_LIST}; do
		__TAR_EXCLUDE="${__TAR_EXCLUDE} --exclude ${__DIR}"
	done

	local IFS=' '
	for __PORT_NAME in "${@}"; do
		# Make sure that port name is in proper format.
		__PKG_INFO_RAW=`pkg info --full --quiet "${__PORT_NAME}"`
		__PKG_NAME=`echo "${__PKG_INFO_RAW}" | grep 'Name           : ' | sed -e 's|Name           : ||g' | tr -d '\n'`
		__PKG_VER=`echo "${__PKG_INFO_RAW}" | grep 'Version        : ' | sed -e 's|Version        : ||g' | tr -d '\n'`
		__PKG_NAME_VER="${__PKG_NAME}-${__PKG_VER}"
		# Is port already cloned?
		[ -f "${CHROOT_DIR}/var/db_chroot/ports/${__PKG_NAME_VER}" ] && continue
		touch "${CHROOT_DIR}/var/db_chroot/ports/${__PKG_NAME_VER}"
		# Slower than cp in some cases, but handle hardliks and dirs.
		# Use --keep-old-files --modification-time ... 2>/dev/null | true
		# to silece and supress errors that may happen while extract
		# files to RO mount ponts.
		# --skip-old-files may fix this but it does not exist in bsdtar.
		pkg info --list-files --quiet "${__PORT_NAME}" | tar --create --directory '/tmp/' --norecurse ${__TAR_EXCLUDE} --files-from - --file - 2>/dev/null | tar --extract --file - --keep-old-files --modification-time --directory "${CHROOT_DIR}/" 2>/dev/null | true
	done

	return 0
}

# Does not clone port, only its deps.
chroot_port_deps_clone() { # ports names
	local __PORT_NAME
	local __PKG_NAME_VER

	for __PORT_NAME in "${@}"; do
		for __PKG_NAME_VER in `pkg info --dependencies --quiet "${__PORT_NAME}" | grep -v '	'`; do
			# Is port already cloned?
			[ -f "${CHROOT_DIR}/var/db_chroot/ports/${__PKG_NAME_VER}.deps" ] && continue
			touch "${CHROOT_DIR}/var/db_chroot/ports/${__PKG_NAME_VER}.deps"
			chroot_port_clone "${__PKG_NAME_VER}"
			chroot_port_deps_clone "${__PKG_NAME_VER}"
		done
	done

	return 0
}

chroot_deps_fixup() {
	# Bins.
	chroot_cp_bin_withdep `find "${CHROOT_DIR}/" -type f -executable | sort -u | sed "s|${CHROOT_DIR}||g"`	
	# Libs.
	chroot_cp_bin_withdep `find "${CHROOT_DIR}/" -type f -name '*.so*' | sort -u | sed "s|${CHROOT_DIR}||g"`
}

chroot_init() {
	local __DIR
	local __RULE

	if [ -d "${CHROOT_DIR}" ]; then
		echo "Dir already exist ${CHROOT_DIR}!"
		exit 0
	fi

	# Create chroot dir.
	mkdir -p -m 0555 "${CHROOT_DIR}"
	echo -o rw -o nomtime -o size="${CHROOT_MNT_ROOT_SIZE}" ${CHROOT_MNT_ROOT_ARGS} -t tmpfs tmpfs "${CHROOT_DIR}" | xargs mount
	# Init /tmp, /var/tmp.
	mkdir -p -m 0777 "${CHROOT_DIR}/tmp" "${CHROOT_DIR}/var"
	echo -o rw -o nomtime -o pgread -o size="${CHROOT_MNT_TMP_SIZE}" -o mode=0777 ${CHROOT_MNT_TMP_ARGS} -t tmpfs tmpfs "${CHROOT_DIR}/tmp" | xargs mount
	chmod 1777 "${CHROOT_DIR}/tmp"
	ln -sf '/tmp' "${CHROOT_DIR}/var/tmp"
	# Create dirs.
	for __DIR in ${CHROOT_BASE_DIRS_LIST}; do
		mkdir -p -m 0555 "${CHROOT_DIR}/${__DIR}"
	done
	chown -R root:wheel "${CHROOT_DIR}"

	# Copy files and dirs.
	chroot_cp ${CHROOT_BASE_CP_LIST}

	# Copy bins and its deps.
	chroot_cp_bin_withdep ${CHROOT_BASE_EXEC_LIST}


	# etc init.
	# malloc.conf is a symlink, optional.
	cp -a '/etc/malloc.conf' "${CHROOT_DIR}/etc/" | true
	# /etc/hosts
	echo '::1 localhost' >		"${CHROOT_DIR}/etc/hosts"
	echo '127.0.0.1 localhost' >>	"${CHROOT_DIR}/etc/hosts"
	# Passwords.
	grep "^${CHROOT_USER}" '/etc/master.passwd' > "${CHROOT_DIR}/etc/master.passwd"
	grep "^${CHROOT_USER}" '/etc/passwd' > "${CHROOT_DIR}/etc/passwd"
	grep "^${CHROOT_GROUP}" '/etc/group' > "${CHROOT_DIR}/etc/group"
	cap_mkdb -f "${CHROOT_DIR}/etc/login.conf" "${CHROOT_DIR}/etc/login.conf"
	pwd_mkdb -d "${CHROOT_DIR}/etc" "${CHROOT_DIR}/etc/master.passwd"


	# Init devfs.
	mount -t devfs devfs "${CHROOT_DIR}/dev"
	# Apply rules.
	for __RULE in ${CHROOT_DEVFS_RULES} ${CHROOT_APP_DEVFS_RULES}; do
		echo "${__RULE}" | xargs devfs -m "${CHROOT_DIR}/dev" rule apply
	done

	# Mount RO files/dirs.
	for __DIR in ${CHROOT_MNT_MAP_RO}; do
		chroot_mount_single 'ro' "${__DIR}"
	done
	# Mount RW files/dirs.
	for __DIR in ${CHROOT_MNT_MAP_RW}; do
		chroot_mount_single 'rw' "${__DIR}"
	done

	# App specific.
	chroot_cp ${CHROOT_APP_CP_LIST}
	chroot_cp_bin_withdep ${CHROOT_APP_EXEC_LIST}

	# Ports.
	chroot_port_clone ${CHROOT_PORTS_NAMES}

	# Ports deps.
	chroot_port_deps_clone ${CHROOT_PORTS_DEPS_NAMES}

	# Ports with deps.
	chroot_port_mark_as_done ${CHROOT_PORTS_STOP_LIST}
	chroot_port_clone ${CHROOT_PORTS_WITH_DEPS_NAMES}
	chroot_port_deps_clone ${CHROOT_PORTS_WITH_DEPS_NAMES}

	# Fixup deps
	chroot_deps_fixup
}

chroot_deinit() {

	if [ ! -d "${CHROOT_DIR}" ]; then
		return 0
	fi

	mount | grep " on ${CHROOT_DIR}/" | cut -d ' ' -f 3-255 | cut -d '(' -f 1 | sed 's/.$//' | xargs umount -f
	#chflags -R noschg "${CHROOT_DIR}"
	umount -f "${CHROOT_DIR}"
	rm -rf "${CHROOT_DIR}"
}

chroot_init_hook_default() {
	# Lockup changes.
	mount -u -o ro "${CHROOT_DIR}"
}

chroot_main() {
	# Auto defaults.
	if [ -z "${CHROOT_GROUP}" ]; then
		CHROOT_GROUP=`/usr/bin/id -gn ${CHROOT_USER}`
	fi

	# Handle command.
	case ${1} in
	start)
		# Base chroot init.
		chroot_init
		# User defined code.
		if [ -n "${CHROOT_INIT_HOOK}" ]; then
			eval "${CHROOT_INIT_HOOK}"
		fi
		;;
	stop)
		# User defined code.
		if [ ! -d "${CHROOT_DIR}" ]; then
			echo "Dir does not exist ${CHROOT_DIR}!"
			return 0
		fi
		if [ -n "${CHROOT_DEINIT_HOOK}" ]; then
			eval "${CHROOT_DEINIT_HOOK}"
		fi
		# Base chroot deinit.
		chroot_deinit
		;;
	restart)
		if [ -d "${CHROOT_DIR}" ]; then
			chroot_main stop
		fi
		chroot_main start
		;;
	*)
		echo 'Invalid command!'
		exit 1
		;;
	esac
}


if [ -f "${1}" ]; then
. "${1}"
else
	if [ -f "${CHROOT_CFG_DIR}/${1}" ]; then
. "${CHROOT_CFG_DIR}/${1}"
	else
		echo "Chroot env config \'${1}\' not found!"
		exit 1
	fi
fi

chroot_main ${2}


exit 0
