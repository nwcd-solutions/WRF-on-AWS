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

if [[ $# -lt 1 ]]; then
    exit 1
fi

# In case AMI already have PBS installed, force it to stop
service pbs stop || true

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

# Check if the yum updates above installed a new kernel version
REQUIRE_REBOOT=0
if [[ $(rpm -qa kernel | wc -l) -gt 1 ]]; then
    REQUIRE_REBOOT=1
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

sudo reboot

# Upon reboot, ComputeNodePostReboot will be executed
