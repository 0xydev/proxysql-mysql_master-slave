#!/bin/bash
set -x  # Komutları göster
set -e  # Hata durumunda scripti durdur

cat << EOF > /tmp/master1.cnf
[client]
host=master1
user=root
password=$MYSQL_ROOT_PASSWORD
EOF

cat << EOF > /tmp/master2.cnf
[client]
host=master2
user=root
password=$MYSQL_ROOT_PASSWORD
EOF

cat << EOF > /tmp/master3.cnf
[client]
host=master3
user=root
password=$MYSQL_ROOT_PASSWORD
EOF


# Her komut için hata kontrolü
check_mysql_command_result() {
    if [ $? -ne 0 ]; then
        echo "MySQL command failed"
        exit 1
    fi
}

# Group Replication kontrolü
check_replication() {
    mysql --defaults-file=/tmp/master1.cnf -e "
        SELECT COUNT(*) as members 
        FROM performance_schema.replication_group_members
        WHERE MEMBER_STATE = 'ONLINE';" | grep -q "3"
    if [ $? -ne 0 ]; then
        echo "Group Replication failed"
        exit 1
    fi
}

# echo "Installing group_replication plugin on member-1..."
# CHANGE MASTER TO MASTER_USER='repl', MASTER_PASSWORD='repl' FOR CHANNEL 'group_replication_recovery';
# "INSTALL PLUGIN group_replication SONAME 'group_replication.so';"
# mysql -hmaster1 -uroot -proot_password -e "INSTALL PLUGIN group_replication SONAME 'group_replication.so';"

# check group_replication plugin installed on master1
echo "Checking group_replication plugin on master1..."
count=1
status=1
while [ $count -le 30 ]
do
    echo "Attempt $count: Checking master1 connection..."
    if mysqladmin --defaults-file=/tmp/master1.cnf ping &>/dev/null; then
        mysql --defaults-file=/tmp/master1.cnf -e "SELECT PLUGIN_NAME, PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS WHERE PLUGIN_NAME='group_replication';" && status=0
    fi
    echo "Status: $status"
    ((count++))
    [ $status -eq 0 ] && break
    echo "Waiting 5 seconds before next attempt..."
    sleep 5
done

check_mysql_command_result
mysql -h master2 -u root -e "SELECT PLUGIN_NAME, PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS WHERE PLUGIN_NAME='group_replication';"
check_mysql_command_result
mysql -h master3 -u root -e "SELECT PLUGIN_NAME, PLUGIN_STATUS FROM INFORMATION_SCHEMA.PLUGINS WHERE PLUGIN_NAME='group_replication';"
check_mysql_command_result

echo "Bootstrapping first member (mysql-member-1)..."
mysql --defaults-file=/tmp/master1.cnf -e "
SET GLOBAL group_replication_bootstrap_group=ON;
START GROUP_REPLICATION;
SET GLOBAL group_replication_bootstrap_group=OFF;"
check_mysql_command_result
