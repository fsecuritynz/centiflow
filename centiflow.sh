#!/bin/bash
clear

# USEFUL GUIDES
# https://medium.com/@ronaldbartels/a-guide-to-installing-elastiflow-53c915250df8
# https://github.com/robcowart/elastiflow/blob/master/INSTALL.md


# Checking whether user has enough permission to run this script
sudo -n true
if [ $? -ne 0 ]
    then
        echo "This script requires user to have passwordless sudo access"
        exit
fi

dependency_check_rpm() {
    java -version
    if [ $? -ne 0 ]
        then
            #Installing Java 8 if it's not installed
            sudo yum install java-1.8.0-openjdk -y
        # Checking if java installed is less than version 8. If yes, installing Java 8. As logstash & Elasticsearch require Java 8 or later.
        elif [ "`java -version 2> /tmp/version && awk '/version/ { gsub(/"/, "", $NF); print ( $NF < 1.8 ) ? "YES" : "NO" }' /tmp/version`" == "YES" ]
            then
                sudo yum install jre-1.8.0-openjdk -y
    fi
}

rpm_elk() {
    #Installing wget.
    sudo yum install wget -y
    #Installing tcpdump
    sudo yum install tcpdump -y
    # Downloading rpm package of logstash
    sudo wget --directory-prefix=/opt/ https://artifacts.elastic.co/downloads/logstash/logstash-7.8.1.rpm
    # Install logstash rpm package
    sudo rpm -ivh /opt/logstash*.rpm
    # Downloading rpm package of elasticsearch
    sudo wget --directory-prefix=/opt/ https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.8.1-x86_64.rpm
    # Install rpm package of elasticsearch
    sudo rpm -ivh /opt/elasticsearch*.rpm
    # Download kibana tarball in /opt
    sudo wget --directory-prefix=/opt/ https://artifacts.elastic.co/downloads/kibana/kibana-7.8.1-x86_64.rpm
    # Extracting kibana tarball
    sudo rpm -ivh /opt/kibana*.rpm
    # Starting The Services
    sudo systemctl enable elasticsearch
    sudo systemctl start elasticsearch
    sudo systemctl enable kibana
    sudo systemctl start kibana

# FIREWALLD + SELINUX CONFIGURATION
    sudo firewall-cmd --add-port=5601/tcp
    sudo firewall-cmd --add-port=2055/udp
    sudo firewall-cmd --runtime-to-permanent
    systemctl restart firewalld
    echo "Enabling sebool selinux"
    setsebool -P httpd_can_network_connect  on

# LISTEN ON LOCAL-IP FOR KIBANA
    localip=$(hostname -I)
    sed -i "/#server.host: \"localhost\"/c\server.host: $localip" /etc/kibana/kibana.yml 
    systemctl restart kibana

# INCREASE BUCKETS IN ELASTISEARCH
   echo "indices.query.bool.max_clause_count: 8192" >> /etc/elasticsearch/elasticsearch.yml
   echo "search.max_buckets: 250000" >> /etc/elasticsearch/elasticsearch.yml

# INSTALL GIT AND CLONE THE ELASTIFLOW REPO + ENABLE BETTER PROCESSING OF UDP PACKETS IN LINUX
   yum -y install git
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
   echo "Go to http://$localip:5601"
   echo "Navigate to KIBANA >> INDEX PATTERNS"
   echo "Add \"elastiflow\*\" into Index Pattern"
   echo "Click \"Next Step\""
   echo ""
   echo "Download the following to your desktop: https://github.com/robcowart/elastiflow/blob/master/kibana/elastiflow.kibana.7.8.x.ndjson"
   echo "On ELK Navitage to \"Kibana >> Saved Objects \" and import the elastiflow.kibana.7.8.x.ndjson file"
   echo "Your dashbaord is now ready"
   echo ""
   echo "You can ingest flow data on udp/2055"
   echo "#######################################################"

}

# Installing ELK Stack
if [ "$(grep -Ei 'debian|buntu|mint' /etc/*release)" ]
    then
        echo " ####################################################################"
        echo " This is a Debian based system and is not supported"
        echo " ####################################################################"

elif [ "$(grep -Ei 'fedora|redhat|centos' /etc/*release)" ]
    then
        echo " ####################################################################"
        echo "This is a RHEL/CENTOS/FEDORA System"
        echo "Installing ELK Stack + Elastiflow"
        echo "This is tested to work with Juniper SRX"
        echo ""
        echo "Relevant SRX Config:"
       	echo "set forwarding-options sampling input rate 100"
       	echo "set forwarding-options sampling input run-length 0"
       	echo "set forwarding-options sampling family inet output flow-server <<this-server-ip>> port 2055"
       	echo "set forwarding-options sampling family inet output flow-server <<this-server-ip>> source-address <<srx-srouce-ip>>"
       	echo "set forwarding-options sampling family inet output flow-server <<this-server-ip>> version 5"
       	echo "set forwarding-options sampling family inet output inline-jflow source-address <<srx-srouce-ip>>"
       	echo "set interfaces irb unit 10 family inet sampling input"
       	echo "set interfaces irb unit 10 family inet sampling output"
        echo ""
        echo " ####################################################################"
        echo " "
        echo "installing..."
        sleep 5
        dependency_check_rpm
        rpm_elk
else
    echo "This script doesn't support ELK installation on this OS."
fi
