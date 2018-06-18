#!/bin/bash

#PBS -N neutral-bdw
#PBS -o gcc-7.3.out
#PBS -q large
#PBS -l nodes=1
#PBS -l walltime=00:15:00
#PBS -joe

if [ -z "$PBS_O_WORKDIR" ]
then
    echo "Submit this script via qsub."
    exit 1
fi

cd $PBS_O_WORKDIR

module swap PrgEnv-{cray,gnu}
module swap gcc gcc/7.3.0

EXE=neutral.omp3.bdw.gcc-7.3

DIR="$PWD/../arch/neutral"
if [ $# -gt 0 ]
then
    DIR="$1"
fi

if [ ! -r "$DIR/$EXE" ]
then
    echo "Directory '$DIR' does not exist or does not contain $EXE"
    exit 1
fi

cd $DIR

export OMP_PROC_BIND=true
export OMP_NUM_THREADS=88
aprun -n 1 -d 88 -j 2 -cc none ./$EXE problems/csp.params