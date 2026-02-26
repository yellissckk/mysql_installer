#!/bin/bash
#
# check4.sh
# Script to check multiple DB nodes and InnoDB Cluster installation
# Usage: ./check4.sh <HOST1> <HOST2> <HOST3> ...
#

MYSQL_USER="icadmin"
MYSQL_PASS="123"
MYSQL_PORT=3306   # Default MySQL port

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <HOST1> <HOST2> <HOST3> ..."
  exit 1
fi

# Store cluster details for summary
CLUSTER_SUMMARY=()
SEEN=()   # to avoid duplicate nodes

for HOST in "$@"; do
  echo
  echo "========== Checking ${HOST}:${MYSQL_PORT} =========="

  # 1. Check if mysqld process is running on remote host (requires SSH access)
  if ssh $HOST "pgrep -x mysqld >/dev/null 2>&1"; then
    echo "[PASS] mysqld process is running on $HOST"
  else
    echo "[FAIL] mysqld process NOT running on $HOST"
    CLUSTER_SUMMARY+=("$HOST|N/A|N/A|FAIL")
    continue
  fi

  # 2. Check MySQL connection
  mysql -h ${HOST} -P ${MYSQL_PORT} -u${MYSQL_USER} -p${MYSQL_PASS} -e "SELECT VERSION();" >/dev/null 2>&1 
  if [[ $? -eq 0 ]]; then
    echo "[PASS] Able to connect to MySQL at ${HOST}:${MYSQL_PORT}"
  else
    echo "[FAIL] Unable to connect to MySQL at ${HOST}:${MYSQL_PORT}"
    CLUSTER_SUMMARY+=("$HOST|N/A|N/A|FAIL")
    continue
  fi

  # 3. Verify mysqlsh is installed
  if ! command -v mysqlsh >/dev/null 2>&1; then
    echo "[FAIL] mysqlsh not found on local machine (required for InnoDB Cluster check)"
    exit 1
  fi

  # 4. Get InnoDB Cluster details (no printing here)
  CLUSTER_INFO=$(mysqlsh ${MYSQL_USER}:${MYSQL_PASS}@${HOST}:${MYSQL_PORT} --js -e \
  "try {
      var c = dba.getCluster();
      var status = c.status();
      print('CLUSTER_NAME=' + status.defaultReplicaSet.name + '\n');
      for (var inst in status.defaultReplicaSet.topology) {
        var node = status.defaultReplicaSet.topology[inst];
        print(inst + '|' + status.clusterName + '|' + node['memberRole'] + '|' + node['status'] + '\n');
      }
   } catch(e) { print('NO_CLUSTER\n') }")

  if echo "$CLUSTER_INFO" | grep -q "NO_CLUSTER"; then
    echo "[FAIL] No InnoDB Cluster configured on ${HOST}:${MYSQL_PORT}"
    CLUSTER_SUMMARY+=("$HOST|N/A|N/A|NO_CLUSTER")
  else
    echo "[PASS] InnoDB Cluster detected on ${HOST}:${MYSQL_PORT}"
    while IFS="|" read -r NODE NAME MEMBERROLE STATUS; do
      [[ "$NODE" == NAME* ]] && continue   # skip cluster name line
      [[ -z "$MEMBERROLE" ]] && continue

      # avoid duplicates
      if [[ ! " ${SEEN[@]} " =~ " ${NODE} " ]]; then
        CLUSTER_SUMMARY+=("$NODE|$NAME|$MEMBERROLE|$STATUS")
        SEEN+=("$NODE")
      fi
    done <<< "$CLUSTER_INFO"
  fi
done

echo
echo "========== Cluster Summary =========="
printf "%-25s | %-15s | %-10s | %-10s\n" "Host" "ClusterName" "MemberRole" "Status"
printf -- "-------------------------------------------------------------------------------\n"
for r in "${CLUSTER_SUMMARY[@]}"; do
  IFS="|" read -r NODE NAME MEMBERROLE STATUS <<< "$r"
  printf "%-25s | %-15s | %-10s | %-10s\n" "$NODE" "$NAME" "$MEMBERROLE" "$STATUS"
done

