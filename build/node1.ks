# Exam lab: node1, installed once. Its disk becomes node1-golden.qcow2, the backing file of node1.qcow2.
# The lab-only root password is not in git: rebuild-nodes.sh fills in the placeholder from a local file

# Installer
text
eula --agreed
poweroff

# Locale
lang en_US.UTF-8
keyboard us
timezone Europe/Zagreb --utc

# Network: by name. A MAC here makes Anaconda rename the NIC to ksdev0 (ifname=ksdev0:<MAC>).
network --device=enp1s0 --bootproto=static --ip=172.25.250.11 --netmask=255.255.255.0 --gateway=172.25.250.1 --nameserver=172.25.250.1 --hostname=node1.lab.example.com

# Users
rootpw --plaintext @ROOT_PASSWORD@
sshkey --username=root "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ5aKHnd0Dejhp4dB/BkdaRgBKpGyyJDM10wBWxbxDIK lab@desktop"

# Security
selinux --enforcing
firewall --enabled --service=ssh

# Disk: only vda. vdb and vdc stay empty for storage tasks.
ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
autopart --type=lvm --nohome

# Software
%packages
@^server-product-environment
qemu-guest-agent
%end
