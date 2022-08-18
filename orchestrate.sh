#!/bin/bash

args=`getopt :iu $*`
set -- $args
for i
do
  case "$i" in
        -i)
          shift;
          echo "install interruptible workload as systemd service";

          sudo chmod +x /usr/share/worker-0.1.0/interruptible-workload \
              && cp /usr/share/worker-0.1.0/interruptible-workload.service /lib/systemd/system/interruptible-workload.service \
              && sudo systemctl enable interruptible-workload \
              && sudo systemctl start interruptible-workload \
              && sudo systemctl status interruptible-workload;;
        -u)
          shift;
          echo "uninstall interruptible workload";

          sudo systemctl stop interruptible-workload \
            && sudo systemctl disable interruptible-workload \
            && sudo rm /lib/systemd/system/interruptible-workload.service \
            && sudo rm -rf /usr/share/worker-0.1.0;;
  esac
done
