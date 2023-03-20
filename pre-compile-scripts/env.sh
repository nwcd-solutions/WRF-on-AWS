#!/bin/bash
# Copyright # Copyright (C) 2022 by Amazon.com, Inc. or its affiliates.  All Rights Reserved.
# SPDX-License-Identifier: MIT
#--------------------------- customized Job env -----------------------------

export SHARED_DIR=/fsx
export GEOG_BASE_DIR=${SHARED_DIR}/spooler/domains/geog

#ENV VARIABLES#

#------------------------------- Run-time env -------------------------------
# compiler & MPI selection
# compiler table:
# ---------------
# 0 VENDOR's compiler, Intel=icc, AMD=armclang, ARM=armgcc
# 1 GNU/GCC compiler
# 2 GNU/CLANG compiler
# 3 INTEL/ICC compiler
# 4 INTEL/ICX compiler
# 5 AMD/CLANG compiler
# 6 ARM/GCC compiler
# 7 ARM/CLANG compiler
#
#
# MPI table:
# ----------
# 0 openmpi
# 1 mpich
# 2 intelmpi
# 3 mvapich
#
# usage: env.sh <compiler> <MPI>
#        C M
# env.sh 0 0   ## select vendor's native compilers with openmpi
# env.sh 0 1   ## select vendor's native compilers with mpich
# env.sh 0 2   ## select vendor's native compilers with intelmpi
# env.sh 0 3   ## select vendor's native compilers with mvapich
# env.sh 1 0   ## select GNU/GCC compilers with openmpi
# env.sh ...

export HPC_USE_VENDOR_COMPILER=true
HPC_COMPILER=gcc
HPC_MPI=mpich
#----------------------------------------------------------------------------
source ${SHARED_DIR}/scripts/compiler.sh
source ${SHARED_DIR}/scripts/mpi_settings.sh

export WRF_DIR=${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/WRF-${WRF_VERSION}
export WPS_DIR=${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/WRF-${WRF_VERSION}/WPS-${WRF_VERSION}
export PATH=${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/${HPC_TARGET}/bin:${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/bin:${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/usr/local/bin:${PATH}
export MANPATH=:${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/share/man:${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/usr/local/share/man${MANPATH}
export LD_LIBRARY_PATH=${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/lib64:${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/lib:${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/usr/local/lib64:${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/usr/local/lib:${LD_LIBRARY_PATH}

# To support EFA, use libfabric provided by Amazon
if [ -d /opt/amazon/efa ]
then
    export LD_LIBRARY_PATH=/opt/amazon/efa/lib64:${LD_LIBRARY_PATH}
fi

export OMP_STACKSIZE=128M
