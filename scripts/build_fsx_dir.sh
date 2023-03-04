#!/bin/bash 
source /shared/setup_env.sh
FSX_DIR=/fsx/FORECAST/domains/test
#Copy WRF Files and links
mkdir -p ${FSX_DIR}
mkdir -p ${FSX_DIR}/log

cp -a ${WRF_DIR}/run  ${FSX_DIR}
cd  ${FSX_DIR}/run
rm ndown.exe real.exe tc.exe wrf.exe MPTABLE.TBL 
ln -s  ${WRF_DIR}/main/ndown.exe ndown.exe
ln -s  ${WRF_DIR}/main/real.exe real.exe
ln -s  ${WRF_DIR}/main/tc.exe tc.exe
ln -s  ${WRF_DIR}/main/wrf.exe wrf.exe
ln -s  ${WRF_DIR}/phys/noahmp/parameters/MPTABLE.TBL MPTABLE.TBL

#Copy WPS Files and links
mkdir ${FSX_DIR}/preproc
cd ${FSX_DIR}/preproc
n -s ${WPS_DIR}/geogrid.exe geogrid.exe
ln -s ${WPS_DIR}/geogrid/GEOGRID.TBL GEOGRID.TBL
ln -s ${WPS_DIR}/metgrid.exe metgrid.exe
ln -s ${WPS_DIR}/metgrid/METGRID.TBL METGRID.TBL
ln -s ${WPS_DIR}/ungrib.exe ungrib.exe
ln -s ${WPS_DIR}/ungrib/Variable_Tables/Vtable.GFS Vtable

mkdir -p /fsx/FORECAST/download

cp -R ${SETUP_DIR}/scripts/fsx/* /fsx/bin
chmod -R 775 /fsx/bin
chmod -R 777 /fsx/FORECAST
