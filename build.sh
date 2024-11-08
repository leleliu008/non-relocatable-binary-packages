#!/bin/sh

# Copyright (c) 2024-2024 刘富频
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


set -e

# If IFS is not set, the default value will be <space><tab><newline>
# https://pubs.opengroup.org/onlinepubs/9699919799/utilities/V3_chap02.html#tag_18_05_03
unset IFS


COLOR_RED='\033[0;31m'          # Red
COLOR_GREEN='\033[0;32m'        # Green
COLOR_YELLOW='\033[0;33m'       # Yellow
COLOR_BLUE='\033[0;94m'         # Blue
COLOR_PURPLE='\033[0;35m'       # Purple
COLOR_OFF='\033[0m'             # Reset

print() {
    printf '%b' "$*"
}

echo() {
    printf '%b\n' "$*"
}

note() {
    printf '%b\n' "${COLOR_YELLOW}🔔  $*${COLOR_OFF}" >&2
}

warn() {
    printf '%b\n' "${COLOR_YELLOW}🔥  $*${COLOR_OFF}" >&2
}

success() {
    printf '%b\n' "${COLOR_GREEN}[✔] $*${COLOR_OFF}" >&2
}

error() {
    printf '%b\n' "${COLOR_RED}💔  $ARG0: $*${COLOR_OFF}" >&2
}

abort() {
    EXIT_STATUS_CODE="$1"
    shift
    printf '%b\n' "${COLOR_RED}💔  $ARG0: $*${COLOR_OFF}" >&2
    exit "$EXIT_STATUS_CODE"
}

run() {
    echo "${COLOR_PURPLE}==>${COLOR_OFF} ${COLOR_GREEN}$@${COLOR_OFF}"
    eval "$@"
}

isInteger() {
    case "${1#[+-]}" in
        (*[!0123456789]*) return 1 ;;
        ('')              return 1 ;;
        (*)               return 0 ;;
    esac
}

# wfetch <URL> [--uri=<URL-MIRROR>] [--sha256=<SHA256>] [-o <OUTPUT-PATH>] [--no-buffer]
#
# If -o <OUTPUT-PATH> option is unspecified, the result will be written to <PWD>/$(basename <URL>).
#
# If <OUTPUT-PATH> is . .. ./ ../ or ends with slash(/), then it will be treated as a directory, otherwise, it will be treated as a filepath.
#
# If <OUTPUT-PATH> is -, then it will be treated as /dev/stdout.
#
# If <OUTPUT-PATH> is treated as a directory, then it will be expanded to <OUTPUT-PATH>/$(basename <URL>)
#
wfetch() {
    unset FETCH_UTS
    unset FETCH_SHA

    unset FETCH_URL
    unset FETCH_URI

    unset FETCH_PATH

    unset FETCH_OUTPUT_DIR
    unset FETCH_OUTPUT_FILEPATH
    unset FETCH_OUTPUT_FILENAME

    unset FETCH_BUFFER_FILEPATH

    unset FETCH_SHA256_EXPECTED

    unset NOT_BUFFER

    [ -z "$1" ] && abort 1 "wfetch <URL> [OPTION]... , <URL> must be non-empty."

    if [ -z "$URL_TRANSFORM" ] ; then
        FETCH_URL="$1"
    else
        FETCH_URL="$("$URL_TRANSFORM" "$1")" || return 1
    fi

    shift

    while [ -n "$1" ]
    do
        case $1 in
            --uri=*)
                FETCH_URI="${1#*=}"
                ;;
            --sha256=*)
                FETCH_SHA256_EXPECTED="${1#*=}"
                ;;
            -o) shift
                if [ -z "$1" ] ; then
                    abort 1 "wfetch <URL> -o <PATH> , <PATH> must be non-empty."
                else
                    FETCH_PATH="$1"
                fi
                ;;
            --no-buffer)
                NOT_BUFFER=1
                ;;
            *)  abort 1 "wfetch <URL> [--uri=<URL-MIRROR>] [--sha256=<SHA256>] [-o <PATH>] [-q] , unrecognized option: $1"
        esac
        shift
    done

    if [ -z "$FETCH_URI" ] ; then
        # remove query params
        FETCH_URI="${FETCH_URL%%'?'*}"
        FETCH_URI="https://fossies.org/linux/misc/${FETCH_URI##*/}"
    else
        if [ -n "$URL_TRANSFORM" ] ; then
            FETCH_URI="$("$URL_TRANSFORM" "$FETCH_URI")" || return 1
        fi
    fi

    case $FETCH_PATH in
        -)  FETCH_BUFFER_FILEPATH='-' ;;
        .|'')
            FETCH_OUTPUT_DIR='.'
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        ..)
            FETCH_OUTPUT_DIR='..'
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        */)
            FETCH_OUTPUT_DIR="${FETCH_PATH%/}"
            FETCH_OUTPUT_FILEPATH="$FETCH_OUTPUT_DIR/${FETCH_URL##*/}"
            ;;
        *)
            FETCH_OUTPUT_DIR="$(dirname "$FETCH_PATH")"
            FETCH_OUTPUT_FILEPATH="$FETCH_PATH"
    esac

    if [ -n "$FETCH_OUTPUT_FILEPATH" ] ; then
        if [ -f "$FETCH_OUTPUT_FILEPATH" ] ; then
            if [ -n "$FETCH_SHA256_EXPECTED" ] ; then
                if [ "$(sha256sum "$FETCH_OUTPUT_FILEPATH" | cut -d ' ' -f1)" = "$FETCH_SHA256_EXPECTED" ] ; then
                    success "$FETCH_OUTPUT_FILEPATH already have been fetched."
                    return 0
                fi
            fi
        fi

        if [ "$NOT_BUFFER" = 1 ] ; then
            FETCH_BUFFER_FILEPATH="$FETCH_OUTPUT_FILEPATH"
        else
            FETCH_UTS="$(date +%s)"

            FETCH_SHA="$(printf '%s\n' "$FETCH_URL:$$:$FETCH_UTS" | sha256sum | cut -d ' ' -f1)"

            FETCH_BUFFER_FILEPATH="$FETCH_OUTPUT_DIR/$FETCH_SHA.tmp"
        fi
    fi

    for FETCH_TOOL in curl wget http lynx aria2c axel
    do
        if command -v "$FETCH_TOOL" > /dev/null ; then
            break
        else
            unset FETCH_TOOL
        fi
    done

    if [ -z "$FETCH_TOOL" ] ; then
        abort 1 "no fetch tool found, please install one of curl wget http lynx aria2c axel, then try again."
    fi

    if [                -n "$FETCH_OUTPUT_DIR" ] ; then
        if [ !          -d "$FETCH_OUTPUT_DIR" ] ; then
            run install -d "$FETCH_OUTPUT_DIR" || return 1
        fi
    fi

    case $FETCH_TOOL in
        curl)
            CURL_OPTIONS="--fail --retry 20 --retry-delay 30 --location"

            if [ "$DUMP_HTTP" = 1 ] ; then
                CURL_OPTIONS="$CURL_OPTIONS --verbose"
            fi

            if [ -n "$SSL_CERT_FILE" ] ; then
                CURL_OPTIONS="$CURL_OPTIONS --cacert $SSL_CERT_FILE"
            fi

            run "curl $CURL_OPTIONS -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "curl $CURL_OPTIONS -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        wget)
            run "wget --timeout=60 -O '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "wget --timeout=60 -O '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        http)
            run "http --timeout=60 -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "http --timeout=60 -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        lynx)
            run "lynx -source '$FETCH_URL' > '$FETCH_BUFFER_FILEPATH'" ||
            run "lynx -source '$FETCH_URI' > '$FETCH_BUFFER_FILEPATH'"
            ;;
        aria2c)
            run "aria2c -d '$FETCH_OUTPUT_DIR' -o '$FETCH_OUTPUT_FILENAME' '$FETCH_URL'" ||
            run "aria2c -d '$FETCH_OUTPUT_DIR' -o '$FETCH_OUTPUT_FILENAME' '$FETCH_URI'"
            ;;
        axel)
            run "axel -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URL'" ||
            run "axel -o '$FETCH_BUFFER_FILEPATH' '$FETCH_URI'"
            ;;
        *)  abort 1 "wfetch() unimplementation: $FETCH_TOOL"
            ;;
    esac

    [ $? -eq 0 ] || return 1

    if [ -n "$FETCH_OUTPUT_FILEPATH" ] ; then
        if [ -n "$FETCH_SHA256_EXPECTED" ] ; then
            FETCH_SHA256_ACTUAL="$(sha256sum "$FETCH_BUFFER_FILEPATH" | cut -d ' ' -f1)"

            if [ "$FETCH_SHA256_ACTUAL" != "$FETCH_SHA256_EXPECTED" ] ; then
                abort 1 "sha256sum mismatch.\n    expect : $FETCH_SHA256_EXPECTED\n    actual : $FETCH_SHA256_ACTUAL\n"
            fi
        fi

        if [ "$NOT_BUFFER" != 1 ] ; then
            run mv "$FETCH_BUFFER_FILEPATH" "$FETCH_OUTPUT_FILEPATH"
        fi
    fi
}

filetype_from_url() {
    # remove query params
    URL="${1%%'?'*}"

    FNAME="${URL##*/}"

    case $FNAME in
        *.tar.gz|*.tgz)
            printf '%s\n' '.tgz'
            ;;
        *.tar.lz|*.tlz)
            printf '%s\n' '.tlz'
            ;;
        *.tar.xz|*.txz)
            printf '%s\n' '.txz'
            ;;
        *.tar.bz2|*.tbz2)
            printf '%s\n' '.tbz2'
            ;;
        *.*)printf '%s\n' ".${FNAME##*.}"
    esac
}

inspect_install_arguments() {
    unset PROFILE

    unset LOG_LEVEL

    unset BUILD_NJOBS

    unset ENABLE_LTO

    unset REQUEST_TO_KEEP_SESSION_DIR

    unset REQUEST_TO_EXPORT_COMPILE_COMMANDS_JSON

    unset SPECIFIED_PACKAGE_LIST

    unset SESSION_DIR
    unset DOWNLOAD_DIR
    unset PACKAGE_INSTALL_DIR

    unset DUMP_ENV
    unset DUMP_HTTP

    unset VERBOSE_GMAKE

    unset DEBUG_CC
    unset DEBUG_LD

    while [ -n "$1" ]
    do
        case $1 in
            -x) set -x ;;
            -q) LOG_LEVEL=0 ;;
            -v) LOG_LEVEL=2

                DUMP_ENV=1
                DUMP_HTTP=1

                VERBOSE_GMAKE=1
                ;;
            -vv)LOG_LEVEL=3

                DUMP_ENV=1
                DUMP_HTTP=1

                VERBOSE_GMAKE=1

                DEBUG_CC=1
                DEBUG_LD=1
                ;;
            -v-env)
                DUMP_ENV=1
                ;;
            -v-http)
                DUMP_HTTP=1
                ;;
            -v-gmake)
                VERBOSE_GMAKE=1
                ;;
            -v-cc)
                DEBUG_CC=1
                ;;
            -v-ld)
                DEBUG_LD=1
                ;;
            --profile=*)
                PROFILE="${1#*=}"
                ;;
            --session-dir=*)
                SESSION_DIR="${1#*=}"

                case $SESSION_DIR in
                    /*) ;;
                    *)  SESSION_DIR="$PWD/$SESSION_DIR"
                esac
                ;;
            --download-dir=*)
                DOWNLOAD_DIR="${1#*=}"

                case $DOWNLOAD_DIR in
                    /*) ;;
                    *)  DOWNLOAD_DIR="$PWD/$DOWNLOAD_DIR"
                esac
                ;;
            --prefix=*)
                PACKAGE_INSTALL_DIR="${1#*=}"

                case $PACKAGE_INSTALL_DIR in
                    /*) ;;
                    *)  PACKAGE_INSTALL_DIR="$PWD/$PACKAGE_INSTALL_DIR"
                esac
                ;;
            -j) shift
                isInteger "$1" || abort 1 "-j <N>, <N> must be an integer."
                BUILD_NJOBS="$1"
                ;;
            -K) REQUEST_TO_KEEP_SESSION_DIR=1 ;;
            -E) REQUEST_TO_EXPORT_COMPILE_COMMANDS_JSON=1 ;;

            -*) abort 1 "unrecognized option: $1"
                ;;
            *)  SPECIFIED_PACKAGE_LIST="$SPECIFIED_PACKAGE_LIST $1"
        esac
        shift
    done

    #########################################################################################

    : ${PROFILE:=release}
    : ${ENABLE_LTO:=1}

    : ${SESSION_DIR:="$HOME/.xbuilder/run/$$"}
    : ${DOWNLOAD_DIR:="$HOME/.xbuilder/downloads"}
    : ${PACKAGE_INSTALL_DIR:="$HOME/.xbuilder/installed/non-relocatable"}

    #########################################################################################

    NATIVE_PLATFORM_KIND="$(uname -s | tr A-Z a-z)"
    NATIVE_PLATFORM_ARCH="$(uname -m)"

    #########################################################################################

    if [ -z "$BUILD_NJOBS" ] ; then
        if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
            NATIVE_PLATFORM_NCPU="$(sysctl -n machdep.cpu.thread_count)"
        else
            NATIVE_PLATFORM_NCPU="$(nproc)"
        fi

        BUILD_NJOBS="$NATIVE_PLATFORM_NCPU"
    fi

    #########################################################################################

    if [ "$LOG_LEVEL" = 0 ] ; then
        exec 1>/dev/null
        exec 2>&1
    else
        if [ -z "$LOG_LEVEL" ] ; then
            LOG_LEVEL=1
        fi
    fi

    #########################################################################################

    if [ -z "$TAR" ] ; then
        TAR="$(command -v bsdtar || command -v gtar || command -v tar)" || abort 1 "none of bsdtar, gtar, tar command was found."
    fi

    if [ -z "$GMAKE" ] ; then
        GMAKE="$(command -v gmake || command -v make)" || abort 1 "command not found: gmake"
    fi

    #########################################################################################

    unset CC_ARGS
    unset PP_ARGS
    unset LD_ARGS

    if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
        [ -z "$CC"      ] &&      CC="$(xcrun --sdk macosx --find clang)"
        [ -z "$CXX"     ] &&     CXX="$(xcrun --sdk macosx --find clang++)"
        [ -z "$AS"      ] &&      AS="$(xcrun --sdk macosx --find as)"
        [ -z "$LD"      ] &&      LD="$(xcrun --sdk macosx --find ld)"
        [ -z "$AR"      ] &&      AR="$(xcrun --sdk macosx --find ar)"
        [ -z "$RANLIB"  ] &&  RANLIB="$(xcrun --sdk macosx --find ranlib)"
        [ -z "$SYSROOT" ] && SYSROOT="$(xcrun --sdk macosx --show-sdk-path)"

        [ -z "$MACOSX_DEPLOYMENT_TARGET" ] && MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion)"

        CC_ARGS="-isysroot $SYSROOT -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -arch $NATIVE_PLATFORM_ARCH -Qunused-arguments"
        PP_ARGS="-isysroot $SYSROOT -Qunused-arguments"
        LD_ARGS="-isysroot $SYSROOT -mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET -arch $NATIVE_PLATFORM_ARCH"
    else
        [ -z "$CC" ] && {
             CC="$(command -v cc  || command -v clang   || command -v gcc)" || abort 1 "C Compiler not found."
        }

        [ -z "$CXX" ] && {
            CXX="$(command -v c++ || command -v clang++ || command -v g++)" || abort 1 "C++ Compiler not found."
        }

        [ -z "$AS" ] && {
            AS="$(command -v as)" || abort 1 "command not found: as"
        }

        [ -z "$LD" ] && {
            LD="$(command -v ld)" || abort 1 "command not found: ld"
        }

        [ -z "$AR" ] && {
            AR="$(command -v ar)" || abort 1 "command not found: ar"
        }

        [ -z "$RANLIB" ] && {
            RANLIB="$(command -v ranlib)" || abort 1 "command not found: ranlib"
        }

        CC_ARGS="-fPIC -fno-common"

        # https://gcc.gnu.org/onlinedocs/gcc/Link-Options.html
        LD_ARGS="-Wl,--as-needed -Wl,-z,muldefs -Wl,--allow-multiple-definition"
    fi

    #########################################################################################

    CPP="$CC -E"

    #########################################################################################

    [ "$DEBUG_CC" = 1 ] && CC_ARGS="$CC_ARGS -v"
    [ "$DEBUG_LD" = 1 ] && LD_ARGS="$LD_ARGS -Wl,-v"

    case $PROFILE in
        debug)
            CC_ARGS="$CC_ARGS -O0 -g"
            ;;
        release)
            CC_ARGS="$CC_ARGS -Os"

            if [ "$ENABLE_LTO" = 1 ] ; then
                LD_ARGS="$LD_ARGS -flto"
            fi

            if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
                LD_ARGS="$LD_ARGS -Wl,-S"
            else
                LD_ARGS="$LD_ARGS -Wl,-s"
            fi
    esac

    case $NATIVE_PLATFORM_KIND in
         netbsd) LD_ARGS="$LD_ARGS -lpthread" ;;
        openbsd) LD_ARGS="$LD_ARGS -lpthread" ;;
    esac

    #########################################################################################

    PATH="$PACKAGE_INSTALL_DIR/bin:$PATH"

    PP_ARGS="$PP_ARGS -I$PACKAGE_INSTALL_DIR/include"

    LD_ARGS="$LD_ARGS -L$PACKAGE_INSTALL_DIR/lib -Wl,-rpath,$PACKAGE_INSTALL_DIR/lib"

    #########################################################################################

      CFLAGS="$CC_ARGS   $CFLAGS"
    CXXFLAGS="$CC_ARGS $CXXFLAGS"
    CPPFLAGS="$PP_ARGS $CPPFLAGS"
     LDFLAGS="$LD_ARGS  $LDFLAGS"

    #########################################################################################

    for TOOL in CC CXX CPP AS AR RANLIB LD SYSROOT CFLAGS CXXFLAGS CPPFLAGS LDFLAGS
    do
        export "${TOOL}"
    done

    #########################################################################################

    export PKG_CONFIG_LIBDIR="$PACKAGE_INSTALL_DIR/lib/pkgconfig"
    export PKG_CONFIG_PATH="$PACKAGE_INSTALL_DIR/lib/pkgconfig"
    export ACLOCAL_PATH="$PACKAGE_INSTALL_DIR/share/aclocal"

    #########################################################################################

    unset LIBS

    # autoreconf --help

    unset AUTOCONF
    unset AUTOHEADER
    unset AUTOM4TE
    unset AUTOMAKE
    unset AUTOPOINT
    unset ACLOCAL
    unset GTKDOCIZE
    unset INTLTOOLIZE
    unset LIBTOOLIZE
    unset M4
    unset MAKE

    # https://stackoverflow.com/questions/18476490/what-is-purpose-of-target-arch-variable-in-makefiles
    unset TARGET_ARCH

    # https://keith.github.io/xcode-man-pages/xcrun.1.html
    unset SDKROOT
}


configure() {
    for FILENAME in config.sub config.guess
    do
        FILEPATH="$SESSION_DIR/$FILENAME"

        [ -f "$FILEPATH" ] || {
            wfetch "https://git.savannah.gnu.org/cgit/config.git/plain/$FILENAME" -o "$FILEPATH"

            run chmod a+x "$FILEPATH"

            if [ "$FILENAME" = 'config.sub' ] ; then
                sed -i.bak 's/arm64-*/arm64-*|arm64e-*/g' "$FILEPATH"
            fi
        }

        find . -name "$FILENAME" -exec cp -vf "$FILEPATH" {} \;
    done

    run ./configure "--prefix=$PACKAGE_INSTALL_DIR" "$@"
    run "$GMAKE" "--jobs=$BUILD_NJOBS"
    run "$GMAKE" install
}

install_the_given_package() {
    [ -z "$1" ] && abort 1 "install_the_given_package <PACKAGE-NAME> , <PACKAGE-NAME> is unspecified."

    unset PACKAGE_SRC_URL
    unset PACKAGE_SRC_URI
    unset PACKAGE_SRC_SHA
    unset PACKAGE_DEP_PKG
    unset PACKAGE_DOPATCH
    unset PACKAGE_INSTALL
    unset PACKAGE_DOTWEAK

    package_info_$1

    #########################################################################################

    for PACKAGE_DEPENDENCY in $PACKAGE_DEP_PKG
    do
        (install_the_given_package "$PACKAGE_DEPENDENCY")
    done

    #########################################################################################

    printf '\n%b\n' "${COLOR_PURPLE}=>> $ARG0: install package : $1${COLOR_OFF}"

    #########################################################################################

    if [ -f "$PACKAGE_INSTALL_DIR/$1.yml" ] ; then
        note "package '$1' already has been installed, skipped."
        return 0
    fi

    #########################################################################################

    PACKAGE_SRC_FILETYPE="$(filetype_from_url "$PACKAGE_SRC_URL")"
    PACKAGE_SRC_FILENAME="$PACKAGE_SRC_SHA$PACKAGE_SRC_FILETYPE"
    PACKAGE_SRC_FILEPATH="$DOWNLOAD_DIR/$PACKAGE_SRC_FILENAME"

    #########################################################################################

    wfetch "$PACKAGE_SRC_URL" --uri="$PACKAGE_SRC_URI" --sha256="$PACKAGE_SRC_SHA" -o "$PACKAGE_SRC_FILEPATH"

    #########################################################################################

    PACKAGE_WORKING_DIR="$SESSION_DIR/$1"

    #########################################################################################

    run install -d "$PACKAGE_WORKING_DIR/src"
    run cd         "$PACKAGE_WORKING_DIR/src"

    #########################################################################################

    run "$TAR" xf "$PACKAGE_SRC_FILEPATH" --strip-components=1 --no-same-owner

    #########################################################################################

    if [ -n  "$PACKAGE_DOPATCH" ] ; then
        eval "$PACKAGE_DOPATCH"
    fi

    #########################################################################################

    if [ "$DUMP_ENV" = 1 ] ; then
        run export -p
    fi

    #########################################################################################

    if [ -n  "$PACKAGE_INSTALL" ] ; then
        eval "$PACKAGE_INSTALL"
    else
        abort 1 "PACKAGE_INSTALL variable is not set for package '$1'"
    fi

    #########################################################################################

    run cd "$PACKAGE_INSTALL_DIR"

    #########################################################################################

    if [ -n  "$PACKAGE_DOTWEAK" ] ; then
        eval "$PACKAGE_DOTWEAK"
    fi

    #########################################################################################

    PACKAGE_INSTALL_UTS="$(date +%s)"

    cat > "$PACKAGE_INSTALL_DIR/$1.yml" <<EOF
src-url: $PACKAGE_SRC_URL
src-uri: $PACKAGE_SRC_URI
src-sha: $PACKAGE_SRC_SHA
dep-pkg: $PACKAGE_DEP_PKG
install: $PACKAGE_INSTALL
builtat: $PACKAGE_INSTALL_UTS
EOF
}

package_info_gm4() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz'
    PACKAGE_SRC_SHA='63aede5c6d33b6d9b13511cd0be2cac046f2e70fd0a07aa9573a04a82783af96'
    PACKAGE_INSTALL='configure'
}

package_info_perl() {
    PACKAGE_SRC_URL='https://cpan.metacpan.org/authors/id/P/PE/PEVANS/perl-5.38.2.tar.xz'
    PACKAGE_SRC_URI='https://distfiles.macports.org/perl5.38/perl-5.38.2.tar.xz'
    PACKAGE_SRC_SHA='d91115e90b896520e83d4de6b52f8254ef2b70a8d545ffab33200ea9f1cf29e8'
    PACKAGE_INSTALL='run ./Configure "-Dprefix=$PACKAGE_INSTALL_DIR" -Dman1dir=none -Dman3dir=none -des -Dmake=gmake -Duselargefiles -Duseshrplib -Dusethreads -Dusenm=false -Dusedl=true && run "$GMAKE" "--jobs=$BUILD_NJOBS" && run "$GMAKE" install'
}

package_info_autoconf() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/autoconf/autoconf-2.71.tar.gz'
    PACKAGE_SRC_SHA='431075ad0bf529ef13cb41e9042c542381103e80015686222b8a9d4abef42a1c'
    PACKAGE_DEP_PKG='perl gm4'
    PACKAGE_INSTALL='configure'
}

package_info_automake() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/automake/automake-1.16.5.tar.xz'
    PACKAGE_SRC_SHA='f01d58cd6d9d77fbdca9eb4bbd5ead1988228fdb73d6f7a201f5f8d6b118b469'
    PACKAGE_DEP_PKG='autoconf'
    PACKAGE_INSTALL='configure'
}

package_info_texinfo() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/texinfo/texinfo-7.1.tar.xz'
    PACKAGE_SRC_SHA='deeec9f19f159e046fdf8ad22231981806dac332cc372f1c763504ad82b30953'
    PACKAGE_DEP_PKG='perl'
    PACKAGE_DOPATCH='sed -i.bak "/libintl/d" tp/Texinfo/XS/parsetexi/api.c'
    PACKAGE_INSTALL='configure --with-included-regex --enable-threads=posix --disable-nls'
}

package_info_help2man() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/help2man/help2man-1.49.3.tar.xz'
    PACKAGE_SRC_SHA='4d7e4fdef2eca6afe07a2682151cea78781e0a4e8f9622142d9f70c083a2fd4f'
    PACKAGE_DEP_PKG='perl'
    PACKAGE_INSTALL='configure'
}

package_info_libexpat() {
    PACKAGE_SRC_URL='https://github.com/libexpat/libexpat/releases/download/R_2_6_3/expat-2.6.3.tar.xz'
    PACKAGE_SRC_SHA='274db254a6979bde5aad404763a704956940e465843f2a9bd9ed7af22e2c0efc'
    PACKAGE_INSTALL='configure --disable-dependency-tracking --enable-static --enable-shared --without-xmlwf --without-tests --without-examples --without-docbook'
}

package_info_gsed() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/sed/sed-4.9.tar.xz'
    PACKAGE_SRC_SHA='6e226b732e1cd739464ad6862bd1a1aba42d7982922da7a53519631d24975181'
    PACKAGE_INSTALL='configure --program-prefix=g --with-included-regex --without-selinux --disable-acl --disable-assert'
}

package_info_perl_XML_Parser() {
    PACKAGE_SRC_URL='https://cpan.metacpan.org/authors/id/T/TO/TODDR/XML-Parser-2.47.tar.gz'
    PACKAGE_SRC_SHA='ad4aae643ec784f489b956abe952432871a622d4e2b5c619e8855accbfc4d1d8'
    PACKAGE_DEP_PKG='gsed perl libexpat'
    PACKAGE_DOPATCH='
run export EXPATLIBPATH="$PACKAGE_INSTALL_DIR/lib"
run export EXPATINCPATH="$PACKAGE_INSTALL_DIR/include"
run gsed -i "\"/check_lib/a not_execute,\"" Makefile.PL
'
    if [ "$NATIVE_PLATFORM_KIND" = darwin ] ; then
        PACKAGE_INSTALL='run perl Makefile.PL && run "$GMAKE" "--jobs=$BUILD_NJOBS" && run "$GMAKE" install'
    else
        PACKAGE_INSTALL='run perl Makefile.PL LDDLFLAGS="\"-shared -Wl,-rpath,$PACKAGE_INSTALL_DIR/lib\"" && run "$GMAKE" "--jobs=$BUILD_NJOBS" && run "$GMAKE" install'
    fi
}

package_info_intltool() {
    PACKAGE_SRC_URL='https://launchpad.net/intltool/trunk/0.51.0/+download/intltool-0.51.0.tar.gz'
    PACKAGE_SRC_SHA='67c74d94196b153b774ab9f89b2fa6c6ba79352407037c8c14d5aeb334e959cd'
    PACKAGE_DEP_PKG='perl_XML_Parser'
    PACKAGE_INSTALL='configure'
}

package_info_libtool() {
    PACKAGE_SRC_URL='https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz'
    PACKAGE_SRC_SHA='4f7f217f057ce655ff22559ad221a0fd8ef84ad1fc5fcb6990cecc333aa1635d'
    PACKAGE_INSTALL='configure --enable-ltdl-install'
    PACKAGE_DOTWEAK='
run ln -s libtool    bin/glibtool
run ln -s libtoolize bin/glibtoolize
'
}

package_info_pkgconf() {
    PACKAGE_SRC_URL='https://distfiles.ariadne.space/pkgconf/pkgconf-2.3.0.tar.xz'
    PACKAGE_SRC_SHA='3a9080ac51d03615e7c1910a0a2a8df08424892b5f13b0628a204d3fcce0ea8b'
    PACKAGE_INSTALL='configure'
    PACKAGE_DOTWEAK='run ln -s pkgconf bin/pkg-config'
}

help() {
    printf '%b\n' "\
${COLOR_GREEN}A package builder to build non-relocatable packages such as automake, autoconf, libtool, etc.${COLOR_OFF}

${COLOR_GREEN}$ARG0 --help${COLOR_OFF}
${COLOR_GREEN}$ARG0 -h${COLOR_OFF}
    show help of this command.

${COLOR_GREEN}$ARG0 ls-available [-v]${COLOR_OFF}
    install the available packages.

${COLOR_GREEN}$ARG0 install <PACKAGE-NAME>... [OPTIONS]${COLOR_OFF}
    install the specified packages.

    Influential environment variables: TAR, GMAKE, CC, CXX, AS, LD, AR, RANLIB, CFLAGS, CXXFLAGS, CPPFLAGS, LDFLAGS

    OPTIONS:
        ${COLOR_BLUE}--prefix=<DIR>${COLOR_OFF}
            specify where to be installed into.

        ${COLOR_BLUE}--session-dir=<DIR>${COLOR_OFF}
            specify the session directory.

        ${COLOR_BLUE}--download-dir=<DIR>${COLOR_OFF}
            specify the download directory.

        ${COLOR_BLUE}-j <N>${COLOR_OFF}
            specify the number of jobs you can run in parallel.

        ${COLOR_BLUE}-E${COLOR_OFF}
            export compile_commands.json

        ${COLOR_BLUE}-K${COLOR_OFF}
            keep the session directory even if this packages are successfully installed.

        ${COLOR_BLUE}-x${COLOR_OFF}
            debug current running shell.

        ${COLOR_BLUE}-q${COLOR_OFF}
            silent mode. no any messages will be output to terminal.

        ${COLOR_BLUE}-v${COLOR_OFF}
            verbose mode. many messages will be output to terminal.

            This option is equivalent to -v-* options all are supplied.

        ${COLOR_BLUE}-vv${COLOR_OFF}
            very verbose mode. many many messages will be output to terminal.

            This option is equivalent to -v-* options all are supplied.

        ${COLOR_BLUE}-v-env${COLOR_OFF}
            show all environment variables before starting to build.

        ${COLOR_BLUE}-v-http${COLOR_OFF}
            show http request/response.

        ${COLOR_BLUE}-v-gmake${COLOR_OFF}
            pass V=1 argument to gmake command.

        ${COLOR_BLUE}-v-cc${COLOR_OFF}
            pass -v argument to the C/C++ compiler.

        ${COLOR_BLUE}-v-ld${COLOR_OFF}
            pass -v argument to the linker.
"
}

ARG0="$0"

case $1 in
    ''|--help|-h)
        help
        ;;
    ls-available)
        PACKAGE_NAMES='gm4 perl autoconf automake texinfo help2man libtool libexpat perl_XML_Parser intltool pkgconf'

        if [ "$2" = -v ] ; then
            for PACKAGE_NAME in $PACKAGE_NAMES
            do
                unset PACKAGE_SRC_URL
                unset PACKAGE_SRC_URI
                unset PACKAGE_SRC_SHA
                unset PACKAGE_DEP_PKG
                unset PACKAGE_DOPATCH
                unset PACKAGE_INSTALL
                unset PACKAGE_DOTWEAK

                package_info_$PACKAGE_NAME

                cat <<EOF
$PACKAGE_NAME:
    src-url: $PACKAGE_SRC_URL
    src-sha: $PACKAGE_SRC_SHA

EOF
            done
        else
            printf '%s\n' $PACKAGE_NAMES
        fi
        ;;
    install)
        shift

        inspect_install_arguments "$@"

        for PACKAGE_NAME in $SPECIFIED_PACKAGE_LIST
        do
            (install_the_given_package "$PACKAGE_NAME")
        done

        cat > "$PACKAGE_INSTALL_DIR/toolchain.txt" <<EOF
     CC='$CC'
    CXX='$CXX'
     AS='$AS'
     LD='$LD'
     AR='$AR'
 RANLIB='$RANLIB'
SYSROOT='$SYSROOT'
PROFILE='$PROFILE'
 CFLAGS='$CFLAGS'
LDFLAGS='$LDFLAGS'
EOF

        if [ "$REQUEST_TO_KEEP_SESSION_DIR" != 1 ] ; then
            rm -rf "$SESSION_DIR"
        fi
        ;;
    *)  abort 1 "unrecognized argument: $1"
esac