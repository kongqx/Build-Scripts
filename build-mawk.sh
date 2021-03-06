#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script builds Mawk and its dependencies from sources.
# It is needed on Debian and Ubuntu, not Fedora, OS X, Solaris or friends

MAWK_TAR=mawk.tar.gz
MAWK_DIR=mawk-1.3.4-20171017

# Avoid shellcheck.net warning
CURR_DIR="$PWD"

# Sets the number of make jobs
MAKE_JOBS=4

###############################################################################

# Get the environment as needed. We can't export it because it includes arrays.
if ! source ./build-environ.sh
then
    echo "Failed to set environment"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

# The password should die when this subshell goes out of scope
if [[ -z "$SUDO_PASSWORD" ]]; then
    source ./build-password.sh
fi

###############################################################################

echo
echo "********** mawk **********"
echo

wget --ca-certificate="$IDENTRUST_ROOT" "http://invisible-island.net/datafiles/release/$MAWK_TAR" -O "$MAWK_TAR"

if [[ "$?" -ne "0" ]]; then
    echo "Failed to download mawk"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

rm -rf "$MAWK_DIR" &>/dev/null
gzip -d < "$MAWK_TAR" | tar xf -
cd "$MAWK_DIR"

# http://pkgs.fedoraproject.org/cgit/rpms/gnutls.git/tree/gnutls.spec; thanks NM.
# AIX needs the execute bit reset on the file.
sed -e 's|sys_lib_dlsearch_path_spec="/lib /usr/lib|sys_lib_dlsearch_path_spec="/lib %{_libdir} /usr/lib|g' configure > configure.fixed
mv configure.fixed configure; chmod +x configure

    PKG_CONFIG_PATH="${BUILD_PKGCONFIG[*]}" \
    CPPFLAGS="${BUILD_CPPFLAGS[*]}" \
    CFLAGS="${BUILD_CFLAGS[*]}" \
    CXXFLAGS="${BUILD_CXXFLAGS[*]}" \
    LDFLAGS="${BUILD_LDFLAGS[*]}" \
    LIBS="${BUILD_LIBS[*]}" \
./configure --prefix="$INSTX_PREFIX" --libdir="$INSTX_LIBDIR" \

if [[ "$?" -ne "0" ]]; then
    echo "Failed to configure mawk"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("-j" "$MAKE_JOBS" "all")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to build mawk"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("check")
if ! "$MAKE" "${MAKE_FLAGS[@]}"
then
    echo "Failed to test mawk"
    [[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 1 || return 1
fi

MAKE_FLAGS=("install")
if [[ ! (-z "$SUDO_PASSWORD") ]]; then
    echo "$SUDO_PASSWORD" | sudo -S "$MAKE" "${MAKE_FLAGS[@]}"
    echo "$SUDO_PASSWORD" | sudo -S ln -s "$INSTX_PREFIX/bin/mawk" "$INSTX_PREFIX/bin/awk" 2>/dev/null
else
    "$MAKE" "${MAKE_FLAGS[@]}"
    ln -s "$INSTX_PREFIX/bin/mawk" "$INSTX_PREFIX/bin/awk" 2>/dev/null
fi

cd "$CURR_DIR"

###############################################################################

echo ""
echo "*****************************************************************************"
echo "Please run Bash's 'hash -r' to update program cache in the current shell"
echo "*****************************************************************************"

###############################################################################

# Set to false to retain artifacts
if true; then

    ARTIFACTS=("$MAWK_TAR" "$MAWK_DIR")
    for artifact in "${ARTIFACTS[@]}"; do
        rm -rf "$artifact"
    done

    # ./build-mawk.sh 2>&1 | tee build-mawk.log
    if [[ -e build-mawk.log ]]; then
        rm -f build-mawk.log
    fi

    unset SUDO_PASSWORD
fi

[[ "$0" = "${BASH_SOURCE[0]}" ]] && exit 0 || return 0
