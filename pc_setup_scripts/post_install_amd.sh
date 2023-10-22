#!/bin/bash -l
. /etc/parallelcluster/cfnconfig
set -ex
#shared_folder=$(echo $cfn_ebs_shared_dirs | cut -d ',' -f 1 )
shared_folder=/fsx
domains_num=$1

# Set ulimits according to WRF needs
cat >>/tmp/limits.conf << EOF
# core file size (blocks, -c) 0
*           hard    core           0
*           soft    core           0
# data seg size (kbytes, -d) unlimited
*           hard    data           unlimited
*           soft    data           unlimited
# scheduling priority (-e) 0
*           hard    priority       0
*           soft    priority       0
# file size (blocks, -f) unlimited
*           hard    fsize          unlimited
*           soft    fsize          unlimited
# pending signals (-i) 256273
*           hard    sigpending     1015390
*           soft    sigpending     1015390
# max locked memory (kbytes, -l) unlimited
*           hard    memlock        unlimited
*           soft    memlock        unlimited
# open files (-n) 1024
*           hard    nofile         65536
*           soft    nofile         65536
# POSIX message queues (bytes, -q) 819200
*           hard    msgqueue       819200
*           soft    msgqueue       819200
# real-time priority (-r) 0
*           hard    rtprio         0
*           soft    rtprio         0
# stack size (kbytes, -s) unlimited
*           hard    stack          unlimited
*           soft    stack          unlimited
# cpu time (seconds, -t) unlimited
*           hard    cpu            unlimited
*           soft    cpu            unlimited
# max user processes (-u) 1024
*           soft    nproc          16384
*           hard    nproc          16384
# file locks (-x) unlimited
*           hard    locks          unlimited
*           soft    locks          unlimited
EOF

sudo bash -c 'cat /tmp/limits.conf > /etc/security/limits.conf'

download_wrf_install_package() {
  echo "Download wrf pre-compiled installation package"
  chmod 777 ${shared_folder}
  cd ${shared_folder}
  wget https://aws-hpc-builder.s3.amazonaws.com/project/apps/aws_pcluster_3.4_alinux2_wrf_amd64.tar.xz
  tar xpf aws_pcluster_3.4_alinux2_wrf_amd64.tar.xz
  chown -R ec2-user:ec2-user ${shared_folder}
}

#build dir
build_dir(){
  WRF_VERSION=4.2.2 
  WPS_VERSION=4.2
  jobdir=/fsx/FORECASET/domains
  source /apps/scripts/env.sh 3 2
  WPS_DIR=${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/WRF-${WRF_VERSION}/WPS-${WPS_VERSION} 
  WRF_DIR=${HPC_PREFIX}/${HPC_COMPILER}/${HPC_MPI}/WRF-${WRF_VERSION}
  for (( i=1; i<=$1; i++ ))
  do
     echo $i
     mkdir -p $jobdir/$i/run
     mkdir -p $jobdir/$i/preproc
     ln -s ${WPS_DIR}/geogrid* $jobdir/$i/preproc/
     ln -s ${WPS_DIR}/link_grib.csh $jobdir/$i/preproc/
     ln -s ${WPS_DIR}/metgrid* $jobdir/$i/preproc/
     ln -s ${WPS_DIR}/ungrib.exe $jobdir/$i/preproc/ungrib.exe
     ln -s ${WPS_DIR}/ungrib/Variable_Tables/Vtable.GFS $jobdir/$i/preproc/Vtable
     cp -a ${WRF_DIR}/run $jobdir/$i/run
     rm $jobdir/$i/run/wrf.exe
     rm $jobdir/$i/run/real.exe
     ln -s ${WRF_DIR}/main/real.exe  $jobdir/$i/run/real.exe
     ln -s ${WRF_DIR}/main/wrf.exe  $jobdir/$i/run/wrf.exe
  done
  mkdir -p $jobdir/downloads  
  chown -R ec2-user:ec2-user ${jobdir}
}
echo "NODE TYPE: ${cfn_node_type}"

case ${cfn_node_type} in
        HeadNode)
                echo "I am the HeadNode node"
                #download_wrf_install_package
		            sed -i s"|PREFIX=/fsx|PREFIX=/apps|g" /apps/scripts/env.sh
                cd ${shared_folder}
		            build_dir $domains_num 
 
                
        ;;
        ComputeFleet)
                echo "I am a Compute node"
        ;;
        esac
        
exit 0
