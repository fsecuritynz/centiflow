# Centiflow
An easy-to-deploy script of Elastiflow for Centos7 Linux


# Based off the good work
https://medium.com/@ronaldbartels/a-guide-to-installing-elastiflow-53c915250df8
https://github.com/robcowart/elastiflow/blob/master/INSTALL.md


# Minimum Hardware Requirements for small deployments
- 4x Cores of a relatively modern CPU
- 8 GB of RAM
- 1 TB of storage


# Recommended (strongly) Hardware Requirements
- 8x Cores Xeon (or equivalent)
- 16-32 GB of RAM
- 4 TB of storage (RAID 1+0)

# Installation
login as root
cd /opt
wget https://raw.githubusercontent.com/fsecuritynz/centiflow/main/centiflow.sh
chmod +x centiflow.sh
sudo sh centiflow.sh
profit

# Default Configuration
- IP = "hostname -I"
- Web Interface = http://your-ip:5601
- Netflow Listen = UDP/2055 your-ip

