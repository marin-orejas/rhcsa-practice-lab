# Exam lab: infra server (repos, NFS, NTP, Flatpak) for node1 and node2
# The lab-only root password is not in git: fill in the placeholder from a local file before an install

# Installer
text
eula --agreed
poweroff

# Locale
lang en_US.UTF-8
keyboard us
timezone Europe/Zagreb --utc

# Network, by name (a MAC makes Anaconda rename the NIC to ksdev0): static on the exam network (no default route), DHCP on the NAT network for internet
network --device=enp1s0 --bootproto=static --ip=172.25.250.10 --netmask=255.255.255.0 --ipv6=fd00:fa::10/64 --nodefroute --hostname=infra.lab.example.com
network --device=enp2s0 --bootproto=dhcp

# Users
rootpw --plaintext @ROOT_PASSWORD@
sshkey --username=root "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ5aKHnd0Dejhp4dB/BkdaRgBKpGyyJDM10wBWxbxDIK lab@desktop"

# Security and services
selinux --enforcing
firewall --enabled --service=ssh,http,nfs,mountd,rpc-bind,ntp
services --enabled=httpd,nfs-server,chronyd

# Disk
ignoredisk --only-use=vda
zerombr
clearpart --all --initlabel --drives=vda
autopart --type=lvm --nohome
bootloader --append="console=ttyS0,115200"

# Software
%packages
@^minimal-environment
httpd
nfs-utils
chrony
flatpak
ostree
gnupg2
tar
qemu-guest-agent
%end

%post --log=/root/ks-post.log
# HTTP: the DVD (attached as a CD-ROM after the install) is the BaseOS and AppStream repo
mkdir -p /var/www/html/rhel10 /var/www/html/pub /var/www/html/flatpak
echo '/dev/sr0  /var/www/html/rhel10  iso9660  ro,nofail,context="system_u:object_r:httpd_sys_content_t:s0"  0 0' >> /etc/fstab

# NFS
mkdir -p /exports/shared
echo 'Exam lab NFS share on infra.' > /exports/shared/README
echo '/exports/shared  172.25.250.0/24(ro)' > /etc/exports.d/lab.exports

# NTP server for the exam network, also when the internet is down
printf '%s\n' '' '# Exam lab: serve time to the exam network' 'allow 172.25.250.0/24' 'local stratum 10' >> /etc/chrony.conf

restorecon -R /var/www/html /exports /etc/exports.d
%end
