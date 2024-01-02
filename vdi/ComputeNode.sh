#!/bin/bash -xe
######################################################################################################################
#  Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.                                                #
#                                                                                                                    #
#  Licensed under the Apache License, Version 2.0 (the "License"). You may not use this file except in compliance    #
#  with the License. A copy of the License is located at                                                             #
#                                                                                                                    #
#      http://www.apache.org/licenses/LICENSE-2.0                                                                    #
#                                                                                                                    #
#  or in the 'license' file accompanying this file. This file is distributed on an 'AS IS' BASIS, WITHOUT WARRANTIES #
#  OR CONDITIONS OF ANY KIND, express or implied. See the License for the specific language governing permissions    #
#  and limitations under the License.                                                                                #
######################################################################################################################

set -x

source /etc/environment

source /root/config.cfg

date

# Install SSM
machine=$(uname -m)
if ! systemctl status amazon-ssm-agent; then
    if [[ $machine == "x86_64" ]]; then
        yum install -y $SSM_X86_64_URL
    elif [[ $machine == "aarch64" ]]; then
        yum install -y $SSM_AARCH64_URL
    fi
    systemctl enable amazon-ssm-agent || true
    systemctl restart amazon-ssm-agent
fi

AWS=$(command -v aws)


# Check if we're using a customized AMI
if [[ ! -f /root/soca_preinstalled_packages.log ]]; then
    # Install System required libraries / EPEL
    if [[ $SOCA_BASE_OS == "rhel7" ]]; then
      curl "$EPEL_URL" -o $EPEL_RPM
      yum -y install $EPEL_RPM
      yum install -y $(echo ${SYSTEM_PKGS[*]} ${SCHEDULER_PKGS[*]}) --enablerepo rhel-7-server-rhui-optional-rpms
    elif [[ $SOCA_BASE_OS == "centos7" ]]; then
      yum -y install epel-release
      yum install -y $(echo ${SYSTEM_PKGS[*]} ${SCHEDULER_PKGS[*]})
    else
      # AL2
      sudo amazon-linux-extras install -y epel
      yum install -y $(echo ${SYSTEM_PKGS[*]} ${SCHEDULER_PKGS[*]})
    fi
    yum install -y $(echo ${OPENLDAP_SERVER_PKGS[*]} ${SSSD_PKGS[*]})
fi
date
# Check if the yum updates above installed a new kernel version
REQUIRE_REBOOT=0
if [[ $(rpm -qa kernel | wc -l) -gt 1 ]]; then
    REQUIRE_REBOOT=1
fi

# Configure Scratch Directory if specified by the user
mkdir /scratch/
if [[ $SOCA_SCRATCH_SIZE -ne 0 ]]; then
    LIST_ALL_DISKS=$(lsblk --list | grep disk | awk '{print $1}')
    for disk in $LIST_ALL_DISKS;
    do
        CHECK_IF_PARTITION_EXIST=$(lsblk -b /dev/$disk | grep part | wc -l)
        CHECK_PARTITION_SIZE=$(lsblk -lnb /dev/$disk -o SIZE)
        let SOCA_SCRATCH_SIZE_IN_BYTES=$SOCA_SCRATCH_SIZE*1024*1024*1024
        if [[ $CHECK_IF_PARTITION_EXIST -eq 0 ]] && [[ $CHECK_PARTITION_SIZE -eq $SOCA_SCRATCH_SIZE_IN_BYTES ]]; then
            echo "Detected /dev/$disk with no partition as scratch device"
            mkfs -t ext4 /dev/$disk
            echo "/dev/$disk /scratch ext4 defaults 0 0" >> /etc/fstab
        fi
    done
else
    # Use Instance Store if possible.
    # When instance has more than 1 instance store, raid + mount them as /scratch
    VOLUME_LIST=()
    if [[ ! -z $(ls /dev/nvme[0-9]n1) ]]; then
        echo 'Detected Instance Store: NVME'
        DEVICES=$(ls /dev/nvme[0-9]n1)

    elif [[ ! -z $(ls /dev/xvdc[a-z]) ]]; then
        echo 'Detected Instance Store: SSD'
        DEVICES=$(ls /dev/xvdc[a-z])
    else
        echo 'No instance store detected on this machine.'
    fi

    if [[ ! -z $DEVICES ]]; then
        echo "Detected Instance Store with NVME:" $DEVICES
        # Clear Devices which are already mounted (eg: when customer import their own AMI)
        for device in $DEVICES;
        do
            CHECK_IF_PARTITION_EXIST=$(lsblk -b $device | grep part | wc -l)
            if [[ $CHECK_IF_PARTITION_EXIST -eq 0 ]]; then
                echo "$device is free and can be used"
                VOLUME_LIST+=($device)
            fi
        done

        VOLUME_COUNT=${#VOLUME_LIST[@]}
        if [[ $VOLUME_COUNT -eq 1 ]]; then
            # If only 1 instance store, mfks as ext4
            echo "Detected  1 NVMe device available, formatting as ext4 .."
            mkfs -t ext4 $VOLUME_LIST
            echo "$VOLUME_LIST /scratch ext4 defaults,nofail 0 0" >> /etc/fstab
        elif [[ $VOLUME_COUNT -gt 1 ]]; then
            # if more than 1 instance store disks, raid them !
            echo "Detected more than 1 NVMe device available, creating XFS fs ..."
            DEVICE_NAME="md0"
          for dev in ${VOLUME_LIST[@]} ; do dd if=/dev/zero of=$dev bs=1M count=1 ; done
          echo yes | mdadm --create -f --verbose --level=0 --raid-devices=$VOLUME_COUNT /dev/$DEVICE_NAME ${VOLUME_LIST[@]}
          mkfs -t ext4 /dev/$DEVICE_NAME
          mdadm --detail --scan | tee -a /etc/mdadm.conf
          echo "/dev/$DEVICE_NAME /scratch ext4 defaults,nofail 0 0" >> /etc/fstab
        else
            echo "All volumes detected already have a partition or mount point and can't be used as scratch devices"
        fi
    fi
fi


# Disable SELINUX & firewalld
if [[ -z $(grep SELINUX=disabled /etc/selinux/config) ]]; then
    sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
    REQUIRE_REBOOT=1
fi
systemctl stop firewalld
systemctl disable firewalld

# Disable StrictHostKeyChecking
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config

IMDS_TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_FAMILY=$(curl -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" --silent http://169.254.169.254/latest/meta-data/instance-type | cut -d. -f1)

# If GPU instance, disable NOUVEAU drivers before installing DCV as this require a reboot
# Rest of the DCV configuration is managed by ComputeNodeInstallDCV.sh
GPU_INSTANCE_FAMILY=(p2 p3 g2 g3 g4 g4dn)
if [[ "${GPU_INSTANCE_FAMILY[@]}" =~ "${INSTANCE_FAMILY}" ]]; then
    echo "Detected GPU instance .. disable NOUVEAU driver"
    cat << EOF | sudo tee --append /etc/modprobe.d/blacklist.conf
blacklist vga16fb
blacklist nouveau
blacklist rivafb
blacklist nvidiafb
blacklist rivatv
EOF
    echo GRUB_CMDLINE_LINUX="rdblacklist=nouveau" >> /etc/default/grub
    sudo grub2-mkconfig -o /boot/grub2/grub.cfg
fi

# Configure Chrony
yum remove -y ntp
mv /etc/chrony.conf  /etc/chrony.conf.original
echo -e """
# use the local instance NTP service, if available
server 169.254.169.123 prefer iburst minpoll 4 maxpoll 4

# Use public servers from the pool.ntp.org project.
# Please consider joining the pool (http://www.pool.ntp.org/join.html).
# !!! [BEGIN] SOCA REQUIREMENT
# You will need to open UDP egress traffic on your security group if you want to enable public pool
#pool 2.amazon.pool.ntp.org iburst
# !!! [END] SOCA REQUIREMENT
# Record the rate at which the system clock gains/losses time.
driftfile /var/lib/chrony/drift

# Allow the system clock to be stepped in the first three updates
# if its offset is larger than 1 second.
makestep 1.0 3

# Specify file containing keys for NTP authentication.
keyfile /etc/chrony.keys

# Specify directory for log files.
logdir /var/log/chrony

# save data between restarts for fast re-load
dumponexit
dumpdir /var/run/chrony
""" > /etc/chrony.conf
systemctl enable chronyd

# Disable ulimit
echo -e  "
* hard memlock unlimited
* soft memlock unlimited
" >> /etc/security/limits.conf
date
sudo reboot

# Upon reboot, ComputeNodePostReboot will be executed
