#!/bin/bash
grep bullseye /etc/os-release && {
  sed 's/bullseye/bookworm/g' -i /etc/apt/source.list
}
