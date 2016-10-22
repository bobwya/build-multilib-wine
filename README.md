## Ubuntu Wine/Wine-Staging Build Script (build-multilib-wine)


###  Discussion


Monolithic BASH script to build multilib Wine / Wine-Staging, from source, on Ubuntu(tm) - using dual Chroot Environments.

The Ubuntu(tm) / Debian distributions have chosen to remove most of the i386 multilib development libraries from their 64-bit repositories (post the Ubuntu 10.04 release?) Wine requires a complete multilib build/development environment to be built from Source. The vast majority of Windows binaries are still 32-bit (including all legacy applications).

It appears, from the WineHQ forums, that Ubuntu/Wine users meet a bit a brick wall if they want to apply non-official patches to Wine. Building multilib Wine from source - without the necessary 32-bit development libraries - is quite tricky!

To overcome the problem of building Wine from Source on a modern Ubuntu(tm) release requires access to a true 32-bit Ubuntu system and repostories on a 64-bit System. This is because multilib Wine is effectively built/compiled in 2 cycles on a 64-bit System: 32-bit and 64-bit respectively.

As Ubuntu(tm) has removed the necesary 32-bit development libraries, from the 64-bit repositories, it is necessary to use a more "creative build process" to workaround this. The main available and solutions that can be used are:

1. **build multilib Wine natively on a 64-bit Ubuntu(tm) system**
  * This works - but 32-bit support will not be fully functional in the Wine build - due to a number of critical development libraries that will be missing.

2. **build multilib Wine on a 64-bit Ubuntu(tm) using a 32-bit Chroot**
  * Performant, doesn't polute the host system with unnecessary development libraries, no missing 32-bit development libraries, Chroot images can be minimal in size and thereby use the least possible disk space.

3. **build multilib Wine on 64-bit Ubuntu(tm) using a 32-bit LXC (Linux Container)**
  * Performant, doesn't need to polute the host system with unnecessary development libraries (if using dual architecture containers), no missing 32-bit development libraries. LXC image can be relatively small, but can be difficult to setup (steep learning curve).

4. **build multilib Wine on 64-bit Ubuntu(tm) using a Virtual Machine with a 32-bit Ubuntu(tm) image (VM - e.g. VirtualBox)**
  * Overhead (CPU), hard to link the 32-bit Wine build to the native 64-bit Wine build, disk usage hog, not a very practical solution!


###  Usage


Install the script in your user's PATH.
The script has a detailed help page with the all the supported options:
```
    build_multilib_wine.sh help
```

At present the script has some Environment variables that have to be overridden to change some advanced options: 
```
        WINE_CONFIG_OPTIONS="${WINE_CONFIG_OPTIONS} --without-hal --without-v4l --without-oss"
        WINE_CFLAGS="${WINE_CFLAGS} -march=native -mtune=native"
        WINE_MAKE_OPTIONS="${WINE_MAKE_OPTIONS} -j${THREADS}"
```
All patches from the Wine-Staging patchset are applied - without exception at present. An option (or configuration file) is still to be added, to the build script, to specify indvidual patch groups to disable.

User patches can applied (specified by directory or directories). Thereby allowing a custom Wine version to be built from Source.

At present the build script carefully installs **all** necessary development libraries to build Wine or Wine-Staging from Source. But these libraries are only installed in the Chroot Environments.
There is no attempt to install necessary runtime dependencies (mainly 32-bit libaries) on the Host Ubuntu(tm) System. This will be added in at a later stage (perhaps a small helper script). This isn't a package builder! So it's recommended to install one the WineHQ official packages (**winehq-devel** or **winehq-staging**) alongside your usage of this script... These packages will pull in the necessary runtime library dependencies, plus install package icons and desktop files.


###  I'm a stupid


I should point out I'm firmly in the Gentoo camp... So bear that in mind if the script makes some misassumptions about the Debian Schroot utility or Debian package management! Pull requests happily received!

