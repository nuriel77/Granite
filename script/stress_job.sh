#!/bin/bash
#SBATCH -n 2
#SBATCH --time=00:01:00
#SBATCH --workdir=/tmp

srun -l /usr/bin/stress  --cpu 12 --timeout 60s


