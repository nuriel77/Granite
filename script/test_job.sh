#!/bin/bash
#SBATCH -n 4
#SBATCH --time=00:10:50
#SBATCH --workdir=/tmp

srun -l hostname
srun -l sleep 50

