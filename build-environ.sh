#!/usr/bin/env bash

# Written and placed in public domain by Jeffrey Walton
# This script creates the environment for other scripts to execute in.

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

THIS_SYSTEM=$(uname -s 2>&1)
IS_DARWIN=$(echo -n "$THIS_SYSTEM" | grep -i -c darwin)
IS_SOLARIS=$(echo -n "$THIS_SYSTEM" | grep -i -c sunos)

# The BSDs and Solaris should have GMake installed if its needed
if [[ -z "$MAKE" ]]; then
    if [[ $(command -v gmake 2>/dev/null) ]]; then
        export MAKE="gmake"
    else
        export MAKE="make"
    fi
fi

# Try to determine 32 vs 64-bit, /usr/local/lib, /usr/local/lib32 and /usr/local/lib64
# The Autoconf programs misdetect Solaris as x86 even though its x64. OpenBSD has
# getconf, but it does not have LONG_BIT.
IS_64BIT=$(getconf LONG_BIT 2>&1 | grep -i -c 64)
if [[ "$IS_64BIT" -eq "0" ]]; then
    IS_64BIT=$(file /bin/ls 2>&1 | grep -i -c '64-bit')
fi

# Don't override a user choice of INSTALL_PREFIX
if [[ -z "$INSTALL_PREFIX" ]]; then
    INSTALL_PREFIX="/usr/local"
    export INSTALL_PREFIX
fi

# Don't override a user choice of INSTALL_LIBDIR
if [[ -z "$INSTALL_LIBDIR" ]]; then
    if [[ "$IS_SOLARIS" -ne "0" ]]; then
        INSTALL_LIBDIR="$INSTALL_PREFIX/lib64"
    elif [[ "$IS_64BIT" -ne "0" ]]; then
        if [[ (-d /usr/lib) && (-d /usr/lib32) ]]; then
            INSTALL_LIBDIR="$INSTALL_PREFIX/lib"
        elif [[ (-d /usr/lib) && (-d /usr/lib64) ]]; then
            INSTALL_LIBDIR="$INSTALL_PREFIX/lib64"
        else
            INSTALL_LIBDIR="$INSTALL_PREFIX/lib"
        fi
    else
        INSTALL_LIBDIR="$INSTALL_PREFIX/lib"
    fi

	export INSTALL_LIBDIR
fi

if [[ "$IS_SOLARIS" -ne "0" ]]; then
    SH_MARCH="-m64"
elif [[ "$IS_64BIT" -ne "0" ]]; then
    if [[ (-d /usr/lib) && (-d /usr/lib32) ]]; then
        SH_MARCH="-m64"
    elif [[ (-d /usr/lib) && (-d /usr/lib64) ]]; then
        SH_MARCH="-m64"
    else
        SH_MARCH="-m64"
    fi
else
    SH_MARCH="-m32"
fi

if [[ (-z "$CC" && $(command -v cc 2>/dev/null) ) ]]; then CC=$(command -v cc); fi
if [[ (-z "$CXX" && $(command -v CC 2>/dev/null) ) ]]; then CXX=$(command -v CC); fi

MARCH_ERROR=$($CC $SH_MARCH -x c -c -o /dev/null - </dev/null 2>&1 | grep -i -c -E "fatal|error|not found")
if [[ "$MARCH_ERROR" -ne "0" ]]; then
    SH_MARCH=
fi

SH_PIC="-fPIC"
PIC_ERROR=$($CC $SH_PIC -x c -c -o /dev/null - </dev/null 2>&1 | grep -i -c -E "fatal|error|not found")
if [[ "$PIC_ERROR" -ne "0" ]]; then
    SH_PIC=
fi

# For the benefit of the programs and libraries. Make them run faster.
SH_NATIVE="-march=native"
NATIVE_ERROR=$($CC $SH_NATIVE -x c -c -o /dev/null - </dev/null 2>&1 | grep -i -c -E "fatal|error|not found")
if [[ "$NATIVE_ERROR" -ne "0" ]]; then
    SH_NATIVE=
fi

GNU_LD=$(ld -v 2>&1 | grep -i -c 'GNU ld')
if [[ "$GNU_LD" -ne "0" ]]; then
    SH_ERROR=$(echo 'int main() {}' | $CC -Wl,--enable-new-dtags -x c -o /dev/null - 2>&1 | grep -i -c -E 'fatal|error|not found')
    if [[ "$SH_ERROR" -eq "0" ]]; then
        SH_DTAGS="-Wl,--enable-new-dtags"
    fi
fi

###############################################################################

BUILD_PKGCONFIG=("$INSTALL_LIBDIR/pkgconfig")
BUILD_CPPFLAGS=("-I$INSTALL_PREFIX/include" "-DNDEBUG")
BUILD_CFLAGS=("$SH_MARCH" "$SH_NATIVE")
BUILD_CXXFLAGS=("$SH_MARCH" "$SH_NATIVE")
BUILD_LDFLAGS=("$SH_MARCH" "-Wl,-rpath,$INSTALL_LIBDIR" "-L$INSTALL_LIBDIR")
BUILD_LIBS=("-ldl" "-lpthread")

if [[ ! -z "$SH_PIC" ]]; then
    BUILD_CFLAGS+=("$SH_PIC")
    BUILD_CXXFLAGS+=("$SH_PIC")
fi

if [[ ! -z "$SH_DTAGS" ]]; then
    BUILD_LDFLAGS+=("$SH_DTAGS")
fi

if [[ -z "$BUILD_OPTS" ]]; then

    echo ""
    echo "Common flags and options:"
    echo ""
	echo " INSTALL_PREFIX: $INSTALL_PREFIX"
	echo " INSTALL_LIBDIR: $INSTALL_LIBDIR"
    echo ""
    echo "      PKGCONFIG: ${BUILD_PKGCONFIG[*]}"
    echo "       CPPFLAGS: ${BUILD_CPPFLAGS[*]}"
    echo "         CFLAGS: ${BUILD_CFLAGS[*]}"
    echo "       CXXFLAGS: ${BUILD_CXXFLAGS[*]}"
    echo "        LDFLAGS: ${BUILD_LDFLAGS[*]}"
    echo "         LDLIBS: ${BUILD_LIBS[*]}"

fi

export BUILD_OPTS="TRUE"