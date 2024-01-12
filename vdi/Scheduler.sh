#!/bin/bash -xe

source /etc/environment
source /root/config.cfg
FS_DATA_PROVIDER=$1
FS_DATA=$2
FS_APPS_PROVIDER=$3
FS_APPS=$4
SERVER_IP=$(hostname -I)
SERVER_HOSTNAME=$(hostname)
SERVER_HOSTNAME_ALT=$(echo $SERVER_HOSTNAME | cut -d. -f1)
echo $SERVER_IP $SERVER_HOSTNAME $SERVER_HOSTNAME_ALT >> /etc/hosts



# Mount EFS

mkdir /apps
mkdir /data

if [[ "$FS_DATA_PROVIDER" == "fsx_lustre" ]] || [[ "$FS_APPS_PROVIDER" == "fsx_lustre" ]]; then
    if [[ -z "$(rpm -qa lustre-client)" ]]; then
        # Install FSx for Lustre Client
        if [[ "$SOCA_BASE_OS" == "amazonlinux2" ]]; then
            amazon-linux-extras install -y lustre
        else
            kernel=$(uname -r)
            machine=$(uname -m)
            echo "Found kernel version: $kernel running on: $machine"
            if [[ $kernel == *"3.10.0-957"*$machine ]]; then
                yum -y install https://downloads.whamcloud.com/public/lustre/lustre-2.10.8/el7/client/RPMS/x86_64/kmod-lustre-client-2.10.8-1.el7.x86_64.rpm
                yum -y install https://downloads.whamcloud.com/public/lustre/lustre-2.10.8/el7/client/RPMS/x86_64/lustre-client-2.10.8-1.el7.x86_64.rpm
            elif [[ $kernel == *"3.10.0-1062"*$machine ]]; then
                wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -O /tmp/fsx-rpm-public-key.asc
                rpm --import /tmp/fsx-rpm-public-key.asc
                wget https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -O /etc/yum.repos.d/aws-fsx.repo
                sed -i 's#7#7.7#' /etc/yum.repos.d/aws-fsx.repo
                yum clean all
                yum install -y kmod-lustre-client lustre-client
            elif [[ $kernel == *"3.10.0-1127"*$machine ]]; then
                wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -O /tmp/fsx-rpm-public-key.asc
                rpm --import /tmp/fsx-rpm-public-key.asc
                wget https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -O /etc/yum.repos.d/aws-fsx.repo
                sed -i 's#7#7.8#' /etc/yum.repos.d/aws-fsx.repo
                yum clean all
                yum install -y kmod-lustre-client lustre-client
            elif [[ $kernel == *"3.10.0-1160"*$machine ]]; then
                wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -O /tmp/fsx-rpm-public-key.asc
                rpm --import /tmp/fsx-rpm-public-key.asc
                wget https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -O /etc/yum.repos.d/aws-fsx.repo
                yum clean all
                yum install -y kmod-lustre-client lustre-client
            elif [[ $kernel == *"4.18.0-193"*$machine ]]; then
                # FSX for Lustre on aarch64 is supported only on 4.18.0-193
                wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -O /tmp/fsx-rpm-public-key.asc
                rpm --import /tmp/fsx-rpm-public-key.asc
                wget https://fsx-lustre-client-repo.s3.amazonaws.com/centos/7/fsx-lustre-client.repo -O /etc/yum.repos.d/aws-fsx.repo
                yum clean all
                yum install -y kmod-lustre-client lustre-client
            else
                echo "ERROR: Can't install FSx for Lustre client as kernel version: $kernel isn't matching expected versions: (x86_64: 3.10.0-957, -1062, -1127, -1160, aarch64: 4.18.0-193)!"
            fi
        fi
    fi
fi

AWS=$(command -v aws)

if [[ "$FS_DATA_PROVIDER" == "efs" ]]; then
    echo "$FS_DATA:/ /data/ nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0" >> /etc/fstab
elif [[ "$FS_DATA_PROVIDER" == "fsx_lustre" ]]; then
    FSX_ID=$(echo $FS_DATA | cut -d. -f1)
    FSX_DATA_MOUNT_NAME=$($AWS fsx describe-file-systems --file-system-ids $FSX_ID  --query FileSystems[].LustreConfiguration.MountName --output text --region $REGION)
    echo "$FS_DATA@tcp:/$FSX_DATA_MOUNT_NAME /data lustre defaults,noatime,flock,_netdev 0 0" >> /etc/fstab
fi

if [[ "$FS_APPS_PROVIDER" == "ebs" ]]; then
    echo "/dev/nvme1n1 /apps ext4 defaults 0 0" >> /etc/fstab
    echo "/apps *(rw,sync,no_subtree_check,no_root_squash,insecure)" >> /etc/exports
    exportfs -rv
    systemctl start nfs
    systemctl enable nfs
elif [[ "$FS_APPS_PROVIDER" == "efs" ]]; then
    echo "$FS_APPS:/ /apps nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport 0 0" >> /etc/fstab
elif [[ "$FS_APPS_PROVIDER" == "fsx_lustre" ]]; then
    FSX_ID=$(echo $FS_APPS | cut -d. -f1)
    FSX_APPS_MOUNT_NAME=$($AWS fsx describe-file-systems --file-system-ids $FSX_ID  --query FileSystems[].LustreConfiguration.MountName --output text --region $REGION)
    echo "$FS_APPS@tcp:/$FSX_APPS_MOUNT_NAME /apps lustre defaults,noatime,flock,_netdev 0 0" >> /etc/fstab
fi



FS_MOUNT=0
mount -a
while [[ $? -ne 0 ]] && [[ $FS_MOUNT -le 5 ]]
do
    SLEEP_TIME=$(( RANDOM % 60 ))
    echo "Failed to mount FS, retrying in $SLEEP_TIME seconds and Loop $FS_MOUNT/5 ..."
    sleep $SLEEP_TIME
    ((FS_MOUNT++))
    mount -a
done


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
