#!/bin/bash

set -u

function usage
{
    echo
    echo "Usage:"
    echo "  # Build the benchmark"
    echo "  ./benchmark.sh build [COMPILER]"
    echo
    echo "  # Run on a single node"
    echo "  ./benchmark.sh run node [COMPILER]"
    echo
    echo "  # Run on N nodes"
    echo "  ./benchmark.sh run scale-N [COMPILER]"
    echo
    echo "Valid compilers:"
    for COMPILER in $COMPILERS
    do
      echo "  $COMPILER"
    done
    echo
    echo "The default configuration is '$DEFAULT_COMPILER'."
    echo
}

# Process arguments
if [ $# -lt 1 ]
then
    usage
    exit 1
fi

ACTION="$1"
if [ "$ACTION" == "run" ]
then
    shift
    RUN_ARGS="${1:-}"
fi
export COMPILER="${2:-$DEFAULT_COMPILER}"
SCRIPT="`realpath $0`"
SCRIPT_DIR="`realpath $(dirname $SCRIPT)`"


if [ "${BUILDTOOL:-}" == "spack" ]; then
  export BENCHMARK_EXE="clover_leaf"
  export CFG_DIR="$PWD/${PLATFORM}/cloverleaf/${COMPILER}"
  export ENV_NAME="cloverleaf_$COMPILER"
else
  export BENCHMARK_EXE=clover_leaf
  export SRC_DIR="$PWD/CloverLeaf_ref"
  export CFG_DIR="$PWD/cloverleaf/${ARCH}/${COMPILER}"
fi

export CONFIG="${ARCH:-$PLATFORM}_${COMPILER}"
# Set up the environment
setup_env

# Handle actions

if [ "$ACTION" == "build" ]
then
  if [ "${BUILDTOOL:-}" == "spack" ]; then
    cat > cloverleaf.yaml <<EOF
spack:
  include:
    - $PWD/buildit/config/3/v0.23/linux/compilers.yaml
    - $PWD/buildit/config/3/v0.23/packages.yaml
  view: true
  concretizer:
    unify: true
    reuse: false
  specs:
    - cloverleaf-ref%$SPACK_COMPILER fflags=-fallow-argument-mismatch
EOF
    spack env create -d ./$ENV_NAME cloverleaf.yaml
    spack env activate ./$ENV_NAME
    spack repo add ./buildit/repo/v0.23/isamrepo
    spack concretize
    spack install
    spack env deactivate
    mkdir -p "$CFG_DIR"

  else
    # Fetch source code
    if ! "$SCRIPT_DIR/fetch.sh"
    then
      echo
      echo "Failed to fetch source code."
      echo
      exit 1
    fi

    # Perform build
    rm -f "$SRC_DIR/$BENCHMARK_EXE" "$CFG_DIR/$BENCHMARK_EXE"
    if ! eval make -C "$SRC_DIR" -B $MAKE_OPTS
    then
      echo
      echo "Build failed."
      echo
      exit 1
    fi

    mkdir -p "$CFG_DIR"
    mv "$SRC_DIR/$BENCHMARK_EXE" "$CFG_DIR"
  fi
elif [ "$ACTION" == "run" ]
then
  if [ "${BUILDTOOL:-}" == "spack" ]; then
    if ! spack env activate ./$ENV_NAME; then
      echo "Spack env ./$ENV_NAME not found."
      echo "Use the 'build' action first."
      exit 1
    fi
    if ! type -P "$BENCHMARK_EXE" 2>&1 >/dev/null; then
      echo "$BENCHMARK_EXE not found in Spack env ./$ENV_NAME"
      exit 1
    fi
    # This is really install location
    FULL_EXE="`type -P $BENCHMARK_EXE`"
    export SRC_DIR="`realpath $(dirname $FULL_EXE)/..`"
  else
    if [ ! -x "$CFG_DIR/$BENCHMARK_EXE" ]
    then
        echo "Executable '$CFG_DIR/$BENCHMARK_EXE' not found."
        echo "Use the 'build' action first."
        exit 1
    fi
  fi
  cd "$CFG_DIR"

  if [ "$RUN_ARGS" == node ]
  then
      NODES=1
      JOBSCRIPT=node.job
  elif [[ "$RUN_ARGS" == scale-* ]]
  then
      export NODES=${RUN_ARGS#scale-}
      if ! [[ "$NODES" =~ ^[0-9]+$ ]]
      then
          echo
          echo "Invalid node count for 'run scale-N' action"
          echo
          exit 1
      fi
      JOBSCRIPT=scale.job
  else
      echo
      echo "Invalid 'run' argument '$RUN_ARGS'"
      usage
      exit 1
  fi

  # Some systems use a different shell for jobs, breaking exported functions
  [ "${SYSTEM:-}" = catalyst ] && unset -f setup_env
  mkdir -p "results-${RUN_ARGS}"
  cd results-${RUN_ARGS}
  if [ "${SCHEDULER:-}" == "slurm" ]; then
    sbatch --nodes=$NODES \
      --output=${RUN_ARGS}_${COMPILER}.out \
      --job-name="cloverleaf_${RUN_ARGS}_${CONFIG}" \
      ${SLURM_RESOURCES:-} \
      "$PLATFORM_DIR/${JOBSCRIPT}"
  else
    qsub -l select=$NODES${PBS_RESOURCES:-} \
        -o ${RUN_ARGS}_${COMPILER}.out \
        -N "cloverleaf_${RUN_ARGS}_${CONFIG}" \
        -V \
        "$PLATFORM_DIR/$JOBSCRIPT"
  fi
else
    echo
    echo "Invalid action (use 'build' or 'run')."
    echo
    exit 1
fi
