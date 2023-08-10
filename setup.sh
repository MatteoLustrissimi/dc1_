#!/bin/bash

# exit when any command fails
set -e

# keep track of the last executed command
trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
# echo an error message before exiting
trap 'echo "\"${last_command}\" command filed with exit code $?."' EXIT

debian_check
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
DEBIAN_FRONTEND=noninteractive apt-get install -y samba smbclient winbind krb5-user krb5-config libpam-krb5 libpam-winbind libnss-winbind acl net-tools
systemctl disable --now samba-ad-dc.service smbd.service nmbd.service winbind.service
unlink /etc/samba/smb.conf
unlink /etc/krb5.conf

samba-tool domain info dc1 || {
  samba-tool domain provision --realm HSSERVICE.LAN \
                                     --domain HSSERVICE \
                                     --server-role dc \
                                     --dns-backend BIND9_DLZ \
                                     --adminpass CambiaLaPassword123 \
                                     --use-rfc2307 \
                                     --option="interfaces=lo enX0" \
                                     --option="bind interfaces only=yes"
  }
cp /var/lib/samba/private/krb5.conf /etc/krb5.conf
ln -s /var/lib/samba/private/secrets.keytab /etc/krb5.keytab

mkdir -p /var/lib/samba/ntp_signd && chgrp _chrony /var/lib/samba/ntp_signd && chmod 750 /var/lib/samba/ntp_signd
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
grep -q 'include "/etc/bind/domain-enabled.conf";' /etc/bind/named.conf || echo 'include "/etc/bind/domain-enabled.conf";' >> /etc/bind./named.conf
test -d /etc/bind/domain-enabled || mkdir /etc/bind/domain-enabled
grep -q 'tkey-gssapi-keytab' /etc/bind/named.conf.options  || sed  '/listen-on-v6 {/a\ \ \ \ \ \ \ \ tkey-gssapi-keytab "/var/lib/samba/bind-dns/dns.keytab";' -i /etc/bind/named.conf.options 
grep -q 'OPTIONS="-u[^*]*-4"' /etc/default/named  ||  sed -e '/OPTIONS/ s/"$/ -4"/' -i /etc/default/named

systemctl enable --now named
systemctl unmask samba-ad-dc.service
systemctl enable --now samba-ad-dc.service

apt install isc-dhcp-server -y
## samba-tool user create dhcpduser --description="Unprivileged user for TSIG-GSSAPI DNS updates via ISC DHCP server" --random-password
## samba-tool user setexpiry dhcpduser --noexpiry
## samba-tool group addmembers DnsAdmins dhcpduser
## samba-tool domain exportkeytab --principal=dhcpduser@DC1.HSSERVICE.LAN /etc/dhcpduser.keytab
## chown root:root /etc/dhcpduser.keytab
## chmod 400 /etc/dhcpduser.keytab

wget https://github.com/MatteoLustrissimi/dc1_/raw/main/dhcp-dyndns.sh -O /usr/local/bin/dhcp-dyndns.sh && chmod 775 /usr/local/bin/dhcp-dyndns.sh 
cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.orig
grep -q omapi /etc/dhcp/dhcpd.conf || echo -e "\nomapi-port 7911;\nomapi-key omapi_key;\n $(tsig-keygen -a hmac-md5 omapi_key)" >> /etc/dhcp/dhcpd.conf


## acl trusted { 192.168.223.0/24; 192.168.218.0/24; };
## acl dnsservers { 192.168.223.5; 192.168.218.6; };
## Options {
##         directory "/var/cache/bind";
## 
##         // If there is a firewall between you and nameservers you want
##         // to talk to, you may need to fix the firewall to allow multiple
##         // ports to talk.  See http://www.kb.cert.org/vuls/id/800113
## 
##         // If your ISP provided one or more IP addresses for stable 
##         // nameservers, you probably want to use them as forwarders.  
##         // Uncomment the following block, and insert the addresses replacing 
##         // the all-0's placeholder.
## 
##          forwarders {
##                 192.168.212.22;
##          };
##         allow-query { trusted; };
##         recursion yes;
##         allow-recursion { trusted; };
##         allow-transfer { dnsservers; };
## 
##         //========================================================================
##         // If BIND logs error messages about the root key being expired,
##         // you will need to update your keys.  See https://www.isc.org/bind-keys
##         //========================================================================
##         dnssec-validation auto;
## 
##         listen-on-v6 { any; };
##         tkey-gssapi-keytab "/var/lib/samba/bind-dns/dns.keytab";
## };



#add to /etc/bind/named.conf:
#
#include "/etc/bind/domain-enabled.conf";
#
#make dir:
#
## mkdir /etc/bind/domain-enabled/
#
#scripts:
#
#cat <<EOF >>/etc/bind/domain-enabled.conf
#zone "$1" {
#        type master;
#        file "/etc/bind/domain-enabled/$1.db";
#};
#EOF
#cat <<EOF >/etc/bind/domain-enabled/$1.db
#\$TTL   604800
#@       IN      SOA     ns1.$1. root.localhost. (
#                              2         ; Serial
#                         604800         ; Refresh
#                          86400         ; Retry
#                        2419200         ; Expire
#                         604800 )       ; Negative Cache TTL
#;
#@       IN      NS      ns1.$1.
#@       IN      A       $2
#ns1     IN      A       $2
#EOF
#rndc reload
#
#run:
#
#add-domain examle.com 127.0.0.1



# ddns-confgen -k dc1.hsservice.lan
