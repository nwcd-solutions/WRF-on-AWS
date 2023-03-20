#!/bin/bash
export SHARED_DIR=/fsx
export WRF_VERSION=3.7.2
source ${SHARED_DIR}/scripts/env.sh 1 1
export JOB_DIR=$(pwd)
export WPSWORK=${JOB_DIR}/preproc
export WRFWORK=${JOB_DIR}/run

#-------------------Example---------------------------------------------------
#export WRF_VERSION=3.9.1
#export JOB_DIR=${PREFIX}/spooler/bench_12km
#export JOB_DIR=${PREFIX}/spooler/bench_2.5km

#export WRF_VERSION=4.2.2
#export JOB_DIR=${PREFIX}/spooler/v4_bench_conus12km
#export JOB_DIR=${PREFIX}/spooler/v4_bench_conus2.5km

#export WRF_VERSION=4.4.1
#export JOB_DIR=${PREFIX}/spooler/v4.4_bench_conus12km
#export JOB_DIR=${PREFIX}/spooler/v4.4_bench_conus2.5km
#----------------------------------------------------------------------------

mkdir -p ${JOB_DIR}/log

cp -a ${WRF_DIR}/run  ${JOB_DIR}
cd  ${JOB_DIR}/run
rm ndown.exe real.exe tc.exe wrf.exe MPTABLE.TBL
ln -s  ${WRF_DIR}/main/ndown.exe ndown.exe
ln -s  ${WRF_DIR}/main/real.exe real.exe
ln -s  ${WRF_DIR}/main/tc.exe tc.exe
ln -s  ${WRF_DIR}/main/wrf.exe wrf.exe
ln -s  ${WRF_DIR}/phys/noahmp/parameters/MPTABLE.TBL MPTABLE.TBL

#Copy WPS Files and links
mkdir ${JOB_DIR}/preproc
cd ${JOB_DIR}/preproc
ln -s ${WPS_DIR}/geogrid.exe geogrid.exe
ln -s ${WPS_DIR}/geogrid/GEOGRID.TBL GEOGRID.TBL
ln -s ${WPS_DIR}/metgrid.exe metgrid.exe
ln -s ${WPS_DIR}/metgrid/METGRID.TBL METGRID.TBL
ln -s ${WPS_DIR}/ungrib.exe ungrib.exe
ln -s ${WPS_DIR}/ungrib/Variable_Tables/Vtable.GFS Vtable
