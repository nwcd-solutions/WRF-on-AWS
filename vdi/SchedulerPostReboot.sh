#!/bin/bash -xe

source /etc/environment
source /root/config.cfg

# First flush the current crontab to prevent this script to run on the next reboot
crontab -r
DCV_USERNAME=$1
DCV_SESSION_ID="test"
mkdir -p /data/home

#useradd -d /data/home/$1 $1 -s /bin/csh
#echo "$2" | passwd $1 --stdin > /dev/null 2>&1
#chown -R $1:$1  /data/home/$1
#echo "$1 ALL=(ALL) ALL" >> /etc/sudoers
#su - $1 -c " ssh-keygen -f ~/.ssh/id_rsa -P '' && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys &&chmod go-w /data/home/$1"

# When using custom AMI, the scheduler is fully operational even before SecretManager is ready. LDAP_Manager has a dependency on SecretManager so we have to wait a little bit (or create the user manually once secretmanager is available)
MAX_ATTEMPT=5
CURRENT_ATTEMPT=0
# Create default LDAP user

until `/apps/python/latest/bin/python3 /root/ldap_manager.py add-user -u $1 -p $2 --admin >> /dev/null 2>&1`
do
  echo "Unable to add new LDAP user as command failed (secret manager not ready?) Waiting 3mn ..."
  if [[ $CURRENT_ATTEMPT -ge $MAX_ATTEMPT ]];
  then
    echo "Unable to create LDAP user after 5 attempts, try to run the command manually: /apps/python/latest/bin/python3 /root/ldap_manager.py add-user -u '$1' -p '$2' --admin"
    break
  fi
  sleep 180
  ((CURRENT_ATTEMPT=CURRENT_ATTEMPT+1))
done


# Copy  Aligo scripts file structure
AWS=$(which aws)

# Configure DCV
mv /etc/dcv/dcv.conf /etc/dcv/dcv.conf.orig
IDLE_TIMEOUT=1440 # in minutes. Disconnect DCV (but not terminate the session) after 1 day if not active
USER_HOME=/data/home/$DCV_USERNAME
DCV_STORAGE_ROOT="$USER_HOME/storage-root" 
# Create the storage root location if needed
mkdir -p $DCV_STORAGE_ROOT
chown $DCV_USERNAME:$DCV_USERNAME $DCV_STORAGE_ROOT

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
#web-url-path=\"/$DCV_HOST_ALTNAME\"
idle-timeout=$IDLE_TIMEOUT
[security]
#auth-token-verifier=\"$SOCA_DCV_AUTHENTICATOR\"
no-tls-strict=true
os-auto-lock=false
""" > /etc/dcv/dcv.conf

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
echo "Launching session ... : dcv create-session --user $DCV_USERNAME --owner $DCV_USERNAME --type virtual --storage-root "$DCV_STORAGE_ROOT" $DCV_SESSION_ID"
dcv create-session --user $DCV_USERNAME --owner $DCV_USERNAME --type virtual --storage-root "$DCV_STORAGE_ROOT" $DCV_USERNAME
echo $?
sleep 5

# Final reboot is needed to update GPU drivers if running GPU instance. Reboot will be triggered by ComputeNodePostReboot.sh
if [[ "${GPU_INSTANCE_FAMILY[@]}" =~ "${INSTANCE_FAMILY}" ]];
then
  echo "@reboot dcv create-session --owner $DCV_USERNAME --storage-root \"$DCV_STORAGE_ROOT\" $DCV_USERNAME # Do Not Delete"| crontab - -u $DCV_USERNAME
#  exit 3 # notify ComputeNodePostReboot.sh to force reboot
else
  echo "@reboot dcv create-session --owner $DCV_USERNAME --storage-root \"$DCV_STORAGE_ROOT\" $DCV_USERNAME # Do Not Delete"| crontab - -u $DCV_USERNAME
#  exit 0
fi
# download and config GeoEast
#$AWS s3 cp s3://$SOCA_INSTALL_BUCKET/$SOCA_INSTALL_BUCKET_FOLDER/software/v4.2/geoeast.tar.gz /apps/
#tar zxf /apps/geoeast.tar.gz -C /apps/
chown -R geoeast:geoeast /apps/GEOEAST
#$AWS s3 cp s3://$SOCA_INSTALL_BUCKET/$SOCA_INSTALL_BUCKET_FOLDER/software/v4.2/database.tar.gz /apps/
#tar zxf /apps/database.tar.gz -C /apps/
groupadd -g 699 dba
adduser -g dba -d /apps/database/postgre -s /bin/csh -u 6001 postgre
chown -R postgre:dba /apps/database

cd /apps/database/postgre/product/network
./rootctl.sh
su - postgre -c "
cp /apps/database/postgre/product/network/cshrc.pg /apps/database/postgre/.cshrc ;
source /apps/database/postgre/.cshrc ;
/apps/database/postgre/product/network/createdb.sh geodb"
cd /apps/GEOEAST/ieco1.6/install
./rootinstall.sh
