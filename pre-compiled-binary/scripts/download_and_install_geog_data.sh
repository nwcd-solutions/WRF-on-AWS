#!/bin/bash

cd ${PREFIX}/download
wget --no-check-certificate https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_complete.tar.gz  -q
wget --no-check-certificate https://www2.mmm.ucar.edu/wrf/src/wps_files/albedo_modis.tar.bz2  -q
wget --no-check-certificate https://www2.mmm.ucar.edu/wrf/src/wps_files/maxsnowalb_modis.tar.bz2  -q

#Copy geog data
GEOG_BASE_DIR=${PREFIX}/FORECAST
#mkdir -p ${GEOG_BASE_DIR}
cd  ${GEOG_BASE_DIR}
tar -zxf ${PREFIX}/download/geog_complete.tar.gz
cd  ${GEOG_BASE_DIR}/geog
bzip2 -dc ${PREFIX}/download/albedo_modis.tar.bz2 | tar -xf -
bzip2 -dc ${PREFIX}/download/maxsnowalb_modis.tar.bz2 | tar -xf -
