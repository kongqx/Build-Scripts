#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script builds Emacs and its dependencies from sources.

# See fixup for INSTALL_LIBDIR below
INSTALL_PREFIX=/usr/local
INSTALL_LIBDIR="$INSTALL_PREFIX/lib64"

ZLIB_TAR=zlib-1.2.11.tar.gz
ZLIB_DIR=zlib-1.2.11

NCURSES_TAR=ncurses-6.0.tar.gz
NCURSES_DIR=ncurses-6.0

EMACS_TAR=emacs-24.5.tar.gz
EMACS_DIR=emacs-24.5

# Avoid shellcheck.net warning
CURR_DIR="$PWD"

# Sets the number of make jobs
MAKE_JOBS=4

###############################################################################

# Autotools on Solaris has an implied requirement for GNU gear. Things fall apart without it.
# Also see https://blogs.oracle.com/partnertech/entry/preparing_for_the_upcoming_removal.
if [[ -d "/usr/gnu/bin" ]]; then
    if [[ ! ("$PATH" == *"/usr/gnu/bin"*) ]]; then
        echo
        echo "Adding /usr/gnu/bin to PATH for Solaris"
        PATH="/usr/gnu/bin:$PATH"
    fi
elif [[ -d "/usr/swf/bin" ]]; then
    if [[ ! ("$PATH" == *"/usr/sfw/bin"*) ]]; then
        echo
        echo "Adding /usr/sfw/bin to PATH for Solaris"
        PATH="/usr/sfw/bin:$PATH"
    fi
elif [[ -d "/usr/ucb/bin" ]]; then
    if [[ ! ("$PATH" == *"/usr/ucb/bin"*) ]]; then
        echo
        echo "Adding /usr/ucb/bin to PATH for Solaris"
        PATH="/usr/ucb/bin:$PATH"
    fi
fi

###############################################################################

if [[ -z $(command -v gzip 2>/dev/null) ]]; then
    echo "Some packages gzip. Please install gzip."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if [[ -z $(command -v autoreconf 2>/dev/null) ]]; then
    echo "Some packages require autoreconf. Please install autoconf or automake."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if [[ ! -f "$HOME/.cacert/lets-encrypt-root-x3.pem" ]]; then
    echo "Wget requires several CA roots. Please run build-cacert.sh."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

if [[ ! -f "$HOME/.cacert/identrust-root-x3.pem" ]]; then
    echo "Wget requires several CA roots. Please run build-cacert.sh."
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

LETS_ENCRYPT_ROOT="$HOME/.cacert/lets-encrypt-root-x3.pem"
IDENTRUST_ROOT="$HOME/.cacert/identrust-root-x3.pem"

###############################################################################

echo
echo "If you enter a sudo password, then it will be used for installation."
echo "If you don't enter a password, then ensure INSTALL_PREFIX is writable."
echo "To avoid sudo and the password, just press ENTER and they won't be used."
read -r -s -p "Please enter password for sudo: " SUDO_PASSWWORD
echo

###############################################################################

THIS_SYSTEM=$(uname -s 2>&1)
IS_DARWIN=$(echo -n "$THIS_SYSTEM" | grep -i -c darwin)
IS_LINUX=$(echo -n "$THIS_SYSTEM" | grep -i -c linux)
IS_CYGWIN=$(echo -n "$THIS_SYSTEM" | grep -i -c cygwin)
IS_MINGW=$(echo -n "$THIS_SYSTEM" | grep -i -c mingw)
IS_OPENBSD=$(echo -n "$THIS_SYSTEM" | grep -i -c openbsd)
IS_DRAGONFLY=$(echo -n "$THIS_SYSTEM" | grep -i -c dragonfly)
IS_FREEBSD=$(echo -n "$THIS_SYSTEM" | grep -i -c freebsd)
IS_NETBSD=$(echo -n "$THIS_SYSTEM" | grep -i -c netbsd)
IS_SOLARIS=$(echo -n "$THIS_SYSTEM" | grep -i -c sunos)

# The BSDs and Solaris should have GMake installed if its needed
if [[ $(command -v gmake 2>/dev/null) ]]; then
    MAKE="gmake"
else
    MAKE="make"
fi

# Try to determine 32 vs 64-bit, /usr/local/lib, /usr/local/lib32 and /usr/local/lib64
# The Autoconf programs misdetect Solaris as x86 even though its x64. OpenBSD has
# getconf, but it does not have LONG_BIT.
IS_64BIT=$(getconf LONG_BIT 2>&1 | grep -i -c 64)
if [[ "$IS_64BIT" -eq "0" ]]; then
    IS_64BIT=$(file /bin/ls 2>&1 | grep -i -c '64-bit')
fi

if [[ "$IS_SOLARIS" -eq "1" ]]; then
    SH_KBITS="64"
    SH_MARCH="-m64"
    INSTALL_LIBDIR="$INSTALL_PREFIX/lib64"
    INSTALL_LIBDIR_DIR="lib64"
elif [[ "$IS_64BIT" -eq "1" ]]; then
    if [[ (-d /usr/lib) && (-d /usr/lib32) ]]; then
        SH_KBITS="64"
        SH_MARCH="-m64"
        INSTALL_LIBDIR="$INSTALL_PREFIX/lib"
        INSTALL_LIBDIR_DIR="lib"
    elif [[ (-d /usr/lib) && (-d /usr/lib64) ]]; then
        SH_KBITS="64"
        SH_MARCH="-m64"
        INSTALL_LIBDIR="$INSTALL_PREFIX/lib64"
        INSTALL_LIBDIR_DIR="lib64"
    else
        SH_KBITS="64"
        SH_MARCH="-m64"
        INSTALL_LIBDIR="$INSTALL_PREFIX/lib"
        INSTALL_LIBDIR_DIR="lib"
    fi
else
    SH_KBITS="32"
    SH_MARCH="-m32"
    INSTALL_LIBDIR="$INSTALL_PREFIX/lib"
    INSTALL_LIBDIR_DIR="lib"
fi

if [[ (-z "$CC" && $(command -v cc 2>/dev/null) ) ]]; then CC=$(command -v cc); fi
if [[ (-z "$CXX" && $(command -v CC 2>/dev/null) ) ]]; then CXX=$(command -v CC); fi

# Emacs uses signals, and it needs _XOPEN_SOURCE for Newlib
IS_NEWLIB=$(echo '#include <stdlib.h>' | "$CC" -x c -dM -E - | grep -i -c "__NEWLIB__")

MARCH_ERROR=$($CC $SH_MARCH -x c -c -o /dev/null - </dev/null 2>&1 | grep -i -c error)
if [[ "$MARCH_ERROR" -ne "0" ]]; then
    SH_MARCH=
fi

SH_PIC="-fPIC"
PIC_ERROR=$($CC $SH_PIC -x c -c -o /dev/null - </dev/null 2>&1 | grep -i -c error)
if [[ "$PIC_ERROR" -ne "0" ]]; then
    SH_PIC=
fi

# Solaris fixup.... Ncurses 6.0 does not build and the patches don't apply
if [[ "$IS_SOLARIS" -ne "0" ]]; then
  NCURSES_TAR=ncurses-5.9.tar.gz
  NCURSES_DIR=ncurses-5.9
fi

echo
echo "********** libdir **********"
echo
echo "Using libdir $INSTALL_LIBDIR"

###############################################################################

echo
echo "********** zLib **********"
echo

wget "http://www.zlib.net/$ZLIB_TAR" -O "$ZLIB_TAR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download zLib"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -rf "$ZLIB_DIR" &>/dev/null
gzip -d < "$ZLIB_TAR" | tar xf -
cd "$ZLIB_DIR"

if [[ "$IS_CYGWIN" -ne "0" ]]; then
    if [[ -f "gzguts.h" ]]; then
        sed -i 's/defined(_WIN32) || defined(__CYGWIN__)/defined(_WIN32)/g' gzguts.h
    fi
fi

SH_LDLIBS=("-ldl" "-lpthread")
SH_LDFLAGS=("$SH_MARCH" "-Wl,-rpath,$INSTALL_LIBDIR" "-L$INSTALL_LIBDIR")

    CPPFLAGS="-I$INSTALL_PREFIX/include -DNDEBUG" \
    CFLAGS="$SH_MARCH" CXXFLAGS="$SH_MARCH" \
    LDFLAGS="${SH_LDFLAGS[*]}" LIBS="${SH_LDLIBS[*]}" \
./configure --enable-shared --prefix="$INSTALL_PREFIX" --libdir="$INSTALL_LIBDIR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to configure zLib"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=(-j "$MAKE_JOBS")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to build zLib"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=(install)
if [[ ! (-z "$SUDO_PASSWWORD") ]]; then
    echo "$SUDO_PASSWWORD" | sudo -S "$MAKE" "${MAKE_FLAGS[@]}"
else
    "$MAKE" "${MAKE_FLAGS[@]}"
fi

cd "$CURR_DIR"

###############################################################################

echo
echo "********** ncurses **********"
echo

wget --ca-certificate="$IDENTRUST_ROOT" "https://ftp.gnu.org/pub/gnu/ncurses/$NCURSES_TAR" -O "$NCURSES_TAR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download zLib"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -rf "$NCURSES_DIR" &>/dev/null
gzip -d < "$NCURSES_TAR" | tar xf -
cd "$NCURSES_DIR"

SH_LDLIBS=("-ldl" "-lpthread")
SH_LDFLAGS=("$SH_MARCH" "-Wl,-rpath,$INSTALL_LIBDIR" "-L$INSTALL_LIBDIR")

    CPPFLAGS="-I$INSTALL_PREFIX/include -DNDEBUG $SH_PIC" \
    CFLAGS="$SH_MARCH" CXXFLAGS="$SH_MARCH" \
    LDFLAGS="${SH_LDFLAGS[*]}" LIBS="${SH_LDLIBS[*]}" \
./configure --enable-shared --prefix="$INSTALL_PREFIX" --libdir="$INSTALL_LIBDIR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to configure ncurses"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=(-j "$MAKE_JOBS")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to build ncurses"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=(install)
if [[ ! (-z "$SUDO_PASSWWORD") ]]; then
    echo "$SUDO_PASSWWORD" | sudo -S "$MAKE" "${MAKE_FLAGS[@]}"
else
    "$MAKE" "${MAKE_FLAGS[@]}"
fi

cd "$CURR_DIR"

###############################################################################

echo
echo "********** Emacs **********"
echo

wget --ca-certificate="$IDENTRUST_ROOT" "https://ftp.gnu.org/gnu/emacs/$EMACS_TAR" -O "$EMACS_TAR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download Emacs"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -rf "$EMACS_DIR" &>/dev/null
gzip -d < "$EMACS_TAR" | tar xf -
cd "$EMACS_DIR"

SH_CPPFLAGS="-I$INSTALL_PREFIX/include -DNDEBUG -pthread"
SH_CFLAGS="$SH_MARCH"
SH_CXXFLAGS="$SH_MARCH"
SH_LDFLAGS=("$SH_MARCH" "-Wl,-rpath,$INSTALL_LIBDIR" "-L$INSTALL_LIBDIR" "-pthread")
SH_LDLIBS=("-ldl" "-lpthread")

# http://pubs.opengroup.org/onlinepubs/009695399/functions/xsh_chap02_02.html
# But Cygwin or Newlib headers are mostly fucked up at the moment.
if [[ "$IS_NEWLIB" -ne "0" ]]; then
    SH_CPPFLAGS="$SH_CPPFLAGS -D_XOPEN_SOURCE=600"
fi

    CPPFLAGS="$SH_CPPFLAGS" \
    CFLAGS="$SH_CFLAGS" CXXFLAGS="$SH_CXXFLAGS" \
    LDFLAGS="${SH_LDFLAGS[*]}" LIBS="${SH_LDLIBS[*]}" \
./configure --prefix="$INSTALL_PREFIX" --libdir="$INSTALL_LIBDIR" \
    --with-xml2 --without-x --without-sound --without-xpm \
    --without-jpeg --without-tiff --without-gif --without-png --without-rsvg \
    --without-imagemagick --without-xft --without-libotf --without-m17n-flt \
    --without-xaw3d --without-toolkit-scroll-bars --without-gpm --without-dbus \
    --without-gconf --without-gsettings --without-makeinfo \
    --without-compress-install

if [[ "$?" -ne "0" ]]; then
    echo "Failed to configure emacs"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=(-j "$MAKE_JOBS" all)
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to build emacs"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=(install)
if [[ ! (-z "$SUDO_PASSWWORD") ]]; then
    echo "$SUDO_PASSWWORD" | sudo -S "$MAKE" "${MAKE_FLAGS[@]}"
else
    "$MAKE" "${MAKE_FLAGS[@]}"
fi

cd "$CURR_DIR"

###############################################################################

echo
echo "********** Cleanup **********"
echo

# Set to false to retain artifacts
if true; then

    ARTIFACTS=("$ZLIB_TAR" "$ZLIB_DIR" "$NCURSES_TAR" "$NCURSES_DIR" "$EMACS_TAR" "$EMACS_DIR")

    for artifact in "${ARTIFACTS[@]}"; do
        rm -rf "$artifact"
    done

    # ./build-emacs.sh 2>&1 | tee build-emacs.log
    if [[ -e build-emacs.log ]]; then
        rm build-emacs.log
    fi
fi

[[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0
