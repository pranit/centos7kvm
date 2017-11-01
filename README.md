
Automation of KVM installation, configuration and test vm creation

Assumptions:
1) Host machine is configured with IP address,subnetmask and default gateway
2) Host machine has properly configured yum repository - local or remote 
3) Script make assumption that you have copy of centos/rhel iso on /tmp on Host machine
4) You have other means of access than SSH to the host (read KVM) 

What it does:
1) Installs neccesary packages for KVM 
2) Configures Linux Bridge
3) Create qcow2 disk in /opt
4) Create domain vm and automates the installation of provided ISO with kickstart 

What it doesn't:
1) anything not written in 'what it does'
