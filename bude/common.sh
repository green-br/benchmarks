# shellcheck shell=bash

set -eu
set -o pipefail

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
if [ $# -lt 1 ]; then
  usage
  exit 1
elif [ "$1" = '-h' ] || [ "$1" = '--help' ]; then
  usage
  exit
fi


action="$1"
if [ "$action" == "run" ]
then
    shift
    RUN_ARGS="$1"
fi
export COMPILER="${2:-$DEFAULT_COMPILER}"
export CONFIG="${PLATFORM}_${COMPILER}"

SCRIPT="`realpath $0`"
SCRIPT_DIR="`realpath $(dirname $SCRIPT)`"

if [ "${BUILDTOOL:-}" == "spack" ]; then
  export BENCHMARK_EXE="omp-bude"
  export CFG_DIR="$PWD/${PLATFORM}/bude/${COMPILER}"
  export ENV_NAME="bude_$COMPILER"
else
  export SRC_DIR="$PWD/miniBUDE/openmp"
  export BENCHMARK_EXE="bude"
fi

# Set up the environment
setup_env


if [ "${BUILDTOOL:-}" != "spack" ]; then
  # Fetch source code
  if ! "$SCRIPT_DIR/fetch.sh"
  then
    echo
    echo "Failed to fetch source code."
    echo
    exit 1
  fi
fi

# Handle actions
if [ "$action" == "build" ]; then
  if [ "${BUILDTOOL:-}" == "spack" ]; then
    cat > bude.yaml <<EOF
spack:
  include:
    - $PWD/buildit/config/3/v0.23/linux/compilers.yaml
    - $PWD/buildit/config/3/v0.23/packages.yaml
  view: true
  concretizer:
    unify: true
    reuse: false
  specs:
    - minibude%$SPACK_COMPILER model=omp
EOF
    spack env create -d ./$ENV_NAME bude.yaml
    spack env activate ./$ENV_NAME
    spack repo add ./buildit/repo/v0.23/isamrepo
    spack concretize
    spack install
    spack env deactivate
    mkdir -p "$CFG_DIR"

  else
    rm -f "$SRC_DIR/$BENCHMARK_EXE" "$CFG_DIR/$BENCHMARK_EXE"
    if ! eval make -C "$SRC_DIR" -B "$MAKE_OPTS" -j; then
      echo
      echo "Build failed."
      echo
      exit 1
    fi

    mkdir -p "$CFG_DIR"
    mv "$SRC_DIR/$BENCHMARK_EXE" "$CFG_DIR"
  fi
elif [ "$action" == "run" ]; then
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
    # Check binary exists
    if [ ! -x "$CFG_DIR/$BENCHMARK_EXE" ]; then
      echo "Executable '$CFG_DIR/$BENCHMARK_EXE' not found."
      echo "Use the 'build' action first."
      exit 1
    fi
  fi

  cd "$CFG_DIR"
  if [ "$RUN_ARGS" == "node" ]
  then
      NODES=1
      JOBSCRIPT=node.job
  elif [[ "$RUN_ARGS" == scale-* ]]
  then
      echo "miniBUDE does not support multi-node jobs"
      exit 7
  else
      echo
      echo "Invalid 'run' argument '$RUN_ARGS'"
      usage
      exit 1
  fi

  # Submit job
  mkdir -p "results"
  cd results
  if [ "${SCHEDULER:-}" == "slurm" ]; then
    sbatch --nodes=$NODES \
      --output=${RUN_ARGS}_${COMPILER}.out \
      --job-name="bude_${RUN_ARGS}_${CONFIG}" \
      ${SLURM_RESOURCES:-} \
      "$PLATFORM_DIR/${JOBSCRIPT}"
  else
    qsub -l select=$NODES${PBS_RESOURCES:-} \
        -o ${RUN_ARGS}_${COMPILER}.out \
        -N "bude_${RUN_ARGS}_${CONFIG}" \
        -V \
        "$PLATFORM_DIR/$JOBSCRIPT"
  fi

else
  echo
  echo "Invalid action (use 'build' or 'run')."
  echo
  exit 1
fi
