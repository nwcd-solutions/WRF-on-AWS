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

source /etc/environment
source /root/config.cfg

DCV_HOST_ALTNAME=$(hostname | cut -d. -f1)
AWS=$(which aws)
IMDS_TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_FAMILY=$(curl -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" --silent http://169.254.169.254/latest/meta-data/instance-type | cut -d. -f1)
echo "Detected Instance family $INSTANCE_FAMILY"
GPU_INSTANCE_FAMILY=(g3 g4 g4dn)



# Automatic start Gnome upon reboot
systemctl set-default graphical.target

# Install latest NVIDIA driver if GPU instance is detected
if [[ "${GPU_INSTANCE_FAMILY[@]}" =~ "${INSTANCE_FAMILY}" ]]; then
  # clean previously installed drivers
  echo "Detected GPU instance .. installing NVIDIA Drivers"
  rm -f /root/NVIDIA-Linux-x86_64*.run
  # Determine the S3 bucket AWS region for the drivers
  DRIVER_BUCKET_REGION=$(curl -s --head ec2-linux-nvidia-drivers.s3.amazonaws.com | grep bucket-region | awk '{print $2}' | tr -d '\r\n')
  $AWS --region ${DRIVER_BUCKET_REGION} s3 cp --quiet --recursive s3://ec2-linux-nvidia-drivers/latest/ .
  rm -rf /tmp/.X*
  /bin/sh /root/NVIDIA-Linux-x86_64*.run -q -a -n -X -s
  NVIDIAXCONFIG=$(which nvidia-xconfig)
  $NVIDIAXCONFIG --preserve-busid --enable-all-gpus
fi



# Enable GPU support
if [[ "${GPU_INSTANCE_FAMILY[@]}" =~ "${INSTANCE_FAMILY}" ]]; then
    echo "Detected GPU instance, adding support for nice-dcv-gl"
    rpm -ivh nice-dcv-gl*.rpm --nodeps
    #DCVGLADMIN=$(which dcvgladmin)
    #$DCVGLADMIN enable
fi

# Configure DCV
mv /etc/dcv/dcv.conf /etc/dcv/dcv.conf.orig
IDLE_TIMEOUT=1440 # in minutes. Disconnect DCV (but not terminate the session) after 1 day if not active
USER_HOME=$(eval echo ~$DCV_OWNER)
DCV_STORAGE_ROOT="$USER_HOME/storage-root" # Create the storage root location if needed
mkdir -p $DCV_STORAGE_ROOT
chown $DCV_OWNER $DCV_STORAGE_ROOT

echo -e """
[license]
[log]
[session-management]
virtual-session-xdcv-args=\"-listen tcp\"
[session-management/defaults]
[session-management/automatic-console-session]
storage-root=\"$DCV_STORAGE_ROOT\"
[display]
# add more if using an instance with more GPU
cuda-devices=[\"0\"]
[display/linux]
gl-displays = [\":1.0\"]
[display/linux]
use-glx-fallback-provider=false
[connectivity]
web-url-path=\"/$DCV_HOST_ALTNAME\"
idle-timeout=$IDLE_TIMEOUT
[security]
auth-token-verifier=\"$DCV_AUTHENTICATOR\"
no-tls-strict=true
os-auto-lock=false
""" > /etc/dcv/dcv.conf

# Disable DPMS
echo "Disabling X11 DPMS"
echo -e """
Section \"Extensions\"
    Option      \"DPMS\" \"Disable\"
EndSection""" > /etc/X11/xorg.conf.d/99-disable-dpms.conf

# Start DCV server
sudo systemctl enable dcvserver
sudo systemctl stop dcvserver
sleep 5
sudo systemctl start dcvserver

systemctl stop firewalld
systemctl disable firewalld

# Start X
systemctl isolate graphical.target

# Start Session
echo "Launching session ... : dcv create-session --user $DCV_OWNER --owner $DCV_OWNER --type virtual --storage-root "$DCV_STORAGE_ROOT" $DCV_SESSION_ID"
dcv create-session --user $DCV_OWNER --owner $DCV_OWNER --type virtual --storage-root "$DCV_STORAGE_ROOT" $DCV_SESSION_ID
echo $?
sleep 5
dbus-launch gsettings set org.gnome.desktop.session idle-delay 0 
# Final reboot is needed to update GPU drivers if running GPU instance. Reboot will be triggered by ComputeNodePostReboot.sh
if [[ "${GPU_INSTANCE_FAMILY[@]}" =~ "${INSTANCE_FAMILY}" ]]; then
  echo "@reboot dcv create-session --owner $DCV_OWNER --storage-root \"$DCV_STORAGE_ROOT\" $DCV_SESSION_ID # Do Not Delete"| crontab - -u $DCV_OWNER
  exit 3 # notify ComputeNodePostReboot.sh to force reboot
else
  echo "@reboot dcv create-session --owner $DCV_OWNER --storage-root \"$DCV_STORAGE_ROOT\" $DCV_SESSION_ID # Do Not Delete"| crontab - -u $DCV_OWNER
  exit 0
fi
