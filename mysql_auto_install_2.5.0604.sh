#!/bin/bash

# 2025-06-04	Robert Lin	v2.5.0604   # initial version
# 2025-09-10	Stanley Chen	v2.5.0910   # update the script to support installation across multiple hosts.and support innoDB cluster
######################################################################################################
# DON'T change following variable default value
######################################################################################################
MYSQL_HOME[84]="/opt/mysql84"	# Default MySQL binary home
SOFT_LOC[84]="/opt/software/mysql_installer/software/V1047836-01_MySQL_EE_8.4.4_TAR_glibc_2.28.zip"	# 8.4 default zip file location
UNZIPDIR[84]="mysql-commercial-8.4.4-linux-glibc2.28-x86_64"	# 8.4 tar file extracted default name
#DATA_LOC[84]="/mysqldata/${INST_NAME}"	# Default Instance location
UNZIPSPACE[84]=950              # Unit MB, free space requirement for 8.4 UNZIP location
MHOMESPACE[84]=1750             # Unit MB, free space requirement for 8.4 MYSQL_HOME location
TIME_ZONE="America/La_Paz"      # Default timezone
MYSQL_PW="mysql_123"                   # OS mysql user password
DELSW="y"                                # delete zip directory
CHGTZ="y"   				#Auto change timezone
######################################################################################################

SWVER=84
OSIP=$(dev=`ip r|awk '/default via/{print $5}'`;ip a|grep "inet "|awk '/'$dev'/&&!/secondary/&&!/127.0.0.1/{print substr($2,1,match($2,"/")-1)}')
OSVER=`awk '{print $NF}' /etc/oracle-release`
#INST_NAME=MYINST${OSIP##*.}
if [ "$#" -gt 1 ]; then
   echo -e "\nUsage: $0 [INSTANCE_NAME]\n"
   exit 1
fi

DEFAULT_INST_NAME="MYINST${OSIP##*.}"
INST_NAME="${1:-${INST_NAME:-${DEFAULT_INST_NAME}}}"
DATA_LOC[84]="/mysqldata/${INST_NAME}"	# Default Instance location

[ -f "/usr/bin/timedatectl" ] \
   && CURTZ=`timedatectl|awk '/Time zone:/{print $3}'` \
   || CURTZ=`awk -F= 'gsub("\"","",$2){print $2}' /etc/sysconfig/clock`

pushd "`dirname $0`" >/dev/null
LOGFILE[$SWVER]="${PWD}/log/MySQL${SWVER}_OEL${OSVER}_install_`date '+%Y-%m-%d_%H-%M-%S%p'_$$`.log"
LCKFILE="/root/.MYSQL_AUTO_INSTALL_LCKFILE"
trap "CleanUp" EXIT


PreCheck() {
   [ "${USER}" != "root" ] && { echo -e "\n[Error] - [$(hostname)]Please run script as user ROOT.\n"; exit 1; }
   [ -f "/etc/oracle-release" ] || { echo -e "\n[Error] - [$(hostname)]This script only support Oracle Linux Server OS.\n"; exit 1; }
   pgrep -x mysqld >/dev/null && { echo -e "\n[Error] - [$(hostname)]Other mysqld is running"; exit 1;  }
   #echo -e "[$(hostname)]MySQL Software and Database Auto-Installer starting on `date`"
}

debug() {
   echo -e "\n[InputValue]";
   echo -e "SWVER="${SWVER}"\nINST_NAME="${INST_NAME}"\nMYSQL_PW="${MYSQL_PW//?/*}"\nROOT_PW="${ROOT_PW//?/*}
   echo -e "SOFT_LOC[$SWVER]="${SOFT_LOC[$SWVER]}"\nMYSQL_HOME="${MYSQL_HOME[$SWVER]}"\nDATA_LOC="${DATA_LOC[$SWVER]}
   echo -e "DELSW="${DELSW}"\nCHGTZ="${CHGTZ}
   sleep 0.5;echo;read -n1 -s -r -p "Press any key to continue..."
}


VarCheck() {
   echo -e "\nPre-check OS environment and input value..."
   #--Check LOCK_FILE exist or not--#
   [ -f "${LCKFILE}" ] && [ -s "${LCKFILE}" ] && [ -n "`awk -v mh=${MYSQL_HOME[$SWVER]} '($2==mh){print}' ${LCKFILE}`" ] && {
      echo -e "\n[Error] - [$(hostname)]MySQL binary file home (${MYSQL_HOME[$SWVER]}) are installing by other session."
      echo -e "[$(hostname)]Please wait for other software install session complete and re-run again.\n"
      exit 1
   }

   #--Check INSTANCE_NAME input value--#
   [ -n "`echo ${INST_NAME}|egrep "[^[:alnum:]]"`" ] && { echo -e "\n[Error] - Instance Name include illegle character\n"; exit 1; }

   #--Check source file path--#
   ( [[ -z ${SOFT_LOC[$SWVER]%/*} ]] || [[ ${SOFT_LOC[$SWVER]} != *"/"* ]] ) && \
      { echo -e "\n[Error] - [$(hostname)]Source filename need include full path and don't put the file in /.\n"; exit 1; }

   #--Check UNZIPED source file exist or not--#
   [ `find "${SOFT_LOC[$SWVER]%/*}/mysql${SWVER}" -type f 2>/dev/null|wc -l` -gt 0 ] && {
      [[ $DELSW =~ ^(y|n)$ ]] || {
         echo -e "\n[Warming] - [$(hostname)]Unzip destination location (${SOFT_LOC[$SWVER]%/*}/mysql${SWVER}) not empty"
         while [ "${DELSW}" != "y" -a "${DELSW}" != "n" ]; do
            read -p "Do you want to delete exist directory and re-unzip source file? [n]: " DELSW
            [ -n "${DELSW}" ] && DELSW=${DELSW,,} || DELSW="n"
         done
      }
   }

   #--Check MYSQL_HOME binary fiile exist or not--#
   [ `find ${MYSQL_HOME[$SWVER]} -type f 2>/dev/null|wc -l` -gt 0 ] && \
      { echo -e "\n[Error] - [$(hostname)]MySQL Binary file home (${MYSQL_HOME[$SWVER]}) not empty, please check.\n"; exit 1; }

   #--Check if files exist in ${DATA_LOC[$SWVER]}/data and select delete it or not--#
   [ `find ${DATA_LOC[$SWVER]}/data -type f 2>/dev/null|wc -l` -gt 0 ] && \
      { echo -e "\n[Error] - [$(hostname)]Data file location (${DATA_LOC[$SWVER]}/data) not empty, please check.\n"; exit 1; }

   #--Check OS TimeZone setting--#
   [ "${CURTZ}" != "${TIME_ZONE}" ] && {
      [[ "${CHGTZ}" =~ ^(y|n)$ ]] || {
         echo -e "\n[Warming] - [$(hostname)]Current TimeZone \"${CURTZ}\" setting incorrect"
         while [ -z "${CHGTZ}" ] || [ "${CHGTZ}" != "y" -a "${CHGTZ}" != "n" ]; do
            read -p "Change TimeZone to \"${TIME_ZONE}\" [y|n]? " CHGTZ
            [ -n "${CHGTZ}" ] && CHGTZ=${CHGTZ,,}
         done
      }
   }
   #--Checki if script is run directly with explicit instance name, treat as single-instance install and remove group replication settings from initfile_84.cnf.
   if [ "$#" -eq 1 ] && [ "${AUTO_INSTALL_FROM_REMOTE:-0}" != "1" ]; then
      CONFIG_ROOT="/opt/software/mysql_installer"
      TARGET_CNF="${CONFIG_ROOT}/initfile_${SWVER}.cnf"
      TEMPLATE_CNF="${CONFIG_ROOT}/initfile_${SWVER}_template.cnf"

      echo -e "\n[$(hostname)]Direct mode detected, preparing single-instance CNF..."
      if [ -f "${TEMPLATE_CNF}" ]; then
         sed -e '/^[[:space:]]*loose-group/d' -e '/^[[:space:]]*#/d' "${TEMPLATE_CNF}" > "${TARGET_CNF}"
      elif [ -f "${TARGET_CNF}" ]; then
         sed -i '/^[[:space:]]*loose-group/d' "${TARGET_CNF}"
      else
         echo -e "[Error] - [$(hostname)]Can't find ${TARGET_CNF} or ${TEMPLATE_CNF}."
         exit 1
      fi
   fi
   #--Create logfile directory --#
   mkdir -p ${PWD}/log
}

EnvPrepare() {
   #echo -e "\n[$(hostname)]Starting MySQL Install progress..."
   echo -e "\n[$(hostname)]Set OS environment..."
   echo -e "=============================================="
   echo -e "#--- Install RPM package ---#"
   rpm -i --quiet software/*.rpm
   
   echo -e "#--- Check and remove mariadb ---#"
   MARIADB_PKGS=$(rpm -qa | grep mariadb)
   [ -n "$MARIADB_PKGS" ] &&
    { echo "[INFO]Found mariadb packages, removing..." && echo "$MARIADB_PKGS" | xargs yum remove -y; } || echo "[INFO]No mariadb packages installed."

   [ "${CHGTZ}" = "y" ] && {
      echo -e "#--- Change Server TimeZone ---#"
      [ -f "/usr/bin/timedatectl" ] \
         && timedatectl set-timezone ${TIME_ZONE} \
         || { ln -s -f /usr/share/zoneinfo/America/La_Paz /etc/localtime;
              echo "ZONE=\"${TIME_ZONE}\"" >/etc/sysconfig/clock; }
   }

   echo -e "#--- Disable SELinux ---#"
   sed -i "s/^SELINUX=enforcing/SELINUX=disabled/g" /etc/selinux/config
   [ "`sestatus|awk '/^SELinux status:/{print $NF}'`" = "enabled" ] && setenforce 0

   echo -e "#--- Disable Firewall ---#"
   [ -f "/usr/bin/systemctl" ] && {
      systemctl stop firewalld 2>&1 &>/dev/null
      systemctl disable firewalld 2>&1 &>/dev/null
      systemctl start ntpd 2>&1 &>/dev/null
      systemctl enable ntpd 2>&1 &>/dev/null
   } || {
      service iptables stop 2>&1 &>/dev/null
      chkconfig iptables off 2>&1 &>/dev/null
      service ntpd start 2>&1 &>/dev/null
      chkconfig ntpd on 2>&1 &>/dev/null
   }

   echo -e "#--- Add IP/Hostname mapping to /etc/hosts ---#"
   [ -z "`awk '/'$HOSTNAME'/&&/'$OSIP'/' /etc/hosts`" ] && echo "$OSIP  	$HOSTNAME" >>/etc/hosts

   echo -e "#--- Create MySQL OS group ---#"
   [ -z "`grep '^mysql:' /etc/group`" ] \
      && groupadd mysql \
      || echo "[Info] - OS group MYSQL already exist, skip create group."

   echo -e "#--- Create MySQL OS account ---#"
   [ -z "`grep '^mysql:' /etc/passwd`" ] \
      && { useradd -r -g mysql -s /bin/false mysql; echo "${MYSQL_PW}"|passwd mysql --stdin &>/dev/null; } \
      || echo "[Info] - OS account MySQL already exist, skip create account and reset password"

   echo -e "#--- Disable public YUM server ---#"
   for F in `find /etc/yum.repos.d -name public-yum*.repo`; do mv -f $F $F.bak; done

   echo -e "#--- Check YUM server status ---#"
   yum clean all; yum repolist all;
   case "${OSVER}" in
      8.8)
         [ `dnf repoquery --qf '%{name}' 2>/dev/null|wc -l` -eq 0 ] && \
            { echo -e "\n[Error] - [$(hostname)]No avaliable YUM server\n"; exit 1; }
         ;;
      6.6|7.4|7.8)
         [ `yum repolist 2>/dev/null|awk '/repolist/{gsub(",","");print $2}'` -eq 0 ] && \
            { echo -e "\n[Error] - [$(hostname)]No avaliable YUM server\n"; exit 1; }
         ;;
      *)
         { echo -e "\n[Error] - [$(hostname)]This script only support Oracle Enterprise Linux 6.6 7.4 7.8 8.8\n"; exit 1; }
         ;;
   esac

   echo -e "#--- Install mandatory RPM package ---#"
   yum install bc vim-enhanced tar unzip net-tools perl sysstat -y -q

   echo -e "#--- Setting PATH variable ---#"
   [ -z "$(grep '\.bash_alias' ~/.bash_profile)" ] && echo ". ~/.bash_alias" >>~/.bash_profile
   cat > ~/.bash_alias <<EOF
export PATH=${MYSQL_HOME[$SWVER]}/bin:$PATH
EOF
   . ~/.bash_profile

   echo -e "==================== done ===================="
}

UnzipSource() {
   echo -e "\n[$(hostname)]Unzip Source file..."
   echo -e "=============================================="

   echo -e "#--- Check SOURCE_FILE.ZIP exist or not ---#"
   [ `find ${SOFT_LOC[$SWVER]%/*} -name ${SOFT_LOC[$SWVER]##*/} 2>/dev/null|wc -l` -eq 0 ] && \
      { echo -e "\n[Error] - [$(hostname)]Oracle source (${SOFT_LOC[$SWVER]}) not exist.\n"; exit 1; }

   [ "${DELSW}" = "y" ] && { echo -e "#--- Delete UNZIP source file ---#"; rm -rf ${SOFT_LOC[$SWVER]%/*}/mysql${SWVER}; }

   [[ -z ${DELSW} || ${DELSW} = "y" ]] && {
      echo -e "#--- Check UnZip location free space ---#"
      [ `df -Pm ${SOFT_LOC[$SWVER]%/*}|grep -v ^Filesystem|awk '{print $4}'` -lt `echo $((UNZIPSPACE[$SWVER]))` ] && \
         { echo -e "\n[Error] - [$(hostname)]UnZip location (${SOFT_LOC[$SWVER]%/*}/mysql${SWVER}) free space less than requirement ${UNZIPSPACE[$SWVER]}MB.\n"; exit 1; }

      echo -e "#--- UnZip source file ${SOFT_LOC[$SWVER]} ---#"
      unzip -q ${SOFT_LOC[$SWVER]} -d ${SOFT_LOC[$SWVER]%/*}/mysql${SWVER}
   }

   echo -e "#--- Check binary file location free space ---#"
   mkdir -p ${MYSQL_HOME[$SWVER]%/*}
   [ `df -Pm ${MYSQL_HOME[$SWVER]%/*}|grep -v ^Filesystem|awk '{print $4}'` -lt `echo $((MHOMESPACE[$SWVER]))` ] && \
      { echo -e "\n[Error] - [$(hostname)]Binary file location (${MYSQL_HOME[$SWVER]%/*}) free space less than requirement ${MHOMESPACE[$SWVER]}MB.\n"; exit 1; }

   echo -e "#--- UnZip binary file from tar.xz file ---#"
   FILENAME=$(find ${SOFT_LOC[$SWVER]%/*}/mysql${SWVER} -name "*-x86_64.tar.xz"|tail -n1)
   [ -n "${FILENAME}" ] && tar xf ${FILENAME} -C ${MYSQL_HOME[$SWVER]%/*}
   mv ${MYSQL_HOME[$SWVER]%/*}/${UNZIPDIR[$SWVER]} ${MYSQL_HOME[$SWVER]}

   echo -e "==================== done ===================="
}


InitialDB() {
   echo -e "\n[$(hostname)]Initial MySQL database [${INST_NAME}]..."
   echo -e "=============================================="

   echo -e "#--- Create data directory and config file ---#"
   mkdir -p ${DATA_LOC[$SWVER]}/{data,cnf,binlog,relaylog}
   cp -p /opt/software/mysql_installer/initfile_${SWVER}.cnf ${DATA_LOC[$SWVER]}/cnf/${INST_NAME,,}.cnf
   sed -i -e "s/<MYSQL_HOME>/${MYSQL_HOME[$SWVER]////\\/}/g; s/<DATA_LOC>/${DATA_LOC[$SWVER]////\\/}/g; s/<HOSTNAME>/`hostname`/g;" ${DATA_LOC[$SWVER]}/cnf/${INST_NAME,,}.cnf
   
   #Change server id to ip format on my.cnf
   IP=$(hostname -I | awk '{print $1}') 
   SERVER_ID=$(echo $IP | awk -F. '{print $1$2$3$4}')
   sed -i "s/<SERVERID>/${SERVER_ID}/" ${DATA_LOC[$SWVER]}/cnf/${INST_NAME,,}.cnf
   sed -i "s/<LOCALDBIP>/${IP}/" ${DATA_LOC[$SWVER]}/cnf/${INST_NAME,,}.cnf

   echo -e "#--- Change folder priviledge ---#"
   chown -R mysql:mysql ${MYSQL_HOME[$SWVER]} ${DATA_LOC[$SWVER]%/*}
   chmod 750 ${MYSQL_HOME[$SWVER]} ${DATA_LOC[$SWVER]}

   echo -e "#--- Initial ${INST_NAME} database ---#"
   ${MYSQL_HOME[$SWVER]}/bin/mysqld --defaults-extra-file=${DATA_LOC[$SWVER]}/cnf/${INST_NAME,,}.cnf --initialize-insecure --user=mysql

   echo -e "#--- Setting auto startup ---#"
   cat >/etc/systemd/system/mysqld.service <<EOF
[Unit]
Description=MySQL Server
After=network.target
Wants=network.target

[Service]
User=mysql
Group=mysql
ExecStart=${MYSQL_HOME[$SWVER]}/bin/mysqld --defaults-extra-file=${DATA_LOC[$SWVER]}/cnf/${INST_NAME,,}.cnf
LimitNOFILE=5000
Restart=always

[Install]
WantedBy=multi-user.target
EOF
   systemctl daemon-reload
   systemctl start mysqld.service
   systemctl enable mysqld.service

   [ -f "${MYSQL_HOME[$SWVER]}/bin/mysqladmin" ] && until ${MYSQL_HOME[$SWVER]}/bin/mysqladmin ping --silent; do
      echo "Waiting for MySQL to start..."
      sleep 2
done

   echo -e "==================== done ===================="
}

PostAction() {
   echo -e "\n[$(hostname)]Doing post action..."
   echo -e "=============================================="

   echo -e "#--- Setting global option variables ---#"
   touch /etc/my.cnf
   [ -z "$(grep '^\[MYSQL\]' /etc/my.cnf)" ] && echo '[MYSQL]' >>/etc/my.cnf
   [ -z "$(grep '^prompt=' /etc/my.cnf)" ] && echo 'prompt="(\u@\h) [\d]> "' >>/etc/my.cnf

   echo -e "#--- Reset root passwrd and add OS authentication ---#"
   mysql --skip-password -uroot --force -t <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '$MYSQL_PW';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
INSTALL PLUGIN auth_socket SONAME 'auth_socket.so';
ALTER USER 'root'@'localhost' IDENTIFIED WITH auth_socket;
FLUSH PRIVILEGES;
EOF

#Grant permission to dba and cluster user
   mysql --skip-password -uroot --force -t <<EOF
CREATE USER icadmin@'%' IDENTIFIED BY 'mysql_123';
GRANT ALL PRIVILEGES ON *.* TO 'icadmin'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
CREATE USER 'dba'@'%' IDENTIFIED BY 'mysql_123';
GRANT ALL PRIVILEGES ON *.* TO 'dba'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
CREATE USER 'zbx_monitor'@'%' IDENTIFIED BY '123';
GRANT REPLICATION CLIENT,PROCESS,SHOW DATABASES,SHOW VIEW,SELECT ON *.* TO 'zbx_monitor'@'%';
FLUSH PRIVILEGES;
EOF


   echo -e "#--- Remove anonymous user ---#"
   mysql -e "DELETE FROM mysql.user WHERE User='';FLUSH PRIVILEGES;"

   echo -e "==================== done ===================="
}

ConfigZabbix() {
  echo -e "\n[$(hostname)]Install Zabbix Agent..."
  echo -e "=============================================="
  yum install -y /opt/software/mysql_installer/software/zabbix-agent2-7.0.19-release1.el8.x86_64.rpm
  cp -p /opt/software/mysql_installer/zabbix/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf
  cp -p /opt/software/mysql_installer/zabbix/linux_discovery.sh /etc/zabbix/zabbix_agent2.d/linux_discovery.sh 
  cp -p /opt/software/mysql_installer/zabbix/userparameter_mysql.conf /etc/zabbix/zabbix_agent2.d/userparameter_mysql.conf  
  cp -p /opt/software/mysql_installer/zabbix/userparameter_mysqlrouter.conf /etc/zabbix/zabbix_agent2.d/userparameter_mysqlrouter.conf
  echo -e "#--- Add new user to /etc/sudoers.d/zabbix"
  echo "zabbix  ALL=(ALL)       NOPASSWD:ALL" | tee /etc/sudoers.d/zabbix
  chmod 440 /etc/sudoers.d/zabbix
  systemctl enable zabbix-agent2
  systemctl restart zabbix-agent2
  
  echo -e "======================done===================="
}

CleanUp() {
   [ -f "${LCKFILE}" ] && sed -i "/$(echo "${MYSQL_HOME[$SWVER]}"|sed 's_/_\\/_g')/ {/$$/d}" ${LCKFILE}
   [ -f "${LCKFILE}" ] && [ ! -s "${LCKFILE}" ] && rm -rf ${LCKFILE}
}


# main()
PreCheck
#IntActIn
#VarCheck
VarCheck "$@"

#--- create lock file ---#
echo ${SWVER} ${MYSQL_HOME[$SWVER]} ${INST_NAME} $$ >>${LCKFILE}

{
#debug
EnvPrepare
UnzipSource
InitialDB
PostAction
ConfigZabbix
} | tee ${LOGFILE[$SWVER]}

#--- remove lock file ---#
[ -f "${LCKFILE}" ] && sed -i "/$(echo "${MYSQL_HOME[$SWVER]}"|sed 's_/_\\/_g')/ {/$$/d}" ${LCKFILE}

echo -e "\nYou can find the log about this install session at:\n   ${LOGFILE[$SWVER]}"
echo -e "\nAll step completed on `date`"
echo -e "MySQL ${SWVER} software install successfully."
