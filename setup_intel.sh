#!/bin/bash -i
. /etc/parallelcluster/cfnconfig

shared_folder=$(echo $cfn_ebs_shared_dirs | cut -d ',' -f 1 )


function create_env_file {
echo "Create Env"
cat <<@EOF >${shared_folder}/intel_setup_env.sh
#!/bin/bash
export SHARED_DIR=${shared_folder}
export SETUP_DIR=${shared_folder}/hpc-workshop-wrf
export BUILDDIR=${shared_folder}/build/oneapiWRF
export DIR=${shared_folder}/oneapiWRF
export SCRIPTDIR=${shared_folder}/oneapiWRF/bin

export TARGET_DIR=\${SHARED_DIR}/FORECAST/domains/test.intel/
export GEOG_BASE_DIR=\${SHARED_DIR}/FORECAST/domains/

export WRF_DIR=\$(spack location -i wrf)
export WPS_DIR=\$(spack location -i wps)

export KMP_STACKSIZE=128M
export KMP_AFFINITY=granularity=fine,compact,1,0
export OMP_NUM_THREADS=2

spack env activate wrf-workshop-env
spack load intel-oneapi-mpi
spack load wrf
spack load wps
spack load wgrib2

@EOF

chmod 777 ${shared_folder}
chmod 755 ${shared_folder}/intel_setup_env.sh
rm -f ${shared_folder}/setup_env.sh
ln -s ${shared_folder}/intel_setup_env.sh ${shared_folder}/setup_env.sh
}

echo "NODE TYPE: ${cfn_node_type}"

case ${cfn_node_type} in
        MasterServer)
                echo "I am Master node"
                create_env_file
                source ${shared_folder}/setup_env.sh
                cd wrf_setup_scripts
                /bin/su ec2-user -c "/bin/bash -i compile_and_install_intel.sh"
                /bin/su ec2-user -c "/bin/bash -i build_dir.sh"

        ;;
        ComputeFleet)
                echo "I am a Compute node"
        ;;
        esac

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
exit 0