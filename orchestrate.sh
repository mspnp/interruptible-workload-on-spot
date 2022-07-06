SA_WORKER_URI=

sudo apt-get install -y dotnet-runtime-6.0 \
    && wget -O worker-0.1.0.tar.gz $SA_WORKER_URI --no-check-certificate \
    && mkdir -p /usr/share/worker-0.1.0 \
    && tar -oxzf worker-0.1.0.tar.gz -C /usr/share/worker-0.1.0 \
    && rm worker-0.1.0.tar.gz \
    && /usr/share/worker-0.1.0/interruptible-workload
