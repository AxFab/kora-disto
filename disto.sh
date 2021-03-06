#!/bin/bash
# Distribution building script for KoraOS
# ----------------------------------------------------------------------------
set -e

SCRIPT_DIR=`dirname "$BASH_SOURCE{0}"`
SCRIPT_HOME=`readlink -f "$SCRIPT_DIR"`
TOPDIR=`pwd`

. "$SCRIPT_HOME/resx/utils.sh"

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
function pkg {
    "$SCRIPT_HOME/resx/pkg.sh" $@
}

function update_file {
    hash1=`sha1sum "$1" | cut -f 1 -d ' '`
    hash2=`sha1sum "$2" | cut -f 1 -d ' '`
    if [ "$hash1" != "$hash2" ]; then
        echo "UPDT -- $2"
        cp "$1" "$2"
    fi
}

function update_prj {
    if [ ! -d "$SCRIPT_HOME/sources/$1" ]; then
        echo "No repository at $SCRIPT_HOME/sources/$1"
        return
    fi
    DIR=`readlink -f $SCRIPT_HOME/sources/$1`
    mkdir -p "$DIR/make"
    update_file "$SCRIPT_HOME/make/build.mk" "$DIR/make/build.mk"
    update_file "$SCRIPT_HOME/make/check.mk" "$DIR/make/check.mk"
    update_file "$SCRIPT_HOME/make/global.mk" "$DIR/make/global.mk"
    update_file "$SCRIPT_HOME/make/targets.mk" "$DIR/make/targets.mk"
    update_file "$SCRIPT_HOME/make/host.sh" "$DIR/make/host.sh"
    update_file "$SCRIPT_HOME/make/configure" "$DIR/configure"
    update_file "$SCRIPT_HOME/make/LICENSE.md" "$DIR/LICENSE.md"

    update_file "$SCRIPT_HOME/make/x.gitattributes" "$DIR/.gitattributes"
    update_file "$SCRIPT_HOME/make/x.gitignore" "$DIR/.gitignore"

    shift
    while (( $# > 0 )); do
        case $1 in
            --drivers)
                update_file "$SCRIPT_HOME/make/drivers.mk" "$DIR/make/drivers.mk"
                ;;
            *)
                echo "Ignore option $1"
                ;;
        esac
        shift
    done
}

# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

function package_clone {
    local SRCDIR="$SCRIPT_HOME/sources/$1"

    if [ ! -f "$SRCDIR/Makefile" ]; then
        echo_info "Download sources for $1"
        var=` echo "KORA_cfg_sources_$1" | tr '-' '_'`
        GIT_URL="${!var}"
        if [ -z "$GIT_URL" ]; then
            echo_error "No referenced source for package $1"
        fi
        mkdir -p "$SCRIPT_HOME/sources"
        cd "$SCRIPT_HOME/sources"
        git clone "$GIT_URL" "$1"
        cd "$SRCDIR"
        git checkout develop
    fi
}

function package_build {
    local SRCDIR="$SCRIPT_HOME/sources/$1"
    local SYSDIR="$SCRIPT_HOME/build-$TARGET/kora-os"
    local PKG_PARAM="--preface=$SCRIPT_HOME/build-${TARGET}/preface.mk"

    shift
    while (( $# > 0 )); do
        case $1 in
            --core)
                PKG_PARAM=''
                ;;
            *)
                echo "Ignore option $1"
                ;;
        esac
        shift
    done

    if [ ! -f "$GENDIR/Makefile" ]; then # <Todo> Or in case we force rebuild
        echo_info "Configure build at $GENDIR"
        rm -rf "$GENDIR"
        mkdir -p "$GENDIR"
        cd "$GENDIR"
        $SRCDIR/configure --target="$TARGET" --prefix="$PREFIX" --sysdir="$SYSDIR" $PKG_PARAM
    fi

    echo_important "Build the product $1"
    cd "$GENDIR"
    # make
    make install
}

function package_publish {
    local SRCDIR="$SCRIPT_HOME/sources/$1"
    local GENDIR="$SCRIPT_HOME/build-$TARGET/$1"
    local PREFIX="$SCRIPT_HOME/build-$TARGET/$1/usr"
    local NAME="$1"
    local VERS="$2"
    local PACKNAME=$1-$VERS.tar.xz

    package_clone $NAME $3
    package_build $NAME $3

    echo_info "Create the package $PACKNAME"
    cd "$PREFIX"
    mkdir -p "$REPODIR"
    tar cvJf "$REPODIR/$PACKNAME" *
}

function package_install {
    var=` echo "KORA_cfg_packages_$1" | tr '-' '_'`
    local NAME=$1
    local VERS="${!var}"
    local PACKNAME=$NAME-$VERS.tar.xz
    local PREFIX="$SCRIPT_HOME/build-$TARGET/kora-os/usr"

    local ARG=''
    shift
    while (( $# > 0 )); do
        case $1 in
            --core)
                PREFIX="$SCRIPT_HOME/build-$TARGET/kora-os"
                ARG=--core
                ;;
            *)
                echo "Ignore option $1"
                ;;
        esac
        shift
    done

    echo_info "Package $NAME ($VERS)"

    if [ "$VERS" == 'src' ] && [ "$NAME" != 'kora-headers' ]; then
        package_publish $NAME $VERS $ARG
    fi


    mkdir -p "$PREFIX"
    echo_important "Install package $NAME:$VERS"
    pkg install "$NAME:$VERS" --target=$TARGET  --prefix="$PREFIX" $PKG_ARGS

    # echo_info "Install $1 $VERS"
    # if [ ! -f "$REPODIR/$PACKNAME" ]; then
    #     echo_error "Unable to find package $PACKNAME"
    # fi
    # mkdir -p "$PREFIX"
    # cd "$PREFIX"
    # tar xvJf "$REPODIR/$PACKNAME"
}

function header_publish {
    package_clone kernel
    package_clone libc

    local VERS="$KORA_cfg_packages_libc"
    if [ "$KORA_cfg_packages_kernel" != "$KORA_cfg_packages_libc" ]; then
        echo_error "In order to package kora headers, kernel and libc source must be on the same version [$KORA_cfg_packages_kernel vs. $KORA_cfg_packages_libc]"
    fi

    local GENDIR="$SCRIPT_HOME/build-$TARGET/kora-headers"
    local PACKNAME=kora-headers-$VERS.tar.xz

    local KERN_DIR="$SCRIPT_HOME/sources/kernel"
    local LIBC_DIR="$SCRIPT_HOME/sources/libc"
    local ARCH=`echo $TARGET | cut -d '-' -f 1`

    echo_important "Build the kora-headers package"
    rm -rf "$GENDIR/usr"
    mkdir -p "$GENDIR/usr"

    cp -r "$LIBC_DIR/include" "$GENDIR/usr/"
    # cp -r "$LIBC_DIR/arch/$ARCH/*" "$TOOL_HEADERS/"
    cp -r "$KERN_DIR/include/kernel" "$GENDIR/usr/include/"
    cp -r "$KERN_DIR/arch/$ARCH/include/kernel/arch.h" "$GENDIR/usr/include/kernel"
    # cp -r "$KERN_DIR/arch/$ARCH/include/kernel/cpu.h" "$GENDIR/usr/include/kernel"
    # cp -r "$KERN_DIR/arch/$ARCH/include/kernel/mmu.h" "$GENDIR/usr/include/kernel"

    echo_info "Create the package $PACKNAME"
    cd "$GENDIR/usr"
    mkdir -p "$REPODIR"
    tar cJf "$REPODIR/$PACKNAME" *
}



# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=

function for_all_packages {
    "$1" kernel --core

    "$1" file-systems --drivers --core
    "$1" drivers-pc --drivers --core
    "$1" drivers-misc --drivers --core

    "$1" libc --core
    "$1" lgfx
    # "$1" gum

    "$1" utils --core
    "$1" krish
    "$1" desktop
}

function update_disto {
    echo_info "Update common kora projects files" ""
    for_all_packages update_prj
}


function clone_disto {
    echo_info "Download kora sources repository" ""
    for_all_packages package_clone
}

# Build Kora distribution image
function build_disto {
    echo_info "Build Kora distribution image" ""

    mkdir -p "$SCRIPT_HOME/build-${TARGET}"

    if [ ! -f "$SCRIPT_HOME/build-${TARGET}/preface.mk" ]; then
        sed "$SCRIPT_HOME/resx/make.in" \
            -e "s%@DIRECTORY%${SCRIPT_HOME}%" \
            -e "s%@TARGET%${TARGET}%" \
            > "$SCRIPT_HOME/build-${TARGET}/preface.mk"
    fi

    header_publish
    package_install kora-headers

    # for_all_packages package_install
    package_install kernel --core
    package_install file-systems --drivers --core
    package_install drivers-pc --drivers --core
    package_install drivers-misc --drivers --core

    package_install libc --core
    package_install utils --core

    package_install openlibm
    package_install zlib
    package_install libpng
    package_install freetype

    package_install lgfx

    package_install krish
    package_install desktop

    # TODO - Set list on config.yml
    # package_install pixman
    # package_install cairo
    # package_install gum
}

function build_image {
    local PREFIX="$SCRIPT_HOME/build-$TARGET/kora-os"

    echo_info "Create boot archive"
    cd "$PREFIX/boot/mods"
    tar cf ../miniboot.tar ata.ko isofs.ko ps2.ko vga.ko

    echo_info "Install grub file"
    mkdir -p "$PREFIX/boot/grub"
    cp "$SCRIPT_HOME/resx/grub.cfg" "$PREFIX/boot/grub/grub.cfg"

    echo_info "Create disk image Kora.iso"
    cd $SCRIPT_HOME
    grub-mkrescue -o Kora.iso "$PREFIX"

    # Library ports
    # openlibm
    # zlib
    # png
    # jpeg
    # bz2
    # freetype2
    # cairo
    # buzybox

    echo_info "  ----"
}

function setup_toolchain {

    local VERS="$KORA_cfg_packages_libc"
    local PACKNAME=kora-headers-$VERS.tar.xz
    if [ "$VERS" == 'src' ]; then
        header_publish
        package_install libc --core
    fi

    if [ -z "$TLSDIR" ]; then
        echo_error "Unable to setup the toolchain"
    fi

    cd "$TLSDIR/usr"
    rm -rf ./include
    tar xvJf "$REPODIR/$PACKNAME"

    cd "$TLSDIR"
    pkg install "libc:$VERS" --target=$TARGET  --prefix="$TLSDIR" $PKG_ARGS
}

function install_toolchain {
    TOOLS="$SCRIPT_HOME/tools/$KORA_cfg_architecture"
    mkdir -p "$TOOLS"
    pkg install -u "kora-${KORA_cfg_architecture}-toolchain" --prefix="$TOOLS"
    export TLSDIR="$TOOLS/bin"
    echo "export CROSS=$TOOLS/bin/" >> "$SCRIPT_HOME/.env.cfg"
    setup_toolchain
}


# -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=
echo_info "KORA DISTRIBUTION" "  ----"

# Load persisted settings
CROSS=''
if [ -f "$SCRIPT_HOME/.env.cfg" ]; then
    . "$SCRIPT_HOME/.env.cfg"
fi

if [ -f "$SCRIPT_HOME/config.yml" ]; then
    echo_info "Use configuration file $SCRIPT_HOME/config.yml"
    # echo `parse_yaml "$SCRIPT_HOME/config.yml" ''`
    source <(parse_yaml "$SCRIPT_HOME/config.yml" 'KORA_cfg_')
fi


TARGET=`$SCRIPT_DIR/make/host.sh "$KORA_cfg_architecture-kora"`
COMMAND=''
TLSDIR=''

# Analyze scripts parameters
while (( $# > 0)); do
    case "$1" in
        --arch=*)
            TARGET=`$SCRIPT_DIR/make/host.sh "${1:7}-kora"`
            ;;
        -*)
            echo_error "Unknown parameter $1"
            ;;
        *)
            if [ -n "$COMMAND" ]; then
                echo_error "Unexpected parameter $1"
            fi
            COMMAND=$1
            ;;
    esac
    shift
done


# Initialize tools
echo_info "Initialize building script"
echo_important "Select target architecture $TARGET"

CHAIN=`echo $TARGET | cut -d '-' -f 1`'-kora'
GCC=`which "${CROSS}$CHAIN-gcc" 2>/dev/null || echo ''`
if [ -n "$GCC" ]; then
    GCC=`readlink -f "$GCC"`
    TLSDIR=`dirname $(dirname "$GCC")`
    echo_info "Found cross toolchain at $TLSDIR"
else
    echo_warning "Unable to find cross toolchain for $CHAIN"
fi

REPODIR="$SCRIPT_HOME/packages/$TARGET"
echo_info "  ----"

# Run the command
case "$COMMAND" in
    'build')
        build_disto
        build_image
        ;;
    'update')
        update_disto
        ;;
    'clone')
        clone_disto
        ;;
    'header')
        header_publish
        ;;
    'setup')
        setup_toolchain
        ;;
    'style')
        cd "$SCRIPT_HOME/sources"
        astyle --style=kr --indent=spaces=4 --indent-col1-comments \
        --min-conditional-indent=1 --pad-oper --pad-header --unpad-paren \
        --align-pointer=name --align-reference=name --break-one-line-headers \
        --remove-brackets --convert-tabs --lineend=linux --mode=c \-r "*.c" "*.h"
        ;;
    # 'tools')
    #     install_toolchain
    #     ;;
    'help'|'')
        echo "Script to manage packaging of the kora-os distribution"
        echo ""
        echo "USAGE: $0 <command>"
        echo ""
        echo "  The script haven't been tested to be used outside its directory"
        echo "  All those command behaviours depends on the configuration of ./config.yml"
        echo ""
        echo "    build         Build the complete OS disk image"
        echo "    update        Update common files of all packages"
        echo "    header        Build the package for kora-headers"
        echo "    setup         Update the toolchain (erase headers)"
        # echo "    tools         Install the toolchain"
        echo "    clone         Clone all sources repositories"
        ;;
    *)
        echo_error "Unknown command $COMMAND"
        ;;
esac

