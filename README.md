## Debian/Ubuntu Wine/Wine Staging Build Script (build-multilib-wine)

###  Downloading

If you chose to download the build-multilib-wine script directly from Github (rather than cloning the Git repository)... When viewing the script file ensure you click the **RAW** button at the top of the file... Otherwise when you save the webpage, with your Web Browser, you will literally download that **html** Github webpage and not the bare **BASH script**, text file!

###  Usage


Install the script in your user's PATH. Ensure that you have setup a **root** user password set - as the script uses **su** to escalate privileges, as and when required. **Note**: by default **Ubuntu** only sets up **sudo** privileges.

The script has a detailed help page with the all the supported options:
```
    build_multilib_wine.sh help
```
An optional global configuration file is used by, the build script, to specify various global options, Wine/Wine Staging version to build, logging options, colourised output, etc. A command exists to dump a default configuration file - to the **/etc/build_multilib_wine.conf** path:
```
    build_multilib_wine.sh generate-conf
```
*It is recommended new users do this first*. As the configuration file will show what common script options will need to be specfied. This file be edited (as **root**) to suit the users requirements.

The default directory options are typically OK for most users:
```
    PREFIX="${HOME}/usr"                    # default install directory - in your user's HOME directory
    SOURCE_ROOT="${HOME}/Wine/Source"       # default directory for Wine Git source and default patches
    BUILD_ROOT="${HOME}/Wine/Build"         # default directory for Wine builds
    LOG_DIRECTORY="${HOME}/Wine/Build/Logs" # default directory for build log files
```
All of these directories are shared with both of the Schroot environments.
 
At present the script has some Environment variables that can be overridden to change some advanced options: 
```
        WINE_CONFIG_OPTIONS="-without-hal --without-v4l --without-oss"
        WINE_CFLAGS="-march=native -mtune=native"
        WINE_MAKE_OPTIONS="-j${THREADS}"
```
Typically one of more of these variables would be set (if required) in the global configuration file.

Finally once you've built your new shiney custom Wine version...
"How do I run it?" You might ask...
The default install path is:
```
    "${HOME}/usr"
```
So to run your custom Wine version use the full path, e.g.:
```
    ~/usr/bin/wine ...
    ~/usr/bin/winecfg
```

Backported, Wine build time patches, carried over my Gentoo ebuild, are selectively applied to the Wine Git tree.
Depending on the Wine Git Commit being built... Any of these patches that are already committed, as a parent commit in the Wine Git tree, are automatically excluded.
A separate **gentoo_wine_ebuild_common** repository tarball is downloaded to supply this patchset.

All patches from the Wine Staging patch-set are applied by default (except for a small number - that are patched separately from the Wine Staging patch install script). However any number of the Wine Staging (sub-)patch-sets can be selectively disabled. Again this is only possible via overriding Environment variables - typically in the global configuration file.

User patches can applied - any number of directories, containing patch files, can be specified. Thereby allowing a custom Wine version to be built from Source.

Schroot setup and the build process can be optionally logged using a separate thread (via FIFO pipe). Optionally on completion of the selected build phases, or Schroot operations - the log file can be automatically compressed (all the main Linux compressors are supported). Log files and stdout console output can be colourised according to user preference.

At present the build script carefully installs **all** necessary development libraries to build Wine or Wine Staging from Source. But these libraries are only installed in the Chroot Environments.
There is no attempt to install necessary runtime dependencies (mainly 32-bit libraries) on the Host Debian or Ubuntu(tm) System. This will be added in at a later stage (perhaps a small helper script). This isn't a package builder! So it's recommended to install one the WineHQ official packages (**winehq-devel** or **winehq-staging**) alongside your usage of this script... These packages will pull in the necessary runtime library dependencies, plus install package icons and desktop files.


###  Discussion


This Github repository houses a monolithic BASH script to build multilib Wine / Wine Staging, from source, on Debian or Ubuntu(tm). Utilising dual Chroot Environments. Ubuntu 16.04 Xenial (or newer) is a hard requirement for the Chroot Environments.

All recent Debian or Ubuntu(tm) distribution releases have packaging errors with some of the 32-bit and 64-bit multilib development libraries required for Wine. Wine requires a complete multilib build/development environment to be built from Source. The vast majority of Windows binaries are still 32-bit (including all legacy applications).

It appears, from the WineHQ forums, that Ubuntu Wine users (and pseudo distributions like "Linux Mint") meet a bit a brick wall if they want to apply non-official patches to Wine. Building multilib Wine from source - without the necessary 32-bit development libraries - is quite tricky!

To overcome the problem of building Wine from Source on a modern Debian or Ubuntu(tm) release, requires access to a true 32-bit Ubuntu system and repositories on a 64-bit System. This is because multilib Wine is effectively built/compiled in 2 cycles on a 64-bit System: 32-bit and 64-bit respectively.

Modern Debian and Ubuntu(tm) releases have issues co-installing many Wine development 32-bit and 64-bit libraries (due to Debian multilib packaging errors). It is necessary to use a more "creative build process" to workaround this. The main available and solutions that can be used are:

1. **build multilib Wine natively on a 64-bit Debian / Ubuntu(tm) system**
  * This works - but 32-bit support will not be fully functional in the Wine build - due to a number of critical development libraries that will be missing.

2. **build multilib Wine on a 64-bit Debian / Ubuntu(tm) using a 32-bit Chroot**
  * Performant, doesn't pollute the host system with unnecessary development libraries, no missing 32-bit development libraries, Chroot images can be minimal in size and thereby use the least possible disk space.

3. **build multilib Wine on 64-bit Debian / Ubuntu(tm) using a 32-bit LXC (Linux Container)**
  * Performant, doesn't need to pollute the host system with unnecessary development libraries (if using dual architecture containers), no missing 32-bit development libraries. LXC image can be relatively small, but can be difficult to setup (steep learning curve).

4. **build multilib Wine on 64-bit Debian / Ubuntu(tm) using a Virtual Machine with a 32-bit Debian / Ubuntu(tm) image (VM - e.g. VirtualBox)**
  * Overhead (CPU), hard to link the 32-bit Wine build to the native 64-bit Wine build, disk usage hog, not a very practical solution!

Also see: https://wiki.winehq.org/Building_Wine


###  Closing Notes


I should point out I'm a Gentoo user - only an occasional Ubuntu user... So bear that in mind if the script makes some misassumptions about the Debian Schroot utility or Debian package management! Pull requests happily received!

