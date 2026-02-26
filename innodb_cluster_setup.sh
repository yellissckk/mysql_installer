#!/bin/bash
# 2025-09-10    Stanley Chen    # initial version, local remote innoDB cluster install   

# Automatically create a MySQL InnoDB Cluster
# Run this script on the first DB server
# Using mysqlsh + JavaScript

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <NODE2_IP> <NODE3_IP> [<NODE4_IP> ...]"
  exit 1
fi

CLUSTER_NAME="mycluster"
DB_USER="icadmin"
DB_PASS="mysql_123"
PRIMARY_NODE="127.0.0.1:3306"
MYSQL_PORT=3306

# Append :3306 if no port is specified
format_nodes=()
for n in "$@"; do
  if [[ "$n" == *":"* ]]; then
    format_nodes+=("$n")
  else
    format_nodes+=("${n}:${MYSQL_PORT}")
  fi
done

NODES=("$PRIMARY_NODE" "${format_nodes[@]}")
JSON_ARRAY=$(printf '[%s]' "$(printf '"%s",' "${NODES[@]}" | sed 's/,$//')")

TMP_JS="setup_cluster.js"
cat > $TMP_JS <<EOF
var dbUser = "${DB_USER}";
var dbPass = "${DB_PASS}";
var clusterName = "${CLUSTER_NAME}";
var nodes = ${JSON_ARRAY};

// Connect and make this the active shell session
shell.connect(dbUser + ":" + dbPass + "@" + nodes[0]);

// Configure the first node
dba.configureInstance(dbUser + ":" + dbPass + "@" + nodes[0]);

// Try to get existing cluster
var cluster;
try {
  cluster = dba.getCluster();
  //cluster = dba.getCluster(clusterName);
  print(" Cluster '" + clusterName + "' already exists, reusing it...");
} catch (err) {
  print(" Creating new cluster '" + clusterName + "' ...");
  //cluster = dba.createCluster(clusterName, {localAddress: nodes[0]});
  cluster = dba.createCluster(clusterName)
}

// Add other nodes (skip if already in cluster)
for (var i = 1; i < nodes.length; i++) {
  try {
    //print(dbUser + dbPass + nodes[i]);
    cluster.addInstance(dbUser + ":" + dbPass + "@" + nodes[i], {recoveryMethod: "clone"});
    print(" Added instance " + nodes[i]);
  } catch (err) {
    print(" Skipping node " + nodes[i] + ": " + err.message);
  }
}

print(" InnoDB Cluster setup completed!");
cluster.status();
EOF

mysqlsh --js --file=$TMP_JS

