#!/bin/bash -xe

source /etc/environment
source /root/config.cfg

yum install -y $(echo ${OPENLDAP_SERVER_PKGS[*]} ${SSSD_PKGS[*]})

FS_DATA_PROVIDER=$1
FS_DATA=$2
FS_APPS_PROVIDER=$3
FS_APPS=$4
SERVER_IP=$(hostname -I)
SERVER_HOSTNAME=$(hostname)
SERVER_HOSTNAME_ALT=$(echo $SERVER_HOSTNAME | cut -d. -f1)
echo $SERVER_IP $SERVER_HOSTNAME $SERVER_HOSTNAME_ALT >> /etc/hosts
LDAP_BASE="dc=soca,dc=local"


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

# Install Python if needed
PYTHON_INSTALLED_VERS=$(/apps/python/latest/bin/python3 --version | awk {'print $NF'})
if [[ "$PYTHON_INSTALLED_VERS" != "$PYTHON_VERSION" ]]
then
    echo "Python not detected, installing"
    mkdir -p /apps/python/installer
    cd /apps/python/installer
    wget $PYTHON_URL
    if [[ $(md5sum $PYTHON_TGZ | awk '{print $1}') != $PYTHON_HASH ]];  then
        echo -e "FATAL ERROR: Checksum for Python failed. File may be compromised." > /etc/motd
        exit 1
    fi
    tar xvf $PYTHON_TGZ
    cd Python-$PYTHON_VERSION
    ./configure LDFLAGS="-L/usr/lib64/openssl" CPPFLAGS="-I/usr/include/openssl" -enable-loadable-sqlite-extensions --prefix=/apps/python/$PYTHON_VERSION
    make
    make install
    ln -sf /apps/python/$PYTHON_VERSION /apps/python/latest
else
    echo "Python already installed and at correct version."
fi



# Configure Ldap
systemctl enable slapd
systemctl start slapd

MASTER_LDAP_PASSWORD=$(slappasswd -g)
MASTER_LDAP_PASSWORD_ENCRYPTED=$(/sbin/slappasswd -s $MASTER_LDAP_PASSWORD -h "{SSHA}")
echo -n "admin" > /root/OpenLdapAdminUsername.txt
echo -n $MASTER_LDAP_PASSWORD > /root/OpenLdapAdminPassword.txt
chmod 600 /root/OpenLdapAdminPassword.txt
echo "URI ldap://$SERVER_HOSTNAME" >> /etc/openldap/ldap.conf
echo "BASE $LDAP_BASE" >> /etc/openldap/ldap.conf

# Generate 10y certificate for ldaps
openssl req -new -newkey rsa:2048 -days 3650 -nodes -x509 \
    -subj "/C=US/ST=California/L=Sunnyvale/O=Aligo/CN=$SERVER_HOSTNAME" \
    -keyout /etc/openldap/certs/soca.key -out /etc/openldap/certs/soca.crt

chown ldap:ldap /etc/openldap/certs/soca.key /etc/openldap/certs/soca.crt
chmod 600 /etc/openldap/certs/soca.key /etc/openldap/certs/soca.crt

echo -e "
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: $LDAP_BASE

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,$LDAP_BASE

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $MASTER_LDAP_PASSWORD_ENCRYPTED
" > db.ldif

echo -e "
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/soca.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/soca.key
" > update_ssl_cert.ldif

echo -e "
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to attrs=userPassword by self write by anonymous auth by group.exact="ou=admins,$LDAP_BASE" write by * none
-
add: olcAccess
olcAccess: {1}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" write by dn.base="ou=admins,$LDAP_BASE" write by * read
" > change_user_password.ldif

echo -e "
dn: cn=sudo,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: sudo
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.1 NAME 'sudoUser' DESC 'User(s) who may  run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.2 NAME 'sudoHost' DESC 'Host(s) who may run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.3 NAME 'sudoCommand' DESC 'Command(s) to be executed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.4 NAME 'sudoRunAs' DESC 'User(s) impersonated by sudo (deprecated)' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.5 NAME 'sudoOption' DESC 'Options(s) followed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.6 NAME 'sudoRunAsUser' DESC 'User(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.7 NAME 'sudoRunAsGroup' DESC 'Group(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcObjectClasses: ( 1.3.6.1.4.1.15953.9.2.1 NAME 'sudoRole' SUP top STRUCTURAL DESC 'Sudoer Entries' MUST ( cn ) MAY ( sudoUser $ sudoHost $ sudoCommand $ sudoRunAs $ sudoRunAsUser $ sudoRunAsGroup $ sudoOption $ description ) )
" > sudoers.ldif

/bin/ldapmodify -Y EXTERNAL -H ldapi:/// -f db.ldif
/bin/ldapmodify -Y EXTERNAL -H ldapi:/// -f update_ssl_cert.ldif
/bin/ldapmodify -Y EXTERNAL -H ldapi:/// -f change_user_password.ldif
/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f sudoers.ldif
/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif
/bin/ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif

echo -e "
dn: $LDAP_BASE
dc: soca
objectClass: top
objectClass: domain

dn: cn=admin,$LDAP_BASE
objectClass: organizationalRole
cn: admin
description: LDAP Manager

dn: ou=People,$LDAP_BASE
objectClass: organizationalUnit
ou: People

dn: ou=Group,$LDAP_BASE
objectClass: organizationalUnit
ou: Group

dn: ou=Sudoers,$LDAP_BASE
objectClass: organizationalUnit

dn: ou=admins,$LDAP_BASE
objectClass: organizationalUnit
ou: Group
" > base.ldif

/bin/ldapadd -x -W -y /root/OpenLdapAdminPassword.txt -D "cn=admin,$LDAP_BASE" -f base.ldif

authconfig \
    --enablesssd \
    --enablesssdauth \
    --enableldap \
    --enableldapauth \
    --ldapserver="ldap://$SERVER_HOSTNAME" \
    --ldapbasedn="$LDAP_BASE" \
    --enablelocauthorize \
    --enablemkhomedir \
    --enablecachecreds \
    --updateall

echo "sudoers: files sss" >> /etc/nsswitch.conf

# Configure SSSD
echo -e "[domain/default]
enumerate = True
autofs_provider = ldap
cache_credentials = True
ldap_search_base = $LDAP_BASE
id_provider = ldap
auth_provider = ldap
chpass_provider = ldap
sudo_provider = ldap
ldap_tls_cacert = /etc/openldap/certs/soca.crt
ldap_sudo_search_base = ou=Sudoers,$LDAP_BASE
ldap_uri = ldap://$SERVER_HOSTNAME
ldap_id_use_start_tls = True
use_fully_qualified_names = False
ldap_tls_cacertdir = /etc/openldap/certs/

[sssd]
services = nss, pam, autofs, sudo
full_name_format = %2\$s\%1\$s
domains = default

[nss]
homedir_substring = /data/home

[pam]

[sudo]
ldap_sudo_full_refresh_interval=86400
ldap_sudo_smart_refresh_interval=3600

[autofs]

[ssh]

[pac]

[ifp]

[secrets]" > /etc/sssd/sssd.conf
chmod 600 /etc/sssd/sssd.conf

systemctl enable sssd
systemctl restart sssd


# Disable SELINUX
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

# Disable StrictHostKeyChecking
echo "StrictHostKeyChecking no" >> /etc/ssh/ssh_config
echo "UserKnownHostsFile /dev/null" >> /etc/ssh/ssh_config

# Install Python required libraries
# Source environment to reload path for Python3
/apps/python/$PYTHON_VERSION/bin/pip3 install -r /root/requirements.txt

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
