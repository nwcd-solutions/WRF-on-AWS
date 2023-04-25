#!/bin/bash -l
. /etc/parallelcluster/cfnconfig
set -eux
#shared_folder=$(echo $cfn_ebs_shared_dirs | cut -d ',' -f 1 )
shared_folder=/fsx

region=$1
sns=$2
ftime=$3
jwt=$4


# Set ulimits according to WRF needs
cat >>/tmp/limits.conf << EOF
# core file size (blocks, -c) 0
*           hard    core           0
*           soft    core           0
# data seg size (kbytes, -d) unlimited
*           hard    data           unlimited
*           soft    data           unlimited
# scheduling priority (-e) 0
*           hard    priority       0
*           soft    priority       0
# file size (blocks, -f) unlimited
*           hard    fsize          unlimited
*           soft    fsize          unlimited
# pending signals (-i) 256273
*           hard    sigpending     1015390
*           soft    sigpending     1015390
# max locked memory (kbytes, -l) unlimited
*           hard    memlock        unlimited
*           soft    memlock        unlimited
# open files (-n) 1024
*           hard    nofile         65536
*           soft    nofile         65536
# POSIX message queues (bytes, -q) 819200
*           hard    msgqueue       819200
*           soft    msgqueue       819200
# real-time priority (-r) 0
*           hard    rtprio         0
*           soft    rtprio         0
# stack size (kbytes, -s) unlimited
*           hard    stack          unlimited
*           soft    stack          unlimited
# cpu time (seconds, -t) unlimited
*           hard    cpu            unlimited
*           soft    cpu            unlimited
# max user processes (-u) 1024
*           soft    nproc          16384
*           hard    nproc          16384
# file locks (-x) unlimited
*           hard    locks          unlimited
*           soft    locks          unlimited
EOF

sudo bash -c 'cat /tmp/limits.conf > /etc/security/limits.conf'

function systemd_units {

  cat > /etc/systemd/system/slurmdbd.service <<- EOF
	[Unit]
	Description=SlurmDBD daemon
	After=munge.service network.target
	ConditionPathExists=/opt/slurm/etc/slurmdbd.conf
	[Service]
	Type=simple
	Restart=always
	RestartSec=1
	User=root
	ExecStart=/opt/slurm/sbin/slurmdbd -D -s
	ExecReload=/bin/kill -HUP \$MAINPID
	LimitNOFILE=65536
	[Install]
	WantedBy=multi-user.target
EOF

  cat > /etc/systemd/system/slurmrestd.service <<- EOF
	[Unit]
	Description=Slurm REST daemon
	After=network.target munge.service slurmctld.service
	ConditionPathExists=/opt/slurm/etc/slurm.conf
	Documentation=man:slurmrestd(8)
	[Service]
	Type=simple
	User=slumrestd
	Group=slumrestd
	Environment="SLURM_JWT=daemon"
	ExecStart=/opt/slurm/sbin/slurmrestd -a rest_auth/jwt 0.0.0.0:8080
	ExecReload=/bin/kill -HUP \$MAINPID
	[Install]
	WantedBy=multi-user.target
EOF

  groupadd -r slumrestd
  useradd -r -c 'SLURM REST API user' -g slumrestd slumrestd
  systemctl enable slurmdbd.service
  systemctl enable slurmrestd.service
}

function slurm_db {
  local region=$1
  yum install -y mysql
  aws secretsmanager get-secret-value \
    --secret-id SlurmDbCreds \
    --query 'SecretString' \
    --region $region \
    --output text > /tmp/dbcreds
  export DBHOST=$(jq -r '.host' /tmp/dbcreds)
  export DBPASSWD=$(jq -r '.password' /tmp/dbcreds)
  rm /tmp/dbcreds

  cat > /opt/slurm/etc/slurmdbd.conf <<- EOF
	ArchiveEvents=yes
	ArchiveJobs=yes
	ArchiveResvs=yes
	ArchiveSteps=no
	ArchiveSuspend=no
	ArchiveTXN=no
	ArchiveUsage=no
	AuthType=auth/munge
	AuthAltTypes=auth/jwt
	AuthAltParameters=jwt_key=/opt/slurm/etc/jwt_hs256.key
	DbdHost=$(hostname)
	DbdPort=6819
	DebugLevel=info
	PurgeEventAfter=1month
	PurgeJobAfter=12month
	PurgeResvAfter=1month
	PurgeStepAfter=1month
	PurgeSuspendAfter=1month
	PurgeTXNAfter=12month
	PurgeUsageAfter=24month
	SlurmUser=slurm
	LogFile=/var/log/slurmdbd.log
	PidFile=/var/run/slurmdbd.pid
	StorageType=accounting_storage/mysql
	StorageUser=admin
	StoragePass=${DBPASSWD}
	StorageHost=${DBHOST}
	StoragePort=3306
EOF

  chmod 600 /opt/slurm/etc/slurmdbd.conf
  chown slurm:slurm /opt/slurm/etc/slurmdbd.conf

  dd if=/dev/urandom of=/opt/slurm/etc/jwt_hs256.key bs=32 count=1
  chmod 600 /opt/slurm/etc/jwt_hs256.key
  chown slurm:slurm /opt/slurm/etc/jwt_hs256.key

  cat >> /opt/slurm/etc/slurm.conf <<- EOF
	AuthAltTypes=auth/jwt
	AuthAltParameters=jwt_key=/opt/slurm/etc/jwt_hs256.key
	# ACCOUNTING
	JobAcctGatherType=jobacct_gather/linux
	JobAcctGatherFrequency=30
	#
	AccountingStorageType=accounting_storage/slurmdbd
	AccountingStorageHost=$(hostname)
	AccountingStorageUser=admin
	AccountingStoragePort=6819
EOF

  systemctl start slurmdbd.service
  systemctl start slurmrestd.service
}

function fini {
  local region=$1
  local sns=$2
  local ftime=$3
  local jwt=$4
  local y=${ftime:0:4}
  local m=${ftime:5:2}
  local d=${ftime:8:2}
  local h=${ftime:11:2}

  cat > /tmp/jwt.sh <<-EOF
	#!/bin/bash
	. /etc/profile.d/slurm.sh
	cd /fsx/run
	echo $ftime > /fsx/run/ftime
	/fsx/run/get_gfs
	sudo systemctl restart slurmctld.service
	sleep 15
	aws secretsmanager update-secret \
	  --region ${region} \
	  --secret-id "$jwt" \
	  --secret-string \$(/opt/slurm/bin/scontrol token lifespan=7200 | cut -f 2 -d = )
	export ip=$(curl -q -s http://169.254.169.254/latest/meta-data/local-ipv4)
	aws sns publish \
	  --region ${region} \
	  --subject "Parallel Cluster Post Install - SUCCESS" \
	  --message "\$ip" \
	  --topic-arn $sns
EOF
  chmod 755 /tmp/jwt.sh
  chown ec2-user:ec2-user /tmp/jwt.sh
  cat > /etc/systemd/system/jwt.service <<- EOF
	[Unit]
	Description=JWT generation
	After=slurmctld.service
	[Service]
	Type=simple
	User=ec2-user
	Group=ec2-user
	ExecStart=/tmp/jwt.sh
	WorkingDirectory=/tmp
	[Install]
	WantedBy=multi-user.target
EOF
  systemctl enable jwt.service
  systemctl start jwt.service
}

function download_wrf_install_package {
echo "Download wrf pre-compiled installation package"

chmod 777 ${shared_folder}
cd ${shared_folder}
wget https://aws-hpc-builder.s3.amazonaws.com/project/apps/aws_pcluster_3.4_alinux2_wrf_amd64.tar.xz
tar xpf aws_pcluster_3.4_alinux2_wrf_amd64.tar.xz
chown -R ec2-user:ec2-user ${shared_folder}
}

echo "NODE TYPE: ${cfn_node_type}"

case ${cfn_node_type} in
        HeadNode)
                echo "I am the HeadNode node"
                download_wrf_install_package
                cd ${shared_folder}
                #wget https://raw.githubusercontent.com/
                #bash pcluster_install_spack.sh
                systemd_units
                slurm_db $region
                fini $region $sns $ftime $jwt
                
        ;;
        ComputeFleet)
                echo "I am a Compute node"
        ;;
        esac
        
exit 0
