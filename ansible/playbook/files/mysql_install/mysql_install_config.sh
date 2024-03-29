#!/bin/bash
### give it random number to serverid on MariaDB
# To generate a random number in a UNIX or Linux shell, the shell maintains a shell variable named RANDOM. Each time this variable is read, a random number between 0 and 32767 is generated.
SERVERID=$(($RANDOM))
MYSQL_VERSION=$(cat /tmp/MYSQL_VERSION)
CLIENT_PREFFIX="MySQL"
### get amount of memory who will be reserved to InnoDB Buffer Pool
INNODB_MEM=$(expr $(($(cat /proc/meminfo | grep MemTotal | awk '{print $2}') / 10)) \* 6 / 1024)

lg=$(expr $(echo $INNODB_MEM | wc -m) - 3)
var_innodb_suffix="${INNODB_MEM:$lg:2}"

if [ "$var_innodb_suffix" -gt 1 -a "$var_innodb_suffix" -lt 99 ]; then
  var_innodb_suffix="00"
fi

var_innodb_preffix="${INNODB_MEM:0:$lg}"
INNODB_MEM=${var_innodb_preffix}${var_innodb_suffix}M
echo "InnoDB BF Pool: "$INNODB_MEM

### get the number of cpu's to estimate how many innodb instances will be enough for it. ###
NR_CPUS=$(cat /proc/cpuinfo | awk '/^processor/{print $3}' | wc -l)

if [[ $NR_CPUS -gt 8 ]]
then
 INNODB_INSTANCES=16
 INNODB_WRITES=16
 INNODB_READS=16
 INNODB_MIN_IO=200
 INNODB_MAX_IO=2000
 TEMP_TABLE_SIZE='16M'
 NR_CONNECTIONS=1200
 NR_CONNECTIONS_USER=1024
 SORT_MEM='256M'
 SORT_BLOCK="read_rnd_buffer_size                    = 1M
read_buffer_size                        = 1M
max_sort_length                         = 1M
max_length_for_sort_data                = 1M
group_concat_max_len                    = 4096"
else
 INNODB_INSTANCES=8
 INNODB_WRITES=8
 INNODB_READS=8
 INNODB_MIN_IO=200
 INNODB_MAX_IO=800
 TEMP_TABLE_SIZE='16M'
 NR_CONNECTIONS=600
 NR_CONNECTIONS_USER=512
 SORT_MEM='128M'
 SORT_BLOCK="read_rnd_buffer_size                    = 524288
read_buffer_size                        = 262144
max_sort_length                         = 262144
max_length_for_sort_data                = 262144
group_concat_max_len                    = 2048"
fi

### datadir and logdir ####
DATA_DIR="/var/lib/mysql/datadir"
DATA_LOG="/var/lib/mysql-logs"
TMP_DIR="/var/lib/mysql-tmp"

### collation and character set ###
if [ "$MYSQL_VERSION" == "80" ]; then
   COLLATION="utf8mb4_general_ci"
   CHARACTERSET="utf8mb4"
   MYSQL_BLOCK="#### admin extra port ####
admin_address = 127.0.0.1
admin_port = 33306

# native password auth
default-authentication-plugin=mysql_native_password

### configs innodb cluster ######
binlog_checksum=none
binlog_order_commits=1
enforce_gtid_consistency=on
gtid_mode=on
session_track_gtids=OWN_GTID
master_info_repository=TABLE
relay_log_info_repository=TABLE
relay_log_recovery=1
transaction_write_set_extraction=XXHASH64
#### MTS config ####
slave_parallel_type=LOGICAL_CLOCK
slave_preserve_commit_order=1
slave_parallel_workers=8"
elif [ "$MYSQL_VERSION" == "57" ]; then
  COLLATION="utf8_general_ci"
  CHARACTERSET="utf8"
  MYSQL_BLOCK="#### extra confs ####
binlog_checksum=none
binlog_order_commits=1
enforce_gtid_consistency=on
gtid_mode=on
session_track_gtids=OWN_GTID
master_info_repository=TABLE
relay_log_info_repository=TABLE
relay_log_recovery=1
transaction_write_set_extraction=XXHASH64
#### tmp table storage engine ####
internal_tmp_disk_storage_engine = MyISAM
#### MTS config ####
slave_parallel_type=LOGICAL_CLOCK
slave_preserve_commit_order=1
slave_parallel_workers=8
"
else
  COLLATION="utf8_general_ci"
  CHARACTERSET="utf8"
  MYSQL_BLOCK="#### extra confs ####
binlog_checksum=none
enforce_gtid_consistency=on
gtid_mode=on
master_info_repository=TABLE
relay_log_info_repository=TABLE
relay_log_recovery=1
"
fi

echo "[client]
port                                    = 3306
socket                                  = /var/lib/mysql/mysql.sock

[mysqld]
server-id                               = $SERVERID
sql_mode                                = 'ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION'
port                                    = 3306
pid-file                                = /var/lib/mysql/mysql.pid
socket                                  = /var/lib/mysql/mysql.sock
basedir                                 = /usr
local_infile                            = 1

# general configs
datadir                                 = $DATA_DIR
collation-server                        = $COLLATION
character_set_server                    = $CHARACTERSET
init-connect                            = SET NAMES $CHARACTERSET
lower_case_table_names                  = 1
default-storage-engine                  = InnoDB
optimizer_switch                        = 'index_merge_intersection=off'
bulk_insert_buffer_size                 = 128M
thread_cache_size                       = 300

# files limits
open_files_limit                        = 102400
innodb_open_files                       = 65536

# logbin configs
log-bin                                 = $DATA_LOG/mysql-bin
binlog_format                           = ROW
binlog_row_image                        = MINIMAL
expire_logs_days                        = 5
log_bin_trust_function_creators         = 1
sync_binlog                             = 1
log_slave_updates                       = 1

relay_log                               = $DATA_LOG/mysql-relay-bin
relay_log_purge                         = 1

# innodb vars
innodb_buffer_pool_size                 = $INNODB_MEM
innodb_buffer_pool_instances            = $INNODB_INSTANCES
innodb_flush_log_at_trx_commit          = 1
innodb_file_per_table                   = 1
innodb_flush_method                     = O_DIRECT
innodb_flush_neighbors                  = 0
innodb_log_buffer_size                  = 16M
innodb_lru_scan_depth                   = 4096
innodb_purge_threads                    = 4
innodb_sync_array_size                  = 4
innodb_autoinc_lock_mode                = 2
innodb_print_all_deadlocks              = 1
innodb_io_capacity                      = $INNODB_MIN_IO
innodb_io_capacity_max                  = $INNODB_MAX_IO
innodb_read_io_threads                  = $INNODB_READS
innodb_write_io_threads                 = $INNODB_WRITES
innodb_max_dirty_pages_pct              = 90
innodb_max_dirty_pages_pct_lwm          = 10
innodb_doublewrite                      = 1
innodb_thread_concurrency               = 0

# innodb redologs
innodb_log_file_size                    = 1G # 1073741824
innodb_log_files_in_group               = 4

# table configs
table_open_cache                        = 16384
table_definition_cache                  = 52428
max_heap_table_size                     = $TEMP_TABLE_SIZE
tmp_table_size                          = $TEMP_TABLE_SIZE
tmpdir                                  = $TMP_DIR

# connection configs
max_allowed_packet                      = 1G # 1073741824
net_buffer_length                       = 999424
max_connections                         = $NR_CONNECTIONS
max_user_connections                    = $NR_CONNECTIONS_USER
max_connect_errors                      = 100
wait_timeout                            = 28800
connect_timeout                         = 60
skip-name-resolve                       = 1

# sort and group configs
key_buffer_size                         = 32M # 33554432
sort_buffer_size                        = $SORT_MEM
join_buffer_size                        = $SORT_MEM
innodb_sort_buffer_size                 = 67108864
myisam_sort_buffer_size                 = $SORT_MEM
$SORT_BLOCK

# log configs
slow_query_log                          = 1
slow_query_log_file                     = $DATA_LOG/mysql-slow.log
long_query_time                         = 3
log_slow_admin_statements               = 1

log-error                               = $DATA_LOG/mysql-error.log

general_log_file                        = $DATA_LOG/mysql-general.log
general_log                             = 0

# enable scheduler on mysql
event_scheduler                         = 1

# Performance monitoring (with low overhead)
innodb_monitor_enable                   = all
performance_schema                      = ON
performance-schema-instrument           ='%=ON'
performance-schema-consumer-events-stages-current=ON
performance-schema-consumer-events-stages-history=ON
performance-schema-consumer-events-stages-history-long=ON

$MYSQL_BLOCK
" > /etc/my.cnf

### restart mysql service to apply new config file generate in this stage ###
pid_mysql=$(pidof mysqld)
if [[ $pid_mysql -gt 1 ]]
then
kill -15 $pid_mysql
fi
sleep 10

# clean standard mysql dir
rm -rf /var/lib/mysql/*
chown -R mysql:mysql /var/lib/mysql
### remove old config file ####
rm -rf /root/.my.cnf

# create directories for mysql datadir and datalog
if [ ! -d ${DATA_DIR} ]
then
    mkdir -p ${DATA_DIR}
    chmod 755 ${DATA_DIR}
    chown -Rf mysql.mysql ${DATA_DIR}
else
    chown -Rf mysql.mysql ${DATA_DIR}
fi

if [ ! -d ${DATA_LOG} ]
then
    mkdir -p ${DATA_LOG}
    chmod 755 ${DATA_LOG}
    chown -Rf mysql.mysql ${DATA_LOG}
else
    chown -Rf mysql.mysql ${DATA_LOG}
fi

if [ ! -d ${TMP_DIR} ]
then
    mkdir -p ${TMP_DIR}
    chmod 755 ${TMP_DIR}
    chown -Rf mysql.mysql ${TMP_DIR}
else
    chown -Rf mysql.mysql ${TMP_DIR}
fi

### mysql_install_db for deploy a new db fresh and clean ###
mysqld --defaults-file=/etc/my.cnf --initialize-insecure --user=mysql
sleep 5

### start mysql service ###
systemctl enable mysqld.service
sleep 5
systemctl start mysqld.service
sleep 5

### standalone instance standard users ##
REPLICATION_USER_NAME="replication_user"
MYSQLCHK_USER_NAME="mysqlchk"

### generate mysqlchk passwd #####
RD_MYSQLCHK_USER_PWD="mysqlchk-$SERVERID"
touch /tmp/$RD_MYSQLCHK_USER_PWD
echo $RD_MYSQLCHK_USER_PWD > /tmp/$RD_MYSQLCHK_USER_PWD
HASH_MYSQLCHK_USER_PWD=`md5sum  /tmp/$RD_MYSQLCHK_USER_PWD | awk '{print $1}' | sed -e 's/^[[:space:]]*//' | tr -d '/"/'`

### generate replication passwd #####
RD_REPLICATION_USER_PWD="replication-$SERVERID"
touch /tmp/$RD_REPLICATION_USER_PWD
echo $RD_REPLICATION_USER_PWD > /tmp/$RD_REPLICATION_USER_PWD
HASH_REPLICATION_USER_PWD=`md5sum  /tmp/$RD_REPLICATION_USER_PWD | awk '{print $1}' | sed -e 's/^[[:space:]]*//' | tr -d '/"/'`

### users pwd ##
MYSQLCHK_USER_PWD=$HASH_MYSQLCHK_USER_PWD
REPLICATION_USER_PWD=$HASH_REPLICATION_USER_PWD

### generate root passwd #####
if [ "$MYSQL_VERSION" == "80" ]; then
   passwd="$CLIENT_PREFFIX-$SERVERID-my80"
 elif [[ "$MYSQL_VERSION" == "57" ]]; then
   passwd="$CLIENT_PREFFIX-$SERVERID-my57"
 elif [[ "$MYSQL_VERSION" == "56" ]]; then
   passwd="$CLIENT_PREFFIX-$SERVERID-my56"
fi
touch /tmp/$passwd
echo $passwd > /tmp/$passwd
hash=`md5sum  /tmp/$passwd | awk '{print $1}' | sed -e 's/^[[:space:]]*//' | tr -d '/"/'`
hash=`echo ${hash:0:8} | tr  '[a-z]' '[A-Z]'`${hash:8}
hash=$hash\!\$

### update root password #####
mysqladmin -u root password $hash

### show users and pwds ####
echo The server_id is $SERVERID!
echo The root password is $hash
echo The $REPLICATION_USER_NAME password is $REPLICATION_USER_PWD
echo The $MYSQLCHK_USER_NAME password is $MYSQLCHK_USER_PWD

### generate the user file on root linux account #####
echo "[client]
user            = root
password        = $hash

[mysql]
user            = root
password        = $hash
prompt          = '(\u@\h) MySQL [\d]>\_'

[mysqladmin]
user            = root
password        = $hash

[mysqldump]
user            = root
password        = $hash

###### Automated users generated by the installation process ####
#The root password is $hash
#The $REPLICATION_USER_NAME password is $REPLICATION_USER_PWD
#The $MYSQLCHK_USER_NAME password is $MYSQLCHK_USER_PWD
#################################################################
" > /root/.my.cnf

chmod 400 /root/.my.cnf

### setup the users for monitoring/replication streaming and security purpose ###
mysql -e "CREATE USER '$REPLICATION_USER_NAME'@'%' IDENTIFIED BY '$REPLICATION_USER_PWD'; GRANT PROCESS, REPLICATION CLIENT, REPLICATION SLAVE ON *.* TO '$REPLICATION_USER_NAME'@'%';";
mysql -e "CREATE USER '$MYSQLCHK_USER_NAME'@'localhost' IDENTIFIED BY '$MYSQLCHK_USER_PWD'; GRANT PROCESS ON *.* TO '$MYSQLCHK_USER_NAME'@'localhost';";
mysql -e "CREATE USER '$MYSQLCHK_USER_NAME'@'%' IDENTIFIED BY '$MYSQLCHK_USER_PWD'; GRANT PROCESS ON *.* TO '$MYSQLCHK_USER_NAME'@'%';";
mysql -e "DELETE FROM mysql.user WHERE User='';";
mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
mysql -e "flush privileges;"

### REMOVE TMP FILES on /tmp #####
rm -rf /tmp/*
