#!/bin/bash
grep -q bullseye /etc/os-release && {
  sed 's/bullseye/bookworm/g' -i /etc/apt/sources.list
}
