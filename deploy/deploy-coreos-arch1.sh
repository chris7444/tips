LOCATION="westeurope"
RG="RGcoreOS"

VNET="vnet-coreos"
VNETPREFIX="10.6.0.0/16"

CIDR="10.6.0.0/16"
SUBNET="subnet-coreos"
FIP="fip-coreos"


YAML="/tmp/cloud-config.yml"
CERT="azure.pub"

CLUSTER_SIZE=3

token=`curl -s -w "\n" "https://discovery.etcd.io/new?size=$CLUSTER_SIZE"`
cat <<EOF >$YAML
#cloud-config

coreos:
  etcd2:
    # generate a new token for each unique cluster from https://discovery.etcd.io/new?size=3
    # specify the initial size of your cluster with ?size=X
    discovery: $token
    # multi-region and multi-cloud deployments need to use \$public_ipv4
    advertise-client-urls: http://\$private_ipv4:2379
    initial-advertise-peer-urls: http://\$private_ipv4:2380
    listen-client-urls: http://0.0.0.0:2379
    listen-peer-urls: http://\$private_ipv4:2380
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
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

        # could not find how to assign the FIP to a NIC thus we create the FIP when we create the VM
        # azure network public-ip create $RG $FIP $LOCATION

        #
        # first VM is created with a FIP
        #
	i=1
        azure vm create --custom-data=$YAML \
            --disable-boot-diagnostics \
            --vm-size=Basic_A0 \
            --admin-username core --ssh-publickey-file $CERT \
            --nic-name nic-coreos$i   --vnet-name $VNET --vnet-subnet-name $SUBNET \
            --public-ip-name $FIP --public-ip-domain-name $FIP \
            --image-urn coreos:CoreOS:Stable:latest  \
            $RG vm-coreos$i $LOCATION Linux

        sleep 60
        #
        # Other VMS created without a FIP
        #
	((i++))
	while [ $i -le $CLUSTER_SIZE ] 
        do
            azure vm create --custom-data=$YAML \
                --disable-boot-diagnostics \
                --vm-size=Basic_A0 \
                --admin-username core --ssh-publickey-file $CERT \
                --nic-name nic-coreos$i   --vnet-name $VNET --vnet-subnet-name $SUBNET \
                --image-urn coreos:CoreOS:Stable:latest  \
                $RG vm-coreos$i $LOCATION Linux
            ((i++))
        done

