#!/bin/bash
# 2025-09-10    Stanley Chen    # initial version, support remote innoDB cluster install   

# Deploy and run setup_innodb_cluster.sh on the first DB server
# Also check /etc/hosts on all nodes, stop if any entry is missing

# Safety mode, stop the script when a command fails
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 <NODE1(PRIMARY_HOST)> <NODE2> <NODE3> [<NODE4> ...]"
  exit 1
fi

PRIMARY_HOST=$1
shift
ALL_NODES=("$PRIMARY_HOST" "$@")

MYSQL_USER=""icadmin""
MYSQL_PWD="mysql_123"
MYSQL_BIN="/opt/mysql84/bin/mysql"

REMOTE_DIR="/opt/software/mysql_installer"
REMOTE_SCRIPT="${REMOTE_DIR}/innodb_cluster_setup.sh"
LOCAL_SCRIPT="./innodb_cluster_setup.sh"

# 1. Check /etc/hosts on all nodes
echo -e "\nChecking /etc/hosts entries on all nodes..."
missing=0
for node in "${ALL_NODES[@]}"; do
  echo " Checking ${node} ..."
  for ip in "${ALL_NODES[@]}"; do
    ssh $node "grep -q '${ip}' /etc/hosts" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      echo "[Error] ${node} is missing entry for ${ip} in /etc/hosts "
      echo "    Please check /etc/hosts on $node"
      missing=1
    fi
  done
done

if [ $missing -ne 0 ]; then
  echo "[Error] Missing /etc/hosts entries detected. Aborting deployment!"
  exit 1
fi
echo -e "[Pass] /etc/hosts check passed on all nodes.\n"

# 2. Check variable server_id  loose-group_replication_group_name consistency (via MySQL CLI)
echo "Checking server_id and loose-group_replication_group_name on all nodes..."
declare -A server_ids
declare -A group_names

for node in "${ALL_NODES[@]}"; do
  results=$(ssh -o BatchMode=yes $node "$MYSQL_BIN -Nse \"  SHOW VARIABLES WHERE Variable_name IN ('group_replication_group_name','server_id');\"")

  while read -r var value; do
    if [[ "$var" == "server_id" ]]; then
      server_ids["$node"]="$value"
    elif [[ "$var" == "group_replication_group_name" ]]; then
      group_names["$node"]="$value"
    fi
  done <<< "$results"
done

unique_ids=$(printf "%s\n" "${server_ids[@]}" | sort -u | wc -l)
total_ids=${#server_ids[@]}
if [[ $unique_ids -ne $total_ids ]]; then
  echo "[Error] server_id is duplicated:"
  for node in "${!server_ids[@]}"; do
    echo "  $node : ${server_ids[$node]}"
  done
else
  echo "[Pass] There are no duplicate server_id "
fi

unique_groups=$(printf "%s\n" "${group_names[@]}" | sort -u | wc -l)
if [[ $unique_groups -ne 1 ]]; then
  echo "[Error] Variable loose_group_replication_group_name is NOT match"
  for node in "${!group_names[@]}"; do
    echo "  $node : ${group_names[$node]}"
  done
  exit 1
else
  group_name_1=$(printf "%s\n" "${group_names[@]}" | sort -u |head -n1)
  echo -e "[Pass] All nodes have consistent group_replication_group_name: $group_name_1\n"
fi


# 3. Copy script to primary server
echo "Copying script to ${PRIMARY_HOST}:${REMOTE_SCRIPT}"
ssh $PRIMARY_HOST "mkdir -p ${REMOTE_DIR}"
scp $LOCAL_SCRIPT ${PRIMARY_HOST}:${REMOTE_SCRIPT}

# 4. Make script executable on primary server
ssh $PRIMARY_HOST "chmod +x ${REMOTE_SCRIPT}"

# 5. Run script remotely on primary server
OTHER_NODES=("${ALL_NODES[@]:1}")
echo "Running script on ${PRIMARY_HOST}"
ssh $PRIMARY_HOST "${REMOTE_SCRIPT} ${OTHER_NODES[*]}"
echo -e "\n"

