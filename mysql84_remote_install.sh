#!/bin/bash
# 2025-09-10    Stanley Chen    # initial version, support remote install   

# Safety mode, stop the script when a command fails
set -euo pipefail

# Installation files
INSTALL_DB_SCRIPT="mysql_auto_install_2.5.0604.sh"
INSTALL_CLUSTER_SCRIPT=("innodb_cluster_setup.sh" "innodb_cluster_deploy.sh")
INSTALL_ZABBIX_CONFG=("./zabbix/linux_discovery.sh" "./zabbix/userparameter_mysql.conf" "./zabbix/zabbix_agent2.conf" "./zabbix/userparameter_mysqlrouter.conf")
CNF_TEMPLATE="initfile_84_template.cnf"
CNF="initfile_84.cnf"
MYSQL_ZIP="./software/V1047836-01_MySQL_EE_8.4.4_TAR_glibc_2.28.zip"
MYSQL_RPM=("./software/mysql-router-commercial-8.4.6-1.1.el8.x86_64.rpm" "./software/mysql-shell-commercial-8.4.4-1.1.el8.x86_64.rpm" "./software/zabbix-agent2-7.0.19-release1.el8.x86_64.rpm")

# Check input variable , should be 1 or 3 above.
if [[ $# -ne 1 && $# -lt 3 ]]; then
  echo "Usage: $0 <HOST1:INST1> [<HOST2:INST2> <HOST3:INST3> ...]"
  echo "[ERROR] Arguments must be either 1 or at least 3 host:instance pairs."
  exit 1
fi

# Check input variable if duplicated
DUP_CHECK=$(printf "%s\n" "$@" | sort | uniq -d)
if [[ -n "$DUP_CHECK" ]]; then
  echo "[ERROR] Found duplicate host:instance argument(s):"
  echo "$DUP_CHECK"
  exit 1
fi

# Log settings
LOG_DIR="./log"
mkdir -p "${LOG_DIR}"
LOGFILE="${LOG_DIR}/remote_install_`date '+%Y-%m-%d_%H-%M-%S'`.log"

REMOTE_DIR="/opt/software/mysql_installer"

# Check required files exist locally
FILES_TO_CHECK=("$INSTALL_DB_SCRIPT" "$CNF" "$CNF_TEMPLATE" "$MYSQL_ZIP" "${INSTALL_ZABBIX_CONFG[@]}" "${MYSQL_RPM[@]}" "${INSTALL_CLUSTER_SCRIPT[@]}")
for f in "${FILES_TO_CHECK[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "[ERROR] Can't find file $f , please copy file into directory ./software"
    exit 1
  fi
done

{
# Replace replication_group_seeds / group_uuid on my.cnf if user want to install inno cluster
if [[ $# -gt 1 ]]; then
UUID=$(uuidgen)
HOST_PORTS=""
for arg in "$@"; do
  HOST="${arg%%:*}"
  HOST_PORTS+="${HOST}:33061,"
done
HOST_PORTS="${HOST_PORTS%,}"
  echo "All host:port list = ${HOST_PORTS}"
  sed -e "s|<SERVER_GROUP>|${HOST_PORTS}|g" -e "s|<GROUP_UUID>|${UUID}|g" "${CNF_TEMPLATE}" > "${CNF}"
elif [[ $# -eq 1 ]]; then
  sed -e '/^[[:space:]]*loose-group/d' -e '/^[[:space:]]*#/d' "${CNF_TEMPLATE}" > "${CNF}"
fi

# Create trust between local deploy server & remote server
echo  -e "\n================================================================"
echo "[Start] Create server trust"
echo "Time: `date`"
echo "Target: $*"
echo "================================================================"
for arg in "$@"; do
  HOST="${arg%%:*}"       # part before ":"
  INST_NAME="${arg##*:}"  # part after ":"
  {
    # Create mutual SSH trust between local and remote host
    echo "[INFO] Create mutual SSH trust between local and remote host ..."
    ./ssh_trust.sh mutual root@${HOST}
}
done  
echo -e "[END] Server trust create \n\n"

# Start remote install
echo "================================================================"
echo "[Start] Remote MySQL Install"
echo "Time: `date`"
echo "Target: $*"
echo "================================================================"
# Copy file and install
for arg in "$@"; do
  HOST="${arg%%:*}"       # part before ":"
  INST_NAME="${arg##*:}"  # part after ":"
  { 
    echo "---------------------------------------------------------------"
    echo "[INFO] Start remote install on ${HOST} with instance ${INST_NAME} ..."
    # Create remote directory for installation files
    echo "[INFO] Create remote directory ${REMOTE_DIR} ..."
    ssh root@"${HOST}" "mkdir -p ${REMOTE_DIR}"
    ssh root@"${HOST}" "mkdir -p ${REMOTE_DIR}/software"
    ssh root@"${HOST}" "mkdir -p ${REMOTE_DIR}/zabbix"

    # Transfer installation files to remote host
    echo "[INFO] Copy files to ${HOST}:${REMOTE_DIR} ..."
    scp "$INSTALL_DB_SCRIPT" "$CNF" root@"${HOST}:${REMOTE_DIR}/"
    scp "$MYSQL_ZIP" "${MYSQL_RPM[@]}"  root@"${HOST}:${REMOTE_DIR}/software"
    scp "${INSTALL_ZABBIX_CONFG[@]}" root@"${HOST}:${REMOTE_DIR}/zabbix"

    # Execute installation script on remote host
    ssh root@"${HOST}" bash -s <<EOF
set -e
cd ${REMOTE_DIR}
chmod +x $INSTALL_DB_SCRIPT
AUTO_INSTALL_FROM_REMOTE=1 ./$INSTALL_DB_SCRIPT "$INST_NAME"

EOF
    echo -e "[SUCCESS] Installation completed on ${HOST} with instance ${INST_NAME}\n\n"
  }
done

# Wait for all background jobs to finish
wait

echo "================================================================"
echo "[End] Remote MySQL Install"

# Install inno cluster if input variable > 1
if [[ $# -gt 1 ]]; then
HOST_LIST=""
for arg in "$@"; do
  HOST="${arg%%:*}"
  HOST_LIST+="${HOST} "
done
echo ""
echo "================================================================"
echo -e "[Start] Remote MySQL INNO Cluster Install"
echo "================================================================"
./innodb_cluster_deploy.sh $HOST_LIST
fi

echo "Time: `date`"
echo "================================================================"

} 2>&1 | tee -a "${LOGFILE}"

echo -e "Local log file ï¼š ${LOGFILE}"

