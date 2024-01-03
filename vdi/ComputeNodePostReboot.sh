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
export PATH=$PATH:/usr/local/bin
AWS=$(which aws)
REQUIRE_REBOOT=0
echo "SOCA > BEGIN PostReboot setup"
date
echo "Installing DCV"
/bin/bash /root/ComputeNodeInstallDCV.sh >> $SOCA_HOST_SYSTEM_LOG/ComputeNodeInstallDCV.log 2>&1
if [[ $? -eq 3 ]];
 then
   REQUIRE_REBOOT=1
fi
sleep 30


# magic command to disable lock screen
dbus-launch gsettings set org.gnome.desktop.session idle-delay 0 > /dev/null

# Validate user identities
if [[ "$SOCA_AUTH_PROVIDER" == "activedirectory" ]]; then
    # Retrieve account with join permission if available, otherwise query SecretManager
    if [[ -f /apps/soca/$SOCA_CONFIGURATION/cluster_node_bootstrap/ad_automation/join_domain_user.cache ]]; then
        DS_DOMAIN_ADMIN_USERNAME=$(cat /apps/soca/$SOCA_CONFIGURATION/cluster_node_bootstrap/ad_automation/join_domain_user.cache)
    else
        DS_DOMAIN_ADMIN_USERNAME=$($AWS secretsmanager get-secret-value --secret-id $SOCA_CONFIGURATION --query SecretString --output text | grep -oP '"DSDomainAdminUsername": \"(.*?)\"' | sed 's/"DSDomainAdminUsername": //g' | tr -d '"')
        echo -n $DS_DOMAIN_ADMIN_USERNAME > /apps/soca/$SOCA_CONFIGURATION/cluster_node_bootstrap/ad_automation/join_domain_user.cache
    fi
    MAX_ATTEMPT=5
    CURRENT_ATTEMPT=0
    ID=$(command -v id)
    $ID $DS_DOMAIN_ADMIN_USERNAME > /dev/null 2>&1
    while [[ $? -ne 0 ]] && [[ $CURRENT_ATTEMPT -le $MAX_ATTEMPT ]]
    do
        SLEEP_TIME=$(( RANDOM % 30 ))
        echo "User identity not resolving successfully. Retrying in $SLEEP_TIME seconds... Loop count is: $CURRENT_ATTEMPT/$MAX_ATTEMPT"
        systemctl restart sssd
        ((CURRENT_ATTEMPT=CURRENT_ATTEMPT+1))
        $ID $DS_DOMAIN_ADMIN_USERNAME > /dev/null 2>&1
    done
fi
# End validate user identities

# Configure FSx if specified by the user.
# Right before the reboot to minimize the time to wait for FSx to be AVAILABLE
if [[ "$SOCA_FSX_LUSTRE_BUCKET" != 'false' ]] || [[ "$SOCA_FSX_LUSTRE_DNS" != 'false' ]] ; then
    echo "FSx request detected, installing FSX Lustre client ... "
    FSX_MOUNTPOINT="/fsx"
    mkdir -p $FSX_MOUNTPOINT

    if [[ "$SOCA_FSX_LUSTRE_DNS" == 'false' ]]; then
        # Retrieve FSX DNS assigned to this job
        FSX_ARN=$($AWS resourcegroupstaggingapi get-resources --tag-filters  "Key=soca:FSx,Values=true" "Key=soca:StackId,Values=$AWS_STACK_ID" --query ResourceTagMappingList[].ResourceARN --output text)
        echo "GET_FSX_ARN: " $FSX_ARN
        FSX_ID=$(echo $FSX_ARN | cut -d/ -f2)
        echo "GET_FSX_ID: " $FSX_ID
        echo "export SOCA_FSX_LUSTRE_ID="$FSX_ID" >> /etc/environment"
        ## UPDATE FSX_DNS VALUE MANUALLY IF YOU ARE USING A PERMANENT FSX
        FSX_DNS=$FSX_ID".fsx."$AWS_DEFAULT_REGION".amazonaws.com"

        # Verify if DNS is ready
        CHECK_FSX_STATUS=$($AWS fsx describe-file-systems --file-system-ids $FSX_ID  --query FileSystems[].Lifecycle --output text)
        # Note: We can retrieve FSxL Mount Name even if FSx is not fully ready
        GET_FSX_MOUNT_NAME=$($AWS fsx describe-file-systems --file-system-ids $FSX_ID  --query FileSystems[].LustreConfiguration.MountName --output text)
        LOOP_COUNT=1
        echo "FSX_DNS: " $FSX_DNS
        while [[ "$CHECK_FSX_STATUS" != "AVAILABLE" ]] && [[ $LOOP_COUNT -lt 10 ]]
            do
                echo "FSX does not seem to be in AVAILABLE status yet ... waiting 60 secs"
                sleep 60
                CHECK_FSX_STATUS=$($AWS fsx describe-file-systems --file-system-ids $FSX_ID  --query FileSystems[].Lifecycle --output text)
                echo $CHECK_FSX_STATUS
                ((LOOP_COUNT++))
        done

        if [[ "$CHECK_FSX_STATUS" == "AVAILABLE" ]]; then
            echo "FSx is AVAILABLE"
            echo "$FSX_DNS@tcp:/$GET_FSX_MOUNT_NAME $FSX_MOUNTPOINT lustre defaults,noatime,flock,_netdev 0 0" >> /etc/fstab
        else
            echo "FSx is not available even after 10 minutes timeout, ignoring FSx mount ..."
        fi
    else
        # Using persistent FSX provided by customer
        echo "Detected existing FSx provided by customers " $SOCA_FSX_LUSTRE_DNS
        FSX_ID=$(echo $SOCA_FSX_LUSTRE_DNS | cut -d. -f1)
        GET_FSX_MOUNT_NAME=$($AWS fsx describe-file-systems --file-system-ids $FSX_ID  --query FileSystems[].LustreConfiguration.MountName --output text)
        echo "$SOCA_FSX_LUSTRE_DNS@tcp:/$GET_FSX_MOUNT_NAME $FSX_MOUNTPOINT lustre defaults,noatime,flock,_netdev 0 0" >> /etc/fstab
    fi
    
    # Check if Lustre Client is already installed
    if [[ -z "$(rpm -qa lustre-client)" ]]; then
        # Install FSx for Lustre Client
        if [[ "$SOCA_BASE_OS" == "amazonlinux2" ]]; then
            sudo amazon-linux-extras install -y lustre
        else
            kernel=$(uname -r)
            machine=$(uname -m)
            echo "Found kernel version: ${kernel} running on: ${machine}"
            if [[ $kernel == *"3.10.0-957"*$machine ]]; then
                yum -y install https://downloads.whamcloud.com/public/lustre/lustre-2.10.8/el7/client/RPMS/x86_64/kmod-lustre-client-2.10.8-1.el7.x86_64.rpm
                yum -y install https://downloads.whamcloud.com/public/lustre/lustre-2.10.8/el7/client/RPMS/x86_64/lustre-client-2.10.8-1.el7.x86_64.rpm
                REQUIRE_REBOOT=1
            elif [[ $kernel == *"3.10.0-1062"*$machine ]]; then
                wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -O /tmp/fsx-rpm-public-key.asc
                rpm --import /tmp/fsx-rpm-public-key.asc
                wget https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -O /etc/yum.repos.d/aws-fsx.repo
                sed -i 's#7#7.7#' /etc/yum.repos.d/aws-fsx.repo
                yum clean all
                yum install -y kmod-lustre-client lustre-client
                REQUIRE_REBOOT=1
            elif [[ $kernel == *"3.10.0-1127"*$machine ]]; then
                wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -O /tmp/fsx-rpm-public-key.asc
                rpm --import /tmp/fsx-rpm-public-key.asc
                wget https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -O /etc/yum.repos.d/aws-fsx.repo
                sed -i 's#7#7.8#' /etc/yum.repos.d/aws-fsx.repo
                yum clean all
                yum install -y kmod-lustre-client lustre-client
                REQUIRE_REBOOT=1
            elif [[ $kernel == *"3.10.0-1160"*$machine ]]; then
                wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -O /tmp/fsx-rpm-public-key.asc
                rpm --import /tmp/fsx-rpm-public-key.asc
                wget https://fsx-lustre-client-repo.s3.amazonaws.com/el/7/fsx-lustre-client.repo -O /etc/yum.repos.d/aws-fsx.repo
                yum clean all
                yum install -y kmod-lustre-client lustre-client
                REQUIRE_REBOOT=1
            elif [[ $kernel == *"4.18.0-193"*$machine ]]; then
                # FSX for Lustre on aarch64 is supported only on 4.18.0-193
                wget https://fsx-lustre-client-repo-public-keys.s3.amazonaws.com/fsx-rpm-public-key.asc -O /tmp/fsx-rpm-public-key.asc
                rpm --import /tmp/fsx-rpm-public-key.asc
                wget https://fsx-lustre-client-repo.s3.amazonaws.com/centos/7/fsx-lustre-client.repo -O /etc/yum.repos.d/aws-fsx.repo
                yum clean all
                yum install -y kmod-lustre-client lustre-client
                REQUIRE_REBOOT=1
            else
                echo "ERROR: Can't install FSx for Lustre client as kernel version: ${kernel} isn't matching expected versions: (x86_64: 3.10.0-957, -1062, -1127, -1160, aarch64: 4.18.0-193)!"
            fi
        fi
    fi
fi



echo "Require Reboot: $REQUIRE_REBOOT"
if [[ $REQUIRE_REBOOT -eq 1 ]];
then
    echo "systemctl stop pbs
source /etc/environment
DCVGLADMIN=\$(which dcvgladmin)
\$DCVGLADMIN enable >> /root/enable_dcvgladmin.log 2>&1
# Disable HyperThreading
if [[ \"\$SOCA_INSTANCE_HYPERTHREADING\" == \"false\" ]]; then
    echo \"Disabling Hyperthreading\" >> \$SOCA_HOST_SYSTEM_LOG/ComputeNodePostReboot.log
    for cpunum in \$(awk -F'[,-]' '{print \$2}' /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | sort -un);
    do 
        echo 0 > /sys/devices/system/cpu/cpu\$cpunum/online;
    done
fi
# Make Scratch FS accessible by everyone. ACL still applies at folder level
if [[ -n \"\$FSX_MOUNTPOINT\" ]]; then
  chmod 777 \$FSX_MOUNTPOINT
fi

chmod 777 /scratch
while [ ! -d \$SOCA_HOST_SYSTEM_LOG ]
do
    sleep 1
done
/bin/bash /root/ComputeNodeUserCustomization.sh >> \$SOCA_HOST_SYSTEM_LOG/ComputeNodeUserCustomization.log 2>&1
systemctl start pbs" >> /etc/rc.local
    chmod +x /etc/rc.d/rc.local
    systemctl enable rc-local
    reboot
    # End USER Customization
else
    # Mount
    mount -a

    # Make Scratch (and /fsx if applicable) R/W by everyone. ACL still applies at folder level
    echo "chmod /scratch"
    chmod 777 /scratch

    if [[ -n "$FSX_MOUNTPOINT" ]]; then
        echo "chmod FSX"
        chmod 777 $FSX_MOUNTPOINT
    fi

    # Disable HyperThreading
    if [[ $SOCA_INSTANCE_HYPERTHREADING == "false" ]]; then
        echo "Disabling Hyperthreading"  >> $SOCA_HOST_SYSTEM_LOG/ComputeNodePostReboot.log
        for cpunum in $(awk -F'[,-]' '{print $2}' /sys/devices/system/cpu/cpu*/topology/thread_siblings_list | sort -un);
        do
            echo 0 > /sys/devices/system/cpu/cpu$cpunum/online;
        done
    fi
    date
    # Begin USER Customization
    /bin/bash /root/ComputeNodeUserCustomization.sh >> $SOCA_HOST_SYSTEM_LOG/ComputeNodeUserCustomization.log 2>&1
    # End USER Customization

fi
