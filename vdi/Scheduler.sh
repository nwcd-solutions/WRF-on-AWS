#!/bin/bash -xe

source /etc/environment
source /root/config.cfg

SERVER_IP=$(hostname -I)
SERVER_HOSTNAME=$(hostname)
SERVER_HOSTNAME_ALT=$(echo $SERVER_HOSTNAME | cut -d. -f1)
echo $SERVER_IP $SERVER_HOSTNAME $SERVER_HOSTNAME_ALT >> /etc/hosts

if [[ $BASE_OS == "rhel7" ]]
then
    yum install -y $(echo ${SYSTEM_PKGS[*]} ${SCHEDULER_PKGS[*]}) --enablerepo rhui-REGION-rhel-server-optional
else
    yum install -y $(echo ${SYSTEM_PKGS[*]} ${SCHEDULER_PKGS[*]})
fi

yum install -y $(echo ${OPENLDAP_SERVER_PKGS[*]} ${SSSD_PKGS[*]})

# Mount EFS

mkdir /apps
mkdir -p /data/home
echo "/dev/nvme1n1 /apps ext4 defaults 0 0" >> /etc/fstab
mount -a
echo "/data *(rw,sync,no_subtree_check,no_root_squash,insecure)" >> /etc/exports
echo "/apps *(rw,sync,no_subtree_check,no_root_squash,insecure)" >> /etc/exports
exportfs -rv
systemctl start nfs
systemctl enable nfs

# Edit path with new scheduler/python locations
echo "export PATH=\"/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/opt/pbs/bin:/opt/pbs/sbin:/opt/pbs/bin:/apps/soca/$SOCA_CONFIGURATION/python/latest/bin\"" >> /etc/environment

# Disable SELINUX
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

# Disable StrictHostKeyChecking
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config


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

# Reboot to ensure SELINUX is disabled
# Note: Upon reboot, SchedulerPostReboot.sh script will be executed and will finalize scheduler configuration
reboot
