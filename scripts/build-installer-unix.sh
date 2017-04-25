#!/bin/sh
# DEPENDENCIES (binaries should be in PATH):
#   0. 'git'
#   1. 'curl'
#   2. 'nix-shell'
#   3. 'stack'

set -e

usage() {
    test -z "$1" || { echo "ERROR: $*" >&2; echo >&2; }
    cat >&2 <<EOF
  Usage:
    $0 OPTIONS*

  Build a Daedalus installer.

  Options:
    --cardano-branch BRANCH   Mandatory: Cardano SL branch to use with Daedalus
    --os OS                   Mandatory: either 'linux' or 'osx'

    --version VERSION         Daedalus product version; defaults to '0'
    --build-id BUILD-NO       Identifier of the build; defaults to '0'

    --travis-pr PR-ID         Travis pull request id we're building
    --nix-path NIX-PATH       NIX_PATH value

    --verbose                 Verbose operation
    
EOF
    test -z "$1" || exit 1
}
alias   argnz='test $# -ge 1 -a ! -z "$1" || usage "empty value for"'
alias  arg2nz='test $# -ge 2 -a ! -z "$2" || usage "empty value for"'
alias  argnzf='test $# -ge 1 -a ! -z "$1" || fail "missing value for"'
alias arg2nzf='test $# -ge 2 -a ! -z "$2" || fail "missing value for"'
fail() { echo "ERROR: $*" >&2; exit 1;
}
retry() {
        local tries=$1; argnzf "iteration count"; shift
        for i in $(seq 1 ${tries})
        do if "$@"
           then return 0
           fi
           sleep 5s
        done
        fail "persistent failure to exec:  $*"
}

###
### Argument processing
###
os=
verbose=
version=0
build_id=0
cardano_branch=
travis_pr=true

set -u ## Undefined variable firewall enabled
while test $# -ge 1
do case "$1" in
           --cardano-branch ) arg2nz "Cardano SL branch to build Daedalus with";
                                                      cardano_branch="$2"; shift;;
	   --os )             arg2nz "OS to build for";           os="$2"; shift;;
	   --version )        arg2nz "product version";      version="$2"; shift;;
	   --build-id )       arg2nz "build identifier";    build_id="$2"; shift;;
           --travis-pr )      arg2nz "Travis pull request id";
                                                           travis_pr="$2"; shift;;
           --nix-path )       arg2nz "NIX_PATH value";
                                                     export NIX_PATH="$2"; shift;;

           ###
	   --verbose )        echo "--verbose passed, enabling verbose operation";
                                                             verbose=t;;
           --help )           usage;;
	   "--"* )            usage "unknown option: '$1'";;
	   * )                break;; esac
   shift; done

test -n "${cardano_branch}" || usage "Cardano SL branch not specified."
case "${os}" in
        linux )   signing_certificate=linux.p12;;
        osx )     signing_certificate=macos.p12;;
        "" )                   usage "OS is not specified";;
        * )                    usage "Unsupported OS provided: ${os}";;
esac

set -e
if test -n "${verbose}"
then set -x
fi

mkdir -p ~/.local/bin
export PATH=$HOME/.local/bin:$PATH

if test "${os}" = "linux"
then
        echo "INFO: running 'sudo mount -o remount,exec,size=4G,mode=755 /run/user'"
        sudo mount -o remount,exec,size=4G,mode=755 /run/user ||
                fail "Couldn't establish enough free space for the build process:  sudo failed"
else
        echo "INFO: not attempting to establish free space for the build process:  not supported on OS X"
fi

retry 5 bash -c "curl -L https://www.stackage.org/stack/${os}-x86_64 | \
      tar xz --strip-components=1 -C ~/.local/bin"
retry 5 curl -o daedalus-bridge.tar.xz \
      https://s3.eu-central-1.amazonaws.com/cardano-sl-travis/daedalus-bridge-${os}-${cardano_branch}.tar.xz

mkdir -p node_modules/daedalus-client-api/
du -sh  daedalus-bridge.tar.xz
tar xJf daedalus-bridge.tar.xz --strip-components=1 -C node_modules/daedalus-client-api/
rm      daedalus-bridge.tar.xz
echo "cardano-sl build id is $(cat node_modules/daedalus-client-api/build-id)"

nix-shell --run "npm install"

export DAEDALUS_VERSION=${version}.${build_id}
export SSL_CERT_FILE=$NIX_SSL_CERT_FILE

mv node_modules/daedalus-client-api/{log-config-prod.yaml,cardano-node,cardano-launcher} installers/

strip installers/cardano-node installers/cardano-launcher
rm node_modules/daedalus-client-api/cardano-*
nix-shell --run "npm run package -- --icon installers/icons/256x256"
echo "Size of Electron app is $(du -sh release)"

pushd installers
    if test "${travis_pr}" = "false"
    then retry 5 nix-shell -p awscli --run "aws s3 cp --region eu-central-1 s3://iohk-private/${signing_certificate} ${signing_certificate}"
    fi
    stack --no-terminal --nix build --exec make-installer --jobs 2
    mkdir -p dist
popd
echo "Size of Electron app after bundling $(du -sh release)"
