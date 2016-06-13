#!/bin/bash
#log function
NAMEHOST=$HOSTNAME
if [  -e $PWD/lib/mitaka-log.sh ]
then	
	source $PWD/lib/mitaka-log.sh
else
	echo -e "\033[41;37m $PWD/mitaka-log.sh is not exist. \033[0m"
	exit 1
fi
#input variable
if [  -e $PWD/lib/installrc ]
then	
	source $PWD/lib/installrc 
else
	echo -e "\033[41;37m $PWD/lib/installr is not exist. \033[0m"
	exit 1
fi
if [  -e /etc/openstack-mitaka_tag/computer.tag  ]
then
	echo -e "\033[41;37m Oh no ! you can't execute this script on computer node.  \033[0m"
	log_error "Oh no ! you can't execute this script on computer node. "
	exit 1 
fi

if [ -f  /etc/openstack-mitaka_tag/presystem.tag ]
then 
	log_info "config system have installed ."
else
	echo -e "\033[41;37m you should config system first. \033[0m"
	exit
fi

if [ -f  /etc/openstack-mitaka_tag/install_mariadb.tag ]
then 
	echo -e "\033[41;37m you haved config Basic environment \033[0m"
	log_info "you had install mariadb."	
	exit
fi

#test network
function fn_test_network () {
if [ -f $PWD/lib/proxy.sh ]
then 
	source  $PWD/lib/proxy.sh
fi
curl www.baidu.com >/dev/null   
fn_log "curl www.baidu.com >/dev/null "
}



if  [ -f /etc/yum.repos.d/repo.repo ]
then
	log_info " use local yum."
else 
	fn_test_network
fi


 yum install python-openstackclient -y
 fn_log " yum install python-openstackclient -y"
yum clean all && yum install openstack-selinux -y
fn_log "yum clean all && yum install openstack-selinux -y"
FIRST_ETH_IP=${MANAGER_IP}


function fn_install_percona () {
if [ -e /var/log/mysqld.log  ]
then
	rm -rf /var/log/mysqld.log
	fn_log "rm -rf /var/log/mysqld.log"
fi
if [ -e /var/lib/mysql ]
then	
	rm -rf  /var/lib/mysql
	fn_log "rm -rf  /var/lib/mysql"
fi

yum install Percona-Server-server-57 -y
fn_log "yum install Percona-Server-server-57 -y"
rm -rf /etc/my.cnf.d/openstack.cnf &&  cp -a $PWD/lib/mariadb_openstack.cnf /etc/my.cnf.d/openstack.cnf
fn_log "cp -a $PWD/lib/mariadb_openstack.cnf /etc/my.cnf.d/openstack.cnf"
echo " " >>/etc/my.cnf.d/openstack.cnf
echo "bind-address = ${MANAGER_IP}" >>/etc/my.cnf.d/openstack.cnf
service mysqld restart
fn_log "service mysqld restart"
chkconfig mysqld on
fn_log "chkconfig mysqld on"
TMP_PASSWD=`cat /var/log/mysqld.log  | grep "A temporary password" | awk -F " " '{print$11}'`
fn_log "set TMP_PASSWD=`cat /var/log/mysqld.log  | grep "A temporary password" | awk -F " " '{print$11}'` "
echo "mysqladmin -u root -p"TMPPASSWD" password ${ALL_PASSWORD}"  >tmp_modify_passwd
fn_log "echo "mysqladmin -u root -p"TMPPASSWD" password ${ALL_PASSWORD}"  >tmp_modify_passwd"
sed -i "s/TMPPASSWD/${TMP_PASSWD}/g" tmp_modify_passwd
fn_log "sed -i "s/TMPPASSWD/${TMP_PASSWD}/g" tmp_modify_passwd"
bash -x  tmp_modify_passwd
fn_log "bash -x  tmp_modify_passwd"
rm -f  tmp_modify_passwd
fn_log "rm -f  tmp_modify_passwd"
 mysql_secure_installation -p${ALL_PASSWORD}<<EOF
n
y
y
y
y 
EOF
fn_log "mysql_secure_installation"
}

function fn_install_mariadb () {
yum clean all &&  yum install mariadb mariadb-server python2-PyMySQL  -y
fn_log "yum clean all &&  yum install mariadb mariadb-server python2-PyMySQL  -y"
rm -rf /etc/my.cnf.d/openstack.cnf &&  cp -a $PWD/lib/mariadb_openstack.cnf /etc/my.cnf.d/openstack.cnf
fn_log "cp -a $PWD/lib/mariadb_openstack.cnf /etc/my.cnf.d/openstack.cnf"
echo " " >>/etc/my.cnf.d/openstack.cnf
echo "bind-address = ${FIRST_ETH_IP}" >>/etc/my.cnf.d/openstack.cnf

#start mariadb
systemctl enable mariadb.service &&  systemctl start mariadb.service 
fn_log "systemctl enable mariadb.service &&  systemctl start mariadb.service"
mysql_secure_installation <<EOF

y
${ALL_PASSWORD}
${ALL_PASSWORD}
y
y
y
y
EOF
fn_log "mysql_secure_installation"
}




function fn_install_db () {
if [ ${DB_TYPE}x = mariadbx   ]
then
	fn_install_mariadb
	fn_log "fn_install_mariadb"
elif [ ${DB_TYPE}x  = perconax  ]
then
	fn_install_percona
	fn_log "fn_install_percona"
else
	echo -e "\033[41;37m please check option DB_TYPE in installrc ,please give mariadb or percona. \033[0m"
	log_error "please check option DB_TYPE in installrc ,please give mariadb or percona."
	exit 1 
fi
}


DB_PROCESS=`ps -ef | grep mysql | grep -v  color | wc -l`
if [  ${DB_PROCESS} -gt 0   ]
then
	mysql -uroot -p${ALL_PASSWORD} -e "show status" >/dev/null 
	if [ $? -eq 0  ]
	then
		log_info "database had installed."
	else
		fn_install_db
	fi
else
	fn_install_db
fi




function fn_install_rabbit () {
yum clean all && yum install rabbitmq-server -y
fn_log "yum clean all && yum install rabbitmq-server -y"

#start rabbitmq-server.service
systemctl enable rabbitmq-server.service &&  systemctl start rabbitmq-server.service 
fn_log "systemctl enable rabbitmq-server.service &&  systemctl start rabbitmq-server.service"

rabbitmqctl add_user openstack ${ALL_PASSWORD}
fn_log "rabbitmqctl add_user openstack ${ALL_PASSWORD}"
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
fn_log "rabbitmqctl set_permissions openstack ".*" ".*" ".*""
}
function fn_test_rabbit () {
RABBIT_STATUS=`rabbitmqctl list_users | grep openstack | awk -F " " '{print$1}'`
if [ ${RABBIT_STATUS}x  = openstackx ]
then 
	log_info "rabbit had installed."
else
	fn_install_rabbit
fi
}
if [ -f /usr/sbin/rabbitmqctl  ]
then
	log_info "rabbit had installed."
else
	fn_test_rabbit
fi
yum  -y install memcached python-memcached
fn_log "yum  -y install memcached python-memcached"
systemctl enable memcached.service && systemctl restart memcached.service
fn_log "systemctl enable memcached.service && systemctl restart memcached.service"


echo -e "\033[32m ################################################ \033[0m"
echo -e "\033[32m ###   Install Mariadb and Rabbitmq Sucessed.#### \033[0m"
echo -e "\033[32m ################################################ \033[0m"
if  [ ! -d /etc/openstack-mitaka_tag ]
then 
	mkdir -p /etc/openstack-mitaka_tag  
fi
echo `date "+%Y-%m-%d %H:%M:%S"` >/etc/openstack-mitaka_tag/install_mariadb.tag
