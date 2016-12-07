master_ip=10.244.62.4
proxy="yes"
echo proxy=$proxy
echo master_ip=$master_ip
#
# service file for docket if behina a proxy
#
docker_dropin=/tmp/http-proxy.conf
if [ $proxy = "yes" ]
then
    export http_proxy=http://web-proxy.ftc.hpecorp.net:8080
    export https_proxy=http://web-proxy.ftc.hpecorp.net:8080
    export no_proxy=localhost,127.0.0.1,$master_ip
fi

cat <<EOF >$docker_dropin
[Service]
Environment="HTTPS_PROXY=${https_proxy}/" "HTTP_PROXY=${http_proxy}/" "NO_PROXY=localhost,127.0.0.1,$master_ip"
EOF

echo Installing Google APT gpgp key
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg >/tmp/google.key
apt-key add /tmp/google.key

cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF

apt-get update
apt-get install -y docker.io
apt-get install -y kubelet kubeadm kubectl kubernetes-cni

#
# Configure Docket to use the PROXY
#
if [ $proxy = "yes" ]
then
    mkdir /etc/systemd/system/docker.service.d
    cp $docker_dropin /etc/systemd/system/docker.service.d/http-proxy.conf

    sudo systemctl daemon-reload
#    systemctl show --property=Environment docker
    echo "Restarting Docker to enable proxy"
    sleep 30
    sudo systemctl restart docker
fi

#kubeadm init --use-kubernetes-version v1.4.1 --api-advertise-addresses 10.244.62.4
#kubeadm init | tee kube-init.log

