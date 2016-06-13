#!/usr/bin/env sh
source /root/ecloud.cfg

#define repo port, this port mapping with repo file in /etc/yum.repos.d/*.repo
Port=9001
ssh_key="/root/ecloud/.ssh/id_rsa"

# ecloud prepare, including repo file and rpm
function ecloud_pre()
{
    if [ ! -d "/root/ecloud" ];
    then
        echo "Please conferm if there was ecloud.tar.gz under root"
        exit
    fi

    echo "Ecloud prepare complete.            [done]"

}

# ssh key prepare
function controller_ssh_key()
{
    if [ -d "/root/.ssh" ];
    then
        if [ ! -d "/root/.ssh_bk" ]; then
            mkdir /root/.ssh_bk
            mv /root/.ssh/* /root/.ssh_bk/
        fi
        rm -rf /root/.ssh/*
    else 
        mkdir /root/.ssh
    fi
    cp /root/ecloud/.ssh/* /root/.ssh
    echo "Controller Node ssh complete.       [done]"
}

function compute_ssh_key()
{
    IFS=","
    for host in ${COMPUTE_SERVERS[@]}
    do
        if [ ${CONTROLLER_SERVERS} != ${host} ];
        then
            /root/ecloud/expect.sh $host $ADMIN_PASSWD
        fi
    done  
    echo "Compute Node ssh complete.          [done]"
}

function expand_ssh_key()
{
    IFS=","
    for host in ${EXPAND_SERVERS[@]}
    do
        /root/ecloud/expect.sh $host $ADMIN_PASSWD
    done  
    echo "Expand Node ssh complete.          [done]"
}

# repo prepare
function controller_repo_prepare()
{
    if [ ! -d "/etc/yum.repos.d/bak" ];
    then
        mkdir /etc/yum.repos.d/bak
        mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/
    fi

    # replace the repo
    rm -rf /etc/yum.repos.d/*.repo
    cp /root/ecloud/*.repo /etc/yum.repos.d/
    # http service

    sed -i "s/Controller_IP/$CONTROLLER_SERVERS/g" /etc/yum.repos.d/*.repo
    sed -i "s/PORT/${Port}/g" /etc/yum.repos.d/*.repo
    yum clean all && yum makecache
    yum install ecloud -y
    echo "Controller Repo prepare complete.   [done]"
}

function compute_repo_prepare()
{
    IFS=","
    for host in ${COMPUTE_SERVERS[@]}
    do
        if [ ${CONTROLLER_SERVERS} != ${host} ];
        then
            ssh -i ${ssh_key} root@$host "rm -rf /etc/yum.repos.d/*"
            scp -i ${ssh_key} /etc/yum.repos.d/*.repo  root@$host:/etc/yum.repos.d/
            ssh -i ${ssh_key} root@$host "yum clean all && yum makecache"
            ssh -i ${ssh_key} root@$host "yum install ecloud -y"
            echo "$host Repo prepare complete.      [done]"
        fi
    done
    echo "Compute Repo prepare complete.      [done]"
}

function expand_repo_prepare()
{
    IFS=","
    for host in ${EXPAND_SERVERS[@]}
    do
        ssh -i ${ssh_key} root@$host "rm -rf /etc/yum.repos.d/*"
        scp -i ${ssh_key} /etc/yum.repos.d/*.repo  root@$host:/etc/yum.repos.d/
        ssh -i ${ssh_key} root@$host "yum clean all && yum makecache"
        ssh -i ${ssh_key} root@$host "yum install ecloud -y"
    done
    echo "Expand Repo prepare complete.      [done]"
}

function controller_repo_recover()
{
    rm -rf /etc/yum.repos.d/*.repo
    mv /etc/yum.repos.d/bak/* /etc/yum.repos.d/
    rm -rf /etc/yum.repos.d/bak
    yum clean all && yum makecache
}

function compute_repo_recover()
{
    IFS=","
    for host in ${COMPUTE_SERVERS[@]}
    do
        if [ ${CONTROLLER_SERVERS} != ${host} ];
        then
            ssh -i ${ssh_key} root@$host "rm -rf /etc/yum.repos.d/*"
            scp -i ${ssh_key} /etc/yum.repos.d/*  root@$host:/etc/yum.repos.d/
            ssh -i ${ssh_key} root@$host "yum clean all && yum makecache"
        fi
    done
}

function expand_repo_recover()
{
    IFS=","
    for host in ${EXPAND_SERVERS[@]}
    do
        ssh -i ${ssh_key} root@$host "rm -rf /etc/yum.repos.d/*"
        scp -i ${ssh_key} /etc/yum.repos.d/*  root@$host:/etc/yum.repos.d/
        ssh -i ${ssh_key} root@$host "yum clean all && yum makecache"
    done
}

# hosts file creation
function hosts_create_scp()
{
    if ! grep -q controller /etc/hosts;
    then
        echo "$CONTROLLER_SERVERS controller" >> /etc/hosts
    fi

    #add compute host to hosts
    IFS=","
    for host in ${COMPUTE_SERVERS[@]}
    do
        if [ ${CONTROLLER_SERVERS} != ${host} ];
        then
            name=`echo $host | sed 's/\./-/g'`
            if ! grep -q "$host compute-$name" /etc/hosts;
            then
                echo "$host compute-$name" >> /etc/hosts
            fi
        fi
    done
    echo "Hosts file create complete.         [done]"

    #copy hosts to compute
    for host in ${COMPUTE_SERVERS[@]}
    do
        if [ ${CONTROLLER_SERVERS} != ${host} ];
        then
            ssh -i ${ssh_key} root@$host "rm -rf /etc/hosts"
            scp -i ${ssh_key} /etc/hosts  root@$host:/etc/
        fi
    done
    echo "Hosts file send complete.           [done]"
}

function expand_hosts_create_scp()
{
    #add expand host to hosts
    IFS=","
    for host in ${EXPAND_SERVERS[@]}
    do
        name=`echo $host | sed 's/\./-/g'`
        if ! grep -q "$host compute-$name" /etc/hosts;
        then
            echo "$host compute-$name" >> /etc/hosts
        fi
    done
    echo "Hosts file create complete.         [done]"

    #copy hosts to compute
    for host in ${EXPAND_SERVERS[@]}
    do
        ssh -i ${ssh_key} root@$host "rm -rf /etc/hosts"
        scp -i ${ssh_key} /etc/hosts  root@$host:/etc/
    done
    echo "Hosts file send complete.           [done]"
}


# hostname
function hostname_prepare()
{
    host_name=`hostname`
    if [ "$host_name" != "controller" ]; then
        echo controller > /etc/hostname
        hostname -F /etc/hostname
    fi
    echo "Controller hostname changed.        [done]"

    #change compute hostname
    IFS=","
    for host in ${COMPUTE_SERVERS[@]}
    do
        if [ ${CONTROLLER_SERVERS} != ${host} ];
        then
            name=`echo $host | sed 's/\./-/g'`
            ssh -i ${ssh_key} root@$host "echo compute-$name > /etc/hostname && hostname -F /etc/hostname"
        fi
    done
    echo "Compute hostname changed.           [done]"
}
function expand_hostname_prepare()
{
    #change compute hostname
    IFS=","
    for host in ${EXPAND_SERVERS[@]}
    do
        name=`echo $host | sed 's/\./-/g'`
        ssh -i ${ssh_key} root@$host "echo compute-$name > /etc/hostname && hostname -F /etc/hostname"
    done
    echo "Expand hostname changed.           [done]"
}

# create answer.txt
function answer_file()
{
    sed -i "s/^CONFIG_CONTROLLER_HOST=.*$/CONFIG_CONTROLLER_HOST=${CONTROLLER_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_NETWORK_HOSTS=.*$/CONFIG_NETWORK_HOSTS=${CONTROLLER_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_STORAGE_HOST=.*$/CONFIG_STORAGE_HOST=${CONTROLLER_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_AMQP_HOST=.*$/CONFIG_AMQP_HOST=${CONTROLLER_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_MARIADB_HOST=.*$/CONFIG_MARIADB_HOST=${CONTROLLER_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_KEYSTONE_LDAP_URL=.*$/CONFIG_KEYSTONE_LDAP_URL=ldap:\/\/${CONTROLLER_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_REDIS_MASTER_HOST.*$/CONFIG_REDIS_MASTER_HOST=${CONTROLLER_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_MONGODB_HOST=.*$/CONFIG_MONGODB_HOST=${CONTROLLER_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_COMPUTE_HOSTS=.*$/CONFIG_COMPUTE_HOSTS=${COMPUTE_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^Controller_IP.*$/$CONTROLLER_SERVERS/g" /root/ecloud/answer.txt
    echo "answer file create.                 [done]"
}
function network()
{
    sed -i "s/^.*security_group_api.*$/security_group_api=nova/g" /etc/nova/nova.conf
    sed -i "s/^.*firewall_driver.*$/firewall_driver=nova.virt.firewall.NoopFirewallDriver/g" /etc/nova/nova.conf

    sed -i "s/^.*enable_security_group.*$/enable_security_group = False/g" /etc/neutron/plugins/ml2/ml2_conf.ini 

    sed -i "s/^.*firewall_driver.*$/firewall_driver=neutron.agent.firewall.NoopFirewallDriver/g" /etc/neutron/plugins/ml2/ml2_conf.ini 
    sed -i "s/^.*enable_security_group.*$/enable_security_group = False/g" /etc/neutron/plugins/ml2/ml2_conf.ini 

    /bin/systemctl restart  openstack-nova-api.service
    /bin/systemctl restart  openstack-nova-compute.service
    /bin/systemctl restart  openstack-nova-compute.service
    /bin/systemctl restart  neutron-openvswitch-agent.service
    /bin/systemctl restart  neutron-server.service
    /bin/systemctl restart  neutron-openvswitch-agent.service


}

# to check the host ip address
function ip_check()
{
    IFS="," 
    for host in $1
    do
        IFS="."
        i=0
        for host_ip in ${host}
        do
            ((i++))
            if [ ${host_ip} -ge 0 ]&&[ ${host_ip} -le 254 ];
            then
                continue
            else
                exit 1
            fi
        done
        IFS=","
        if [ $i -ne 4 ]; then
            echo Invilid Host IP address : $host
        exit
        fi
    done
    echo "$host check complete.                [done]"
}

echo "Controller Node: ${CONTROLLER_SERVERS}"
echo "Compute Node: ${COMPUTE_SERVERS}"

if [ ${EXPAND_SERVERS} != "NULL" ];
then 
    echo "Expand Node : ${EXPAND_SERVERS}"
fi

if [ ${EXPAND_SERVERS} == "NULL" ];
then
    ip_check ${CONTROLLER_SERVERS}  | grep done
    ip_check ${COMPUTE_SERVERS}     | grep done
    ecloud_pre                      | grep done
    controller_ssh_key              | grep done
    compute_ssh_key                 | grep done
    port=`lsof -i:9001 | awk 'NR==2{print $2}'`
    kill -9 $port
    cd /root/ecloud/repo && nohup python -m SimpleHTTPServer ${Port} &
    controller_repo_prepare         | grep done
    compute_repo_prepare            | grep done
    hosts_create_scp                | grep done
    hostname_prepare                | grep done
    answer_file                     | grep done

    packstack --answer-file=/root/ecloud/answer.txt
    network                         | grep done

#   controller_repo_recover 
#   compute_repo_recover ${COMPUTE_SERVERS} | grep done
else
#Expand mode
    ip_check ${EXPAND_SERVERS}      | grep done
    ecloud_pre                      | grep done
    expand_ssh_key                  | grep done
    port=`lsof -i:9001 | awk 'NR==2{print $2}'`
    kill -9 $port
    cd /root/ecloud/repo && nohup python -m SimpleHTTPServer ${Port} &
    controller_repo_prepare         | grep done
    expand_repo_prepare             | grep done
    expand_hostname_prepare         | grep done
    expand_hosts_create_scp         | grep done
    answer_file                     | grep done

    sed -i "s/^EXCLUDE_SERVERS=.*$/EXCLUDE_SERVERS=${COMPUTE_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^CONFIG_COMPUTE_HOSTS=.*/&,${EXPAND_SERVERS}/g" /root/ecloud/answer.txt
    sed -i "s/^COMPUTE_SERVERS.*/&,${EXPAND_SERVERS}/g" /root/ecloud.cfg
    sed -i "s/^EXPAND_SERVERS.*/EXPAND_SERVERS=NULL/g" /root/ecloud.cfg

    packstack --answer-file=/root/ecloud/answer.txt
    network                         | grep done
fi
