#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2023 by Amazon.com, Inc. or its affiliates.  All Rights Reserved.

USER_DATA_TYPE=${1:-basic}
HPC_OS=${2:-alinux2}
SARCH=${3:-aarch64}

check_os_version()
{
    eval  "$(cat /etc/os-release | grep "^NAME=\|VERSION_ID=")"
    VERSION_ID=$(echo ${VERSION_ID} | cut -f1 -d.)
    S_NAME="${NAME}"

    case ${NAME} in
        "Amazon Linux"|"Oracle Linux Server"|"Red Hat Enterprise Linux Server"|"CentOS Linux"|"Alibaba Cloud Linux"|"Alibaba Cloud Linux (Aliyun Linux)")
            HPC_PACKAGE_TYPE=rpm
            case ${VERSION_ID} in
                2|7)
                    S_VERSION_ID=7
                    ;;
                3|8|2022)
                    S_VERSION_ID=8
                    ;;
                *)
                    echo "Unsupported Linux system: ${NAME} ${VERSION_ID}"
                    exit 1
                    ;;
            esac
            ;;
        "Ubuntu"|"Debian GNU/Linux")
            HPC_PACKAGE_TYPE=deb
            case ${VERSION_ID} in
                10|18)
                    S_VERSION_ID=18
                    ;;
                11|20)
                    S_VERSION_ID=20
                    ;;
                *)
                    echo "Unsupported Linux system: ${NAME} ${VERSION_ID}"
                    exit 1
                    ;;
            esac
            ;;
        *)
            echo "Unsupported Linux system: ${NAME} ${VERSION_ID}"
            exit 1
            ;;
    esac
}

install_sys_dependency_for_headnode()
{
    case ${S_VERSION_ID} in
	7)
	    sudo yum -y update
	    case  "${S_NAME}" in
		"Alibaba Cloud Linux (Aliyun Linux)"|"Oracle Linux Server"|"Red Hat Enterprise Linux Server"|"CentOS Linux")
		    sudo yum -y install tmux htop pxz pmix-devel libfabric-devel rdma-core-devel libpsm2-devel infinipath-psm-devel libnl3 libnl3-devel
		    ;;
		"Amazon Linux")
		    cd ~/ 
		    echo "zzz *** $(date) *** installation"  >> user_data.log
		    sudo yum -y install tmux htop pxz pmix-devel libfabric-devel rdma-core-devel libpsm2-devel infinipath-psm-devel libnl3 libnl3-devel
		    echo "zzz *** $(date) *** downloading"  >> user_data.log
		    wget https://aws-hpc-builder.s3.amazonaws.com/project/apps/aws_pcluster_3.4_${HPC_OS}_${USER_DATA_TYPE}_${SARCH}.tar.xz
		    echo "zzz *** $(date) *** uncompress"  >> user_data.log
		    XZ_OPT="-T0 -vvv" tar xpf aws_pcluster_3.4_${HPC_OS}_${USER_DATA_TYPE}_${SARCH}.tar.xz -C /fsx
		    echo "zzz *** $(date) *** app deployment done"  >> user_data.log
		    ;;
	    esac
	    ;;
	8)
	    sudo $(dnf check-release-update 2>&1 | grep "dnf update --releasever" | tail -n1) -y 2> /dev/null
	    sudo dnf -y update
	    sudo dnf -y install tmux htop pxz pmix-devel libfabric-devel rdma-core-devel libpsm2-devel infinipath-psm-devel libnl3 libnl3-devel
	    case  "${S_NAME}" in
		"Alibaba Cloud Linux"|"Oracle Linux Server"|"Red Hat Enterprise Linux Server"|"CentOS Linux")
		    return
		    ;;
		"Amazon Linux")
		    return
		    ;;
	    esac
	    ;;
	18|20)
	    if [ ! -f /usr/bin/bash ]
	    then
		sudo ln -sfn /bin/bash /usr/bin
	    fi
	    sudo apt-get -y update
	    sudo apt-get -y install tmux htop pixz libncurses-dev libhwloc-dev libpmix-dev libpsm2-dev libnl-3-dev libpsm-infinipath1-dev libfabric-dev
	    ;;
	*)
	    exit 1
	    ;;
    esac
}

install_sys_dependency_for_computefleet()
{
    case ${S_VERSION_ID} in
	7)
	    case  "${S_NAME}" in
		"Alibaba Cloud Linux (Aliyun Linux)"|"Oracle Linux Server"|"Red Hat Enterprise Linux Server"|"CentOS Linux")
		    #echo "This is a compute node"
		    sudo yum -y install tmux htop pxz pmix-devel
		    ;;
		"Amazon Linux")
		    #echo "This is a compute node"
		    sudo yum -y install tmux htop pxz pmix-devel
		    ;;
	    esac
	    ;;
	8)
	    #echo "This is a compute node"
	    sudo dnf -y install tmux htop pmix-devel
	    case  "${S_NAME}" in
		"Alibaba Cloud Linux"|"Oracle Linux Server"|"Red Hat Enterprise Linux Server"|"CentOS Linux")
		    return
		    ;;
		"Amazon Linux")
		    return
		    ;;
	    esac
	    ;;
	18|20)
	    #echo "This is a compute node"
	    if [ ! -f /usr/bin/bash ]
	    then
		sudo ln -sfn /bin/bash /usr/bin
	    fi
	    sudo apt-get -y install tmux htop pixz libncurses-dev libhwloc-dev libpmix-dev
	    ;;
	*)
	    exit 1
	    ;;
    esac
}

. /etc/parallelcluster/cfnconfig

check_os_version

case "${cfn_node_type}" in
    HeadNode|MasterServer)
	install_sys_dependency_for_headnode
    ;;
    ComputeFleet)
	install_sys_dependency_for_computefleet
    ;;
    *)
    ;;
esac

echo "zzz *** $(date) *** user data done." >> user_data.log

