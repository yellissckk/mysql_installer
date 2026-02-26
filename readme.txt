Prepare
1.Check and change the zabbix server on ./zabbix/zabbix_agent2.conf
2.Check and change password on innodb_cluster_setup.sh
3.Check and change MYSQL_PW on mysql_auto_install_2.5.0604.sh

Installation
1.Deploy single mysql server
./mysql84_remote_install.sh HOST_NAME:INSTAN_NAME

2.Deploy innocluster mysql server
./mysql84_remote_install.sh HOST1_NAME:INSTANCE1_NAME HOST2_NAME:INSTANCE2_NAME HOST3_NAME:INSTANCE3_NAME


