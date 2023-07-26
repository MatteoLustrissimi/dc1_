#!/bin/bash
grep -q bullseye /etc/os-release && {
  apt update && apt upgrade -y
  apt --purge autoremove -y
  sed 's/bullseye/bookworm/g' -i /etc/apt/sources.list
  apt update && apt upgrade --without-new-pkgs
  apt full-upgrade -y
  sed 's/eth/enX/g' -i /etc/network/interfaces
}
echo DONE
