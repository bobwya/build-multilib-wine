# build-multilib-wine ``SABERTOOTH BUILD`` - Updated Fork

``build-multilib-wine`` is a Debian/Ubuntu™ build script for compiling multilib Wine/Wine Staging.

###  Installing

Download and install the latest release version tarball:
```
    export release_tag
    cd ~/Downloads
    wget 'https://github.com/bobwya/build-multilib-wine/releases/latest' -O 'build-multilib-wine.release.json'
    release_tag="$(sed -n '\@<a href=\"/bobwya/build-multilib-wine/releases/tag/@{s@^.*<a href=\".*releases/tag/\(.*\)\">.*$@\1@g;p}' 'build-multilib-wine.release.json')"
    [[ -z "${release_tag}" ]] && release_tag="master"
    wget "https://github.com//bobwya/build-multilib-wine/archive/${release_tag}.tar.gz" -O "build-multilib-wine-${release_tag}.tar.gz" \
    && tar xvfa "build-multilib-wine-${release_tag}.tar.gz" \
    && cd "build-multilib-wine-${release_tag}" \
    && sudo make install
```

###  Usage

Ensure that you have a **root** user password set.
The script requires **su** to escalate privileges, as and when required.
**Note**: by default **Ubuntu™** only sets up **sudo** privileges.

The script has a detailed help page with the all the supported options:
```
    build_multilib_wine help
```

Also see the online man pages:
 * [**build_multilib_wine**(1)](https://github.com/bobwya/build-multilib-wine/wiki/build_multilib_wine-(1)-:-man-page)
 * [**build_multilib_wine.conf(5)**](https://github.com/bobwya/build-multilib-wine/wiki/build_multilib_wine.conf(5)-:-man-page) 

These man pages can also be viewed offline, using the commands (respectively):
```
    man build_multilib_wine # (1)
    man build_multilib_wine.conf # (5)
```

A default / stock configuration file can be created with:
```
    build_multilib_wine generate-conf
```

*It is recommended new users do this first*. As the configuration file will show what common script options will/may need to be specified.
This file can then be edited to suit the users requirements.

This configuration file will be created by default as:
```
    "${HOME}/.config/build_multilib_wine/build_multilib_wine.conf"
```

The default directory options are typically OK for most users:
```
    PREFIX="${HOME}/usr"                    # default install directory - in your user's HOME directory
    SOURCE_ROOT="${HOME}/Wine/Source"       # default directory for Wine Git source and default patches
    BUILD_ROOT="${HOME}/Wine/Build"         # default directory for Wine builds
    LOG_DIRECTORY="${HOME}/Wine/Build/Logs" # default directory for build log files
```
All of these directories are shared with both of the Schroot environments (as **HOME** is a common mount-point).

At present the script has some Environment variables that can be overridden to change some advanced options:
```
        WINE_CONFIG_OPTIONS="-without-hal --without-v4l --without-oss"
        WINE_CFLAGS="-march=native -mtune=native"
        WINE_MAKE_OPTIONS="-j${THREADS}"
```
Typically one of more of these variables would be set (if required) in the global configuration file.

###  Using your custom Wine build(s)

Ensure that you have the **winehq-devel** (or **winehq-staging**) staging packages installed - so that
you have the necessary runtime dependencies required by Wine.

Once you've managed to compile your custom version of Wine, it will (by default) be installed to:
```
    "${HOME}/usr"
```
To run your custom Wine version use the **full path** for all the executable, e.g.:
```
    ~/usr/bin/wine start /unix ~/Downloads/foobar2000_v1.4.exe
    ~/usr/bin/winecfg
```


###  Logging

Schroot setup/upgrade and all the build process can be optionally logged. This is done using a separate thread (via FIFO pipe). Optionally on completion of the selected build phases, or Schroot operations - the log file can be automatically compressed (all standard compressors are supported). Log files and stdout console output can be colourised according to user preference.

The default directory, for storing the **build-multilib-wine** log files, is:
```
    LOG_DIRECTORY="${HOME}/Wine/Build/Logs" # default directory for build log files
```

###  Technical

The dual Schroot chroot environments are created as subdirectories of the directory:
```
/srv/chroot/ ...
```
using individual (per-chroot) Schroot configuration files within the directory:
```
/etc/schroot/chroot.d/
```
So an example setup would include a 32-bit configuration file:
```
disco_wine_32bit.conf

[disco_wine_32bit]
description=Ubuntu 19.04 (32-bit)
personality=linux32
directory=/srv/chroot/disco_wine_32bit
message-verbosity=verbose
root-users=root
type=directory
users=robert
preserve-environment=true
```
and a 64-bit configuration file:
```
disco_wine_32bit.conf

[disco_wine_64bit]
description=Ubuntu 19.04 (64-bit)
directory=/srv/chroot/disco_wine_64bit
message-verbosity=verbose
root-users=root
type=directory
users=robert
preserve-environment=true
```

Logging is done with a separate logging thread... This was done so a FIFO pipe could be utilised. This proved to be simplier and more reliable, than say using TTY redirection, etc. Commands are simply grouped into blocks, with all output redirected to the input of the FIFO pipe. The actual logging thread reads the data coming out of the FIFO pipe output. This is always dumped to the standard console output stream (**stdout**) and (optionally) is written, uncompressed, to a log file. Log file compression is deferred to completion, of the current script operation, to support more advanced (non-streaming) compression techniques, like **lzma**. Generally using deferred compression will always achieve better compression ratios vs. streaming compression, when more advanced compression techniques are used.

The script was originally intended to use **sudo** to gain **root** privileges, as required. However there are a number of flaws, in the way **sudo** works, that made this very difficult. The most significant problem is that subshells, created with **sudo**, do not inherit any exported functions and variables, from the parent shell. Working around this limitation (alone) would have been (potentially) quite messy. So the final version of the script uses **su** to gain **root** privileges, as required. Unfortunately, this does require that Ubuntu user's have a **root** password set.
