#!/bin/bash
# shellcheck disable=SC2034 disable=SC2153

set -eu

setup_env() {
  USE_QUEUE=true
  if [ ! -d spack ]; then
    git clone --depth=2 --branch=releases/v0.23 https://github.com/spack/spack.git
  fi
  if [ ! -d buildit ]; then
    git clone https://github.com/green-br/buildit.git
  fi
  export SPACK_DISABLE_LOCAL_CONFIG=true
  . spack/share/spack/setup-env.sh

  case "$COMPILER" in
    gcc-12.3)
      export SPACK_COMPILER="gcc@12.3"
      ;;
    gcc-13.2)
      export SPACK_COMPILER="gcc@13.2"
      ;;
    *)
      echo
      echo "Invalid compiler '$COMPILER'."
      usage
      exit 1
      ;;
  esac
}
export -f setup_env

script="$(realpath "$0")"
SCRIPT_DIR="$(realpath "$(dirname "$script")")"
PLATFORM_DIR="$(realpath "$(dirname "$script")")"
export SCRIPT_DIR PLATFORM_DIR

export BUILDTOOL=spack
export SCHEDULER=slurm
export COMPILERS="gcc-13.2 gcc-12.3"
export DEFAULT_COMPILER="gcc-12.3"
export PLATFORM="grace-isambard"
export SLURM_RESOURCES="--ntasks-per-node=1"

bash "$PLATFORM_DIR/../common.sh" "$@"
