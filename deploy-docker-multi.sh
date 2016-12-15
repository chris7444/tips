#
# deploy a docker swarm with a external KV store
#
#    to be finished
#
IMAGE_COREOS="coreos:CoreOS:Stable:latest"
IMAGE="Canonical:UbuntuServer:16.04-LTS:latest"
LOCATION="westeurope"
RG="RGkube"

VNET="vnet-kube"
VNETPREFIX="10.6.0.0/16"

CIDR="10.6.0.0/16"
SUBNET="subnet-kube"
FIP="fip-kube"


YAML="cloud-config.yml"
CERT="azure.pub"

# we only deploy docker no worker needed
NB_WORKERS=1
NSG="nsg-kube"

MASTER="master"
MASTER_SIZE="Basic_A1"

WORKER="worker"
WORKER_SIZE="Basic_A1"

YAMLETCD="cloud-config-etcd.yml"
YAMLWORKER="cloud-config-worker.yml"

WORKERS=0

cat <<EOF >$YAMLETCD
#cloud-config

packages:
  - docker.io
coreos:
  etcd2:
    name: etcdserver
    initial-cluster: etcdserver=http://\$private_ipv4:2380
    initial-advertise-peer-urls: http://\$private_ipv4:2380
    advertise-client-urls: http://\$private_ipv4:2379
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
    listen-peer-urls: http://\$private_ipv4:2380
  units:
    - name: etcd2.service
      command: start
EOF


#
# delete evrything from the previous run
#
    azure group delete -q $RG

#
# Ready to go
#
	azure group create $RG $LOCATION
	azure network vnet create --address-prefixes $VNETPREFIX $RG $VNET $LOCATION
	azure network vnet subnet create $RG $VNET $SUBNET $CIDR

        #
        # first VM is created with a FIP
        #
        azure vm create  \
            --custom-data=$YAMLETCD \
            --disable-boot-diagnostics \
            --vm-size=$MASTER_SIZE \
            --admin-username core --ssh-publickey-file $CERT \
            --nic-name nic-$MASTER  --vnet-name $VNET --vnet-subnet-name $SUBNET \
            --public-ip-name $FIP --public-ip-domain-name $FIP \
            --image-urn $IMAGE_COREOS \
            $RG vm-${MASTER} $LOCATION Linux

        sleep 60
        #
        # Other VMS created without a FIP
        #
	i=1
	while [ $i -le $NB_WORKERS ] 
        do
            azure vm create  \
                --disable-boot-diagnostics \
                --vm-size=$WORKER_SIZE \
                --admin-username core --ssh-publickey-file $CERT \
                --nic-name nic-${WORKER}$i   --vnet-name $VNET --vnet-subnet-name $SUBNET \
                --image-urn $IMAGE \
                $RG vm-${WORKER}$i $LOCATION Linux
            ((i++))
        done
#
# Create NSG and assign to master VM
#
#azure network nsg create $RG $NSG westeurope
#azure  network nsg rule create --protocol tcp --destination-port-range 22          --access allow --direction inbound $RG $NSG  ssh    100
#azure  network nsg rule create --protocol tcp --destination-port-range 31900-31999 --access allow --direction inbound $RG $NSG  myapps 110
#azure  network nic set --network-security-group-name $NSG $RG nic-${MASTER}

#
# log something
#

        cluster_fip=$(azure network public-ip list $RG | awk "/$FIP/ {print \$8  \" \" \$10}")
        echo "Cluster FIP at ${cluster_fip}"
        priv_ip=`azure network nic show $RG nic-${MASTER} | awk -F":" '/Private IP address/ { print $3}'`
        echo "Private IP VM ${MASTER} ${priv_ip}"

        i=1
        while [ $i -le $NB_WORKERS ]
        do
            priv_ip=`azure network nic show $RG nic-${WORKER}$i | awk -F":" '/Private IP address/ { print $3}'`
            echo "Private IP VM ${WORKER}${i} ${priv_ip}"
            ((i++))
        done


