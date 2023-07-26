#!/bin/bash
grep -q bullseye /etc/os-release && {
  apt update && apt upgrade -y
  apt --purge autoremove -y
  sed 's/bullseye/bookworm/g' -i /etc/apt/sources.list
  apt update && apt upgrade --without-new-pkgs -y
  apt full-upgrade -y
  apt autoremove --purge
  sed 's/eth/enX/g' -i /etc/network/interfaces # only on xcp-ng
}

# VARIABLES:



# DC SETUP:
apt install -y chrony && systemctl disable --now chrony
apt install -y bind9 && systemctl disable --now bind
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
