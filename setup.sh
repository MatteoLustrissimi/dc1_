#!/bin/bash
grep -q bullseye /etc/os-release && {
  apt update && DEBIAN_FRONTEND=noninteractive apt upgrade -y
  apt --purge autoremove -y
  sed 's/bullseye/bookworm/g' -i /etc/apt/sources.list
  apt update && DEBIAN_FRONTEND=noninteractive apt upgrade --without-new-pkgs -y
  DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
  apt autoremove --purge -y
  sed 's/eth/enX/g' -i /etc/network/interfaces # only on xcp-ng
  hostnamectl hostname dc1.hsservice.lan
  reboot
}

# VARIABLES:



# DC SETUP:
apt install -y chrony && systemctl disable --now chrony
apt install -y bind9 bind9utils && bind9-doc systemctl disable --now bind
DEBIAN_FRONTEND=noninteractive apt-get install -y samba smbclient winbind krb5-user krb5-config
systemctl disable --now samba-ad-dc.service smbd.service nmbd.service winbind.service
unlink /etc/samba/smb.conf
unlink /etc/krb5.conf

samba-tool domain provision --realm HSSERVICE.LAN \
                                   --domain HSSERVICE \
                                   --server-role dc \
                                   --dns-backend BIND9_DLZ \
                                   --adminpass CambiaLaPassword123 \
                                   --use-rfc2307 \
                                   --option="interfaces=lo enX0" \
                                   --option="bind interfaces only=yes"

cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
ln -s /var/lib/samba/private/secrets.keytab /etc/krb5.keytab

mkdir /var/lib/samba/ntp_signd && chgrp _chrony /var/lib/samba/ntp_signd && chmod 750 /var/lib/samba/ntp_signd
sed -i -e "/\# Use Debian vendor zone./,+2d" /etc/chrony/chrony.con

cat << EOF ->/etc/chrony/sources.d/debian-pool.sources
pool 0.debian.pool.ntp.org iburst
pool 1.debian.pool.ntp.org iburst
pool 2.debian.pool.ntp.org iburst
pool 3.debian.pool.ntp.org iburst
EOF

cat << EOF ->/etc/chrony/conf.d/server.conf
bindaddress 192.168.223.5
allow 192.168.223.1/24
ntpsigndsocket  /var/lib/samba/ntp_signd
EOF

cat << EOF ->/etc/chrony/conf.d/cmd.conf
bindcmdaddress /var/run/chrony/chronyd.sock
cmdport 0
EOF

systemctl enable --now  chrony

grep -q 'include "/var/lib/samba/bind-dns/named.conf";' /etc/bind/named.conf || echo 'include "/var/lib/samba/bind-dns/named.conf";' >> /etc/bind/named.conf
grep -q 'tkey-gssapi-keytab' /etc/bind/named.conf.options  || sed  '/listen-on-v6 {/a\ \ \ \ \ \ \ \ tkey-gssapi-keytab "/var/lib/samba/bind-dns/dns.keytab";' -i /etc/bind/named.conf.options 

systemctl enable --now named
systemctl unmask samba-ad-dc.service
systemctl enable --now samba-ad-dc.service

apt install isc-dhcp-server -y
samba-tool user create dhcpduser --description="Unprivileged user for TSIG-GSSAPI DNS updates via ISC DHCP server" --random-password
samba-tool user setexpiry dhcpduser --noexpiry
samba-tool group addmembers DnsAdmins dhcpduser
samba-tool domain exportkeytab --principal=dhcpduser@DC1.HSSERVICE.LAN /etc/dhcpduser.keytab
chown root:root /etc/dhcpduser.keytab
chmod 400 /etc/dhcpduser.keytab

wget https://github.com/MatteoLustrissimi/dc1_/raw/main/dhcp-dyndns.sh -O /usr/local/bin/dhcp-dyndns.sh && chmod 775 /usr/local/bin/dhcp-dyndns.sh 
cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.orig
grep -q omapi /etc/dhcp/dhcpd.conf || echo -e "\nomapi-port 7911;\nomapi-key omapi_key;\n $(tsig-keygen -a hmac-md5 omapi_key)" >> /etc/dhcp/dhcpd.conf
