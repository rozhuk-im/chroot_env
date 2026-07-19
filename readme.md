# chroot_env

Rozhuk Ivan <rozhuk.im@gmail.com> 2026

Helps create chroot environments for applications on FreeBSD automatically.

This script allows you to create a chroot environment for an application that contains no SETUID files; the entire environment is mounted read-only (RO), while locations requiring write access are mounted with `noexec` and `nosuid` flags. This setup effectively prevents the exploitation of many vulnerabilities found in both standard and web applications. <br/>

The overhead is minimal: zero impact on CPU usage and a negligible amount of RAM usage. <br/>

An additional benefit is the ability to perform atomic updates for running applications: the process of building ports or installing packages does not interfere with the application currently running inside the chroot. <br/>

This mechanism can also be used to create an application container that includes all the dependencies required for execution. <br/>
<br/>

It was originally developed as a security enhancement for public web servers running PHP applications. <br/>


## Licence
BSD licence.


## Donate
Support the author
* **GitHub Sponsors:** [!["GitHub Sponsors"](https://camo.githubusercontent.com/220b7d46014daa72a2ab6b0fcf4b8bf5c4be7289ad4b02f355d5aa8407eb952c/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f2d53706f6e736f722d6661666266633f6c6f676f3d47697448756225323053706f6e736f7273)](https://github.com/sponsors/rozhuk-im) <br/>
* **Buy Me A Coffee:** [!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://www.buymeacoffee.com/rojuc) <br/>
* **PayPal:** [![PayPal](https://srv-cdn.himpfen.io/badges/paypal/paypal-flat.svg)](https://paypal.me/rojuc) <br/>
* **Bitcoin (BTC):** `1AxYyMWek5vhoWWRTWKQpWUqKxyfLarCuz` <br/>


## Usage
``` shell
chroot_env.sh CONFIG_FILE_NAME start|stop|restart
chroot_env.sh PATH_TO_CONFIG_FILE_NAME start|stop|restart
```
If the path to the chroot configuration file is not specified, then it is used by default: `/usr/local/etc/chroot`. <br/>


### Chroot options


#### Mandatory

* **CHROOT_DIR** - is the directory in which to create chroot. <br/>
* **CHROOT_USER** - the user under which the application will be launched. <br/>
* **CHROOT_GROUP** - is the group to which the running process will belong. By default, it is defined as the group the user belongs to: `/usr/bin/id -gn ${CHROOT_USER}`. <br/>
* **CHROOT_MNT_ROOT_SIZE** - size of the tmpfs for chroot. <br/>

#### Auxiliary
* **CHROOT_MNT_ROOT_ARGS** - tmpfs arguments for mounting the chroot root, default: `-o nosuid`. <br/>
* **CHROOT_MNT_TMP_SIZE** - size of tmpfs mounted in /tmp chroot, default: `1m`. <br/>
* **CHROOT_MNT_TMP_ARGS** - tmpfs arguments for mounting the chroot /tmp, default: `-o noexec -o nosuid -o inodes=1k`. <br/>
* **CHROOT_MNT_MAP_RO**, **CHROOT_MNT_MAP_RW** - paths to files/directories that will be mounted in chroot using nullfs with options: `-o nocache -o noatime -o noexec -o nosuid`. <br/>
<br/>

* **CHROOT_APP_DEVFS_RULES** - devfs rules applied within chroot. Used when working with devices is required. <br/>
* **CHROOT_APP_CP_LIST** - a list of files that will be copied into the chroot. Used for non-executable files, such as configuration files. <br/>
* **CHROOT_APP_EXEC_LIST** - a list of executable files to be copied into the chroot. This is used to copy executable files and all their dependencies. It's ideal for listing system-related files to be copied into the chroot, as well as simple programs installed from ports. <br/>
<br/>

* **CHROOT_APP_PF_RULES** - PF rules (pf.conf syntax) loaded into a per-app anchor. Opt-in: leave unset and no PF integration happens at all, nothing changes. See "Network" below. <br/>
* **CHROOT_APP_PF_ANCHOR** - name of the PF anchor `CHROOT_APP_PF_RULES` is loaded into. Default: `chroot_env/${CHROOT_USER}`. <br/>
<br/>

* **CHROOT_PORTS_NAMES** - a list of ports to be cloned into the chroot, excluding dependencies. <br/>
* **CHROOT_PORTS_DEPS_NAMES** - is a list of ports for which their dependencies must also be cloned. <br/>
* **CHROOT_PORTS_WITH_DEPS_NAMES** — a list of ports to be cloned into the chroot, along with their dependencies. Ports listed in `CHROOT_PORTS_STOP_LIST` are excluded from the dependencies. This is ideal for complex ports that require text files and other binary files in addition to executables. <br/>
* **CHROOT_PORTS_STOP_LIST** - a list of ports that will not be automatically cloned into the chroot. In some cases, there's no need to clone the entire port specified as a dependency, as the entire port may only require a few libraries. For example, net-im/prosody depends on dns/unbound only because it requires libunbound.so. In this case, there's no need to clone the entire unboud port with all its dependencies. The script will automatically detect that libunbound.so is required and copy it into the chroot along with all its dependencies. Does not work for ports listed in `CHROOT_PORTS_NAMES` and `CHROOT_PORTS_DEPS_NAMES`. <br/>
* **CHROOT_PORTS_FILES_EXCLUDE_LIST** - list of files that will not be copied to chroot when cloning ports. Use: `pkg info --list-files PORTNAME` to see a list of files related to a port. <br/>
<br/>

* **CHROOT_INIT_HOOK** - A shell script function called at the final stage of creating a chroot environment. It is used when additional actions are required. See examples: apcupsd, php-dokuwiki, php-nextcloud, sh. By default, chroot_init_hook_default() is called, which remounts the chroot to RO: `mount -u -o ro "${CHROOT_DIR}"`. <br/>
* **CHROOT_DEINIT_HOOK** - A shell script function called before destroying the chroot environment. Used when additional actions are required. See examples: php-nextcloud. <br/>


### Network (optional)
By itself chroot(2) does not isolate the network stack: a process inside the chroot has exactly the same access to sockets and interfaces as `CHROOT_USER` has on the host. `CHROOT_APP_PF_RULES` adds an opt-in network ACL on top of that, using PF's `user` match instead of a separate network stack/VNET jail - so it stays inside the "light, no jails" scope of this script. <br/>
<br/>

One-time setup in the host `pf.conf`, so per-app anchors actually get evaluated (leave this out and `CHROOT_APP_PF_RULES` still loads fine, it just never applies to any traffic): <br/>
``` shell
anchor "chroot_env/*"
```
Then, per app: <br/>
``` shell
CHROOT_APP_PF_RULES="
pass out quick proto tcp to any port {80, 443} user ${CHROOT_USER}
"
```
`start` loads this into `CHROOT_APP_PF_ANCHOR` (`pfctl -a ... -f -`) with a `block return out quick user ${CHROOT_USER}` / `block in quick user ${CHROOT_USER}` pair appended after it, so anything not explicitly passed is denied; `stop` flushes the anchor (`pfctl -a ... -F all`). Two things have to hold for every rule in `CHROOT_APP_PF_RULES`, or it silently under- or over-restricts: <br/>
* needs `quick` - app rules are evaluated before the appended block pair, so without `quick` they lose to it. <br/>
* needs `user ${CHROOT_USER}` - anchor evaluation isn't scoped by anchor name alone; a rule without it can pass traffic for other processes on the host too, not just this chroot. <br/>
<br/>

DNS resolver and TLS trust store need no extra config: `CHROOT_BASE_CP_LIST` already includes `/etc/resolv.conf`, `/etc/nsswitch.conf` and `/etc/ssl` (the CA bundle, if `security/ca_root_nss` is installed) for every chroot. Point `/etc/resolv.conf` at a locally filtering resolver - see the `unbound` example - for a second layer of control alongside the PF rules above. <br/>
<br/>

Two things this cannot do, since the script only manages the chroot environment and never execs the target application itself - that happens via `chroot(8)`/`rc.d`: <br/>
* **Routing-level restriction** (deny the LAN, force a gateway/proxy) - allocate a FIB (`net.fibs` in `loader.conf`) and prefix the actual invocation with `setfib`, e.g. `setfib 1 chroot "${CHROOT_DIR}" ...`. <br/>
* **True network isolation** (own interface, routing table invisible to the host) - that's what VNET jails are for; at that point use jails instead of this script. <br/>

See `examples/browser` for all of the above together. <br/>


### Integration with services
To automatically create and remove a chroot when starting and stopping a service, you'll need to apply a patch to the system: https://github.com/freebsd/freebsd-src/pull/2186 <br/>

Then, simply specify the chroot and pre_start + post_stop in rc.conf:
``` shell
chronyd_enable="YES"
chronyd_chroot="/var/run/chroot-chrony/"
chronyd_pre_start="chroot_env.sh chrony restart"
chronyd_post_stop="chroot_env.sh chrony stop"
```
For services that automatically create a chroot (unbound, php_fpm), you only need to specify pre_start + post_stop.
``` shell
unbound_enable="YES"
unbound_pidfile="/var/run/unbound.pid"
unbound_pre_start="chroot_env.sh unbound restart"
unbound_post_stop="chroot_env.sh unbound stop"
```
