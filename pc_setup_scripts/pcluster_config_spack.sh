#!/bin/bash
set -e

##
# Modified version of: https://raw.githubusercontent.com/spack/spack-configs/main/AWS/parallelcluster/postinstall.sh
# Removed gcc compiler install to reduce cluster start-up time
#
##############################################################################################
# # This script will setup Spack and best practices for a few applications.                  #
# # Use as postinstall in AWS ParallelCluster (https://docs.aws.amazon.com/parallelcluster/) #
##############################################################################################

# TODO: Once https://github.com/archspec/archspec-json/pull/57 makes it into Spack we need to rename: graviton2 -> neoverse_n1, graviton3 -> neoverse_v1

# Install onto first shared storage device
cluster_config="/opt/parallelcluster/shared/cluster-config.yaml"
[ -f "${cluster_config}" ] && {
    os=$(python << EOF
#/usr/bin/env python
import yaml
with open("${cluster_config}", 'r') as s:
    print(yaml.safe_load(s)["Image"]["Os"])
EOF
      )

    case "${os}" in
        alinux*)
            cfn_cluster_user="ec2-user"
            ;;
        centos*)
            cfn_cluster_user="centos"
            ;;
        ubuntu*)
            cfn_cluster_user="ubuntu"
            ;;
        *)
            cfn_cluster_user=""
    esac

    cfn_ebs_shared_dirs=$(python << EOF
#/usr/bin/env python
import yaml
with open("${cluster_config}", 'r') as s:
    print(yaml.safe_load(s)["SharedStorage"][0]["MountDir"])
EOF
                       )
} || . /etc/parallelcluster/cfnconfig || {
    echo "Cannot find ParallelCluster configs"
    echo "Installing Spack into /shared/spack for ec2-user."
    cfn_ebs_shared_dirs="/shared"
    cfn_cluster_user="ec2-user"
}

install_path=${SPACK_ROOT:-"${cfn_ebs_shared_dirs}/spack"}
spack_branch="develop"
scriptdir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

major_version() {
    pcluster_version=$(grep -oE '[0-9]*\.[0-9]*\.[0-9]*' /opt/parallelcluster/.bootstrapped)
    echo "${pcluster_version/\.*}"
}

# Make first user owner of Spack installation when script exits.
fix_owner() {
    rc=$?
    if [ -z "${SPACK_ROOT}" ]
    then
        chown -R ${cfn_cluster_user}:${cfn_cluster_user} "${install_path}"
    fi
    exit $rc
}
trap "fix_owner" SIGINT EXIT



architecture() {
    lscpu  | grep "Architecture:" | awk '{print $2}'
}





set_pcluster_defaults() {
    # Set versions of pre-installed software in packages.yaml
    SLURM_VERSION=$(. /etc/profile && sinfo --version | cut -d' ' -f 2 | sed -e 's?\.?-?g')
    LIBFABRIC_MODULE=$(. /etc/profile && module avail libfabric 2>&1 | grep libfabric | head -n 1 | xargs )
    LIBFABRIC_MODULE_VERSION=$(. /etc/profile && module avail libfabric 2>&1 | grep libfabric | head -n 1 |  cut -d / -f 2 | sed -e 's?~??g' | xargs )
    LIBFABRIC_VERSION=${LIBFABRIC_MODULE_VERSION//amzn*}
    GCC_VERSION=$(gcc -v 2>&1 |tail -n 1| awk '{print $3}' )
}

setup_spack() {
    cd "${install_path}"

    # Load spack at login
    if [ -z "${SPACK_ROOT}" ]
    then
        echo ". ${install_path}/share/spack/setup-env.sh" > /etc/profile.d/spack.sh
        echo ". ${install_path}/share/spack/setup-env.csh" > /etc/profile.d/spack.csh
    fi

    . "${install_path}/share/spack/setup-env.sh"
    spack compiler add --scope site
    spack external find --scope site

    # Remove all autotools/buildtools packages. These versions need to be managed by spack or it will
    # eventually end up in a version mismatch (e.g. when compiling gmp).
    spack tags build-tools | xargs -I {} spack config --scope site rm packages:{}
    spack buildcache keys --install --trust
}



if [ "3" != "$(major_version)" ]; then
    echo "ParallelCluster version $(major_version) not supported."
    exit 1
fi


set_pcluster_defaults |& tee -a /var/log/spack-postinstall.log
setup_spack |& tee -a /var/log/spack-postinstall.log
