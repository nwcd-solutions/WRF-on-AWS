#!/bin/bash -xe
#Load Parallelcluster environment variables
. /etc/parallelcluster/cfnconfig
cd /fsx
aws s3 cp https://aws-hpc-builder.s3.amazonaws.com/project/wrf/aws_pcluster_3.4_al2_wrf_aarch64.tar.xz .
