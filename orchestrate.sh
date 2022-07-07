#!/bin/bash

args=`getopt :iu $*`
set -- $args
for i
do
  case "$i" in
        -i)
          shift;
          echo "install interruptible workload as systemd service";

          SA_WORKER_URI=

          sudo apt-get install -y dotnet-runtime-6.0 \
              && wget -O worker-0.1.0.tar.gz $SA_WORKER_URI --no-check-certificate \
              && mkdir -p /usr/share/worker-0.1.0 \
              && tar -oxzf worker-0.1.0.tar.gz -C /usr/share/worker-0.1.0 \
              && rm worker-0.1.0.tar.gz \
              && sudo chmod +x /usr/share/worker-0.1.0/interruptible-workload \
              && cp /usr/share/worker-0.1.0/interruptible-workload.service /lib/systemd/system/interruptible-workload.service \
              && sudo systemctl enable interruptible-workload \
              && sudo systemctl start interruptible-workload \
              && sudo systemctl status interruptible-workload;;
        -u)
          shift;
          echo "uninstall interruptible workload";

          sudo systemctl stop interruptible-workload \
              && rm -rf /usr/share/worker-0.1.0;;
  esac
done
