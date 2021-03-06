#!/bin/bash
clear


# Checking whether user has enough permission to run this script
sw_check() {
# Check for RHEL variant environment
if [ "$(grep "^ID=" /etc/*release | grep -Eiv  'rocky|fedora|redhat|centos')" ]
    then
        echo "####################################################################"
        echo "RHEL/CENTOS/FEDORA/ROCKY System NOT Detected"
        echo "####################################################################"

elif [ "$(grep -Ei 'rocky|fedora|redhat|centos' /etc/*release)" ]
    then
	hw_check
        echo "####################################################################"
        echo "RHEL/CENTOS/FEDORA/ROCKY System Detected"
        echo "Installing ELK Stack"
        echo ""
        echo ""
        echo "####################################################################"
        echo " "
        echo "installing..."
        sleep 5
        dependency_check_rpm
        rpm_elk
else
    echo "This script doesn't support ELK installation on this OS."
fi
}


root_check() {
	sudo -n true
	if [ $? -ne 0 ]
		then
			echo "This script requires user to have passwordless sudo access"
			exit
		fi
}

hw_check() {
   totalram=$(grep MemTotal /proc/meminfo  | awk {'print $2'})
   if [ "$totalram" -lt "7800000" ]
        then
		echo "Not enough RAM, please assign a minimum of 8GB"
		exit
	else
		echo "Minimum RAM requirements met."
   fi
}



dependency_check_rpm() {
    java -version
    if [ $? -ne 0 ]
        then
	#Installing Java 8 if it's not installed
		sudo yum install java-1.8.0-openjdk -y
        # Checking if java installed is less than version 8. If yes, installing Java 8. As logstash & Elasticsearch require Java 8 or later.
        elif [ "`java -version 2> /tmp/version && awk '/version/ { gsub(/"/, "", $NF); print ( $NF < 1.8 ) ? "YES" : "NO" }' /tmp/version`" == "YES" ]
            then
		sudo yum install java-1.8.0-openjdk -y
    fi
}

rpm_elk() {

    # Downloading Elasticsearch rpm package
    cd /opt
    elasticdl=$(curl https://www.elastic.co/downloads/elasticsearch | grep -Eo "(http|https)://[a-zA-Z0-9./?=_%:-]*"  | grep x86_64.rpm$ | head -n 1)
    curl -O $elasticdl

    # Downloading Logstash rpm package
    logstashdl=$(curl https://www.elastic.co/downloads/logstash | grep -Eo "(http|https)://[a-zA-Z0-9./?=_%:-]*"  | grep x86_64.rpm$ | head -n 1)
    curl -O $logstashdl

    # Download Kibana rpm package
    kibanadl=$(curl https://www.elastic.co/downloads/kibana | grep -Eo "(http|https)://[a-zA-Z0-9./?=_%:-]*"  | grep x86_64.rpm$ | head -n 1)
    curl -O $kibanadl

    echo ""
    echo "#######################################################"
    ls -lah /opt | grep rpm | grep 'elastic\|logstash\|kibana'
    echo ""


    # Install rpm package of elasticsearch
    sudo rpm -ivh /opt/elasticsearch*.rpm
    # Install Logstash rpm package
    sudo rpm -ivh /opt/logstash*.rpm
    # Install kibana rpm package
    sudo rpm -ivh /opt/kibana*.rpm


    clear

    # Starting The Services
    sudo systemctl daemon-reload
    sudo systemctl enable elasticsearch
    sudo systemctl start elasticsearch
    sudo systemctl enable logstash
    sudo systemctl start logstash
    sudo systemctl enable kibana
    sudo systemctl start kibana


# FIREWALLD + SELINUX CONFIGURATION
    echo "Enabling Access on 5601/tcp - firewalld"
    sudo firewall-cmd --add-port=5601/tcp
    sudo firewall-cmd --add-port=2055/udp
    sudo firewall-cmd --runtime-to-permanent
    systemctl restart firewalld
    echo "Enabling sebool selinux httpd_can_network_connect"
    setsebool -P httpd_can_network_connect  on
    


# LISTEN ON LOCAL-IP FOR KIBANA
    localip=$(hostname -I | rev | cut -c 2-15 | rev)
    sed -i "/#server.host: \"localhost\"/c\server.host: $localip" /etc/kibana/kibana.yml 
    systemctl restart kibana

# INCREASE BUCKETS IN ELASTISEARCH
   echo "indices.query.bool.max_clause_count: 8192" >> /etc/elasticsearch/elasticsearch.yml
   echo "search.max_buckets: 250000" >> /etc/elasticsearch/elasticsearch.yml

# ELASTIFLOW
    cd /opt
    git clone https://github.com/robcowart/elastiflow.git
    cp /opt/elastiflow/sysctl.d/87-elastiflow.conf /etc/sysctl.d

# ASSIGN 4GB RAM TO JAVA
   sed -i "/-Xms1g/c\-Xms4g" /etc/logstash/jvm.options
   sed -i "/-Xmx1g/c\-Xmx4g" /etc/logstash/jvm.options

# UPDATED REQUIRED PLUGINS
   /usr/share/logstash/bin/logstash-plugin install logstash-codec-sflow
   /usr/share/logstash/bin/logstash-plugin update logstash-codec-netflow
   /usr/share/logstash/bin/logstash-plugin update logstash-input-udp
   /usr/share/logstash/bin/logstash-plugin update logstash-input-tcp
   /usr/share/logstash/bin/logstash-plugin update logstash-filter-dns
   /usr/share/logstash/bin/logstash-plugin update logstash-filter-geoip
   /usr/share/logstash/bin/logstash-plugin update logstash-filter-translate


# ENABLE ELASTIFLOW CONFIG INSIDE LOGSTASH
   cp -r /opt/elastiflow/logstash/elastiflow /etc/logstash/

# ENABLE PIPLINES
   echo "- pipeline.id: elastiflow" >> /etc/logstash/pipelines.yaml
   echo "  path.config: "/etc/logstash/elastiflow/conf.d/*.conf"" >> /etc/logstash/pipelines.yml

# SYSTEM'D-IFY LOGSTASH & ALLOW DNS LOOKUP OF NETFLOW TRAFFIC
   cp -R /opt/elastiflow/logstash.service.d /etc/systemd/system/
   mydns=$(grep nameserver /etc/resolv.conf | awk {'print $2'})
   sed -i "s/127.0.0.1/$mydns/g" /etc/logstash/elastiflow/conf.d/20_filter_20_netflow.logstash.conf
   sed -i "s/exporters/true/g" /etc/logstash/elastiflow/conf.d/20_filter_20_netflow.logstash.conf
   /usr/share/logstash/bin/system-install /etc/logstash/startup.options systemd
   sed -i "s/19/0/g" /etc/systemd/system/logstash.service
   sudo systemctl daemon-reload
   systemctl enable logstash 
   cp /opt/elastiflow/logstash.service.d/elastiflow.conf /etc/systemd/system/logstash.service.d/
   sed -i "s/127.0.0.1/$mydns/g" /etc/systemd/system/logstash.service.d/elastiflow.conf  
   sed -i "s/IP2HOST=false/IP2HOST=true/g" /etc/systemd/system/logstash.service.d/elastiflow.conf


# RESTART ALL ELK SERVICES
   systemctl restart elasticsearch
   systemctl restart logstash
   systemctl restart kibana

# CONFIGURATION INFORMATION + FINAL SETUP
   echo ""
   echo "#######################################################"
   echo "Go to http://$localip:5601/app/management/kibana/objects"
   echo ""
   echo "Download the following to your desktop: https://github.com/robcowart/elastiflow/blob/master/kibana/elastiflow.kibana.7.8.x.ndjson"
   echo " Import the JSON file"
   echo "Your dashbaords are now ready"
   echo ""
   echo "You can ingest netflow data on udp/2055"
   echo "#######################################################"
   exit
}


clear
#Installing tcpdump net-tools and curl
sudo yum install tcpdump net-tools curl git -y
sw_check
root_check
hw_check
dependency_check_rpm
rpm_elk
exit
