#
# Makefile for build_multilib_wine - a script to build multilib Wine
#
# Copyright (C) 2016-2019 Robert Walker
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#

INSTALL = install
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644
SOURCES = Makefile src man

version=$(shell sed -n '/BUILD_MULTILIB_WINE_VERSION=/{s/"$$//;s/^.*"//;p}' < src/build_multilib_wine)

PREFIX = /usr

all:
	@ echo "make all not supported. Use: cleanup, dist, install"

# Remove trailing whitespaces
cleanup:
	sed --in-place 's/[ \t]\+\\$//' $$(find $(SOURCES) -type f)

dist:
	tar --exclude=python3 --exclude=.git \
		--exclude-backups --xz \
		-cvf build_multilib_wine-$(version).tar.xz $(SOURCES)

install:
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/bin
	$(INSTALL_PROGRAM) src/build_multilib_wine $(DESTDIR)$(PREFIX)/bin/build_multilib_wine
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/man/man1
	$(INSTALL_DATA) man/build_multilib_wine.1 $(DESTDIR)$(PREFIX)/share/man/man1/build_multilib_wine.1
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/man/man5
	$(INSTALL_DATA) man/build_multilib_wine.conf.5 $(DESTDIR)$(PREFIX)/share/man/man5/build_multilib_wine.conf.5
	$(INSTALL) -d $(DESTDIR)$(PREFIX)/share/bash-completion/completions
	$(INSTALL_DATA) src/build_multilib_wine.bash-completion $(DESTDIR)$(PREFIX)/share/bash-completion/completions/build_multilib_wine
