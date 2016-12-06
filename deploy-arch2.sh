#
# Deploys one etcd machine, then 2 workers 
#    no discovery service required
#    FIP is on fisrt worker
#
LOCATION="westeurope"
RG="RGcoreOS"

VNET="vnet-coreos"
VNETPREFIX="10.6.0.0/16"

CIDR="10.6.0.0/16"
SUBNET="subnet-coreos"
FIP="fip-coreos"
FIPETCD="fip-etcdserver"
CERT="azure.pub"

YAMLETCD="cloud-config-etcd.yml"
YAMLWORKER="cloud-config-worker.yml"

WORKERS=2

cat <<EOF >$YAMLETCD
#cloud-config

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
        # Create ETCD standalone machine
        #
        azure vm create --custom-data=$YAMLETCD \
            --disable-boot-diagnostics \
            --vm-size=Basic_A0 \
            --admin-username core --ssh-publickey-file $CERT \
            --nic-name nic-etcdserver   --vnet-name $VNET --vnet-subnet-name $SUBNET \
            --image-urn coreos:CoreOS:Stable:latest  \
            $RG vm-etcdserver $LOCATION Linux

        etcdip=`azure network nic show $RG nic-etcdserver | grep "Private IP address" | awk -F ":" '{ print $3}'`
        etcdip=`echo $etcdip`

#
# Sleep 60 seconds
#
        echo "ETCD at $etcdip, sleeping 60 seconds to let ETCD initialization complete"
        sleep 60

#
# Create Cloud COnfig for workers, it specified the IP Address of the ETCD server and configures the workers as ETCD proxies, no discovery needed
#
cat <<EOF >$YAMLWORKER
#cloud-config

coreos:
  etcd2:
    proxy: on
    initial-cluster: etcdserver=http://$etcdip:2380
    listen-client-urls: http://0.0.0.0:2379,http://0.0.0.0:4001
  units:
    - name: etcd2.service
      command: start
    - name: fleet.service
      command: start
EOF


        #
        # Create the first worker with a FIP.
        #
	i=1
        azure vm create --custom-data=$YAMLWORKER \
            --disable-boot-diagnostics \
            --vm-size=Basic_A0 \
            --admin-username core --ssh-publickey-file $CERT \
            --nic-name nic-coreos$i   --vnet-name $VNET --vnet-subnet-name $SUBNET \
            --public-ip-name $FIP --public-ip-domain-name $FIP \
            --image-urn coreos:CoreOS:Stable:latest  \
            $RG vm-coreos$i $LOCATION Linux

        #
        # Create additional workers without a FIP
        # 
        ((i++))
	while [ $i -le $WORKERS ] 
        do
            azure vm create --custom-data=$YAMLWORKER \
                --disable-boot-diagnostics \
                --vm-size=Basic_A0 \
                --admin-username core --ssh-publickey-file $CERT \
                --nic-name nic-coreos$i   --vnet-name $VNET --vnet-subnet-name $SUBNET \
                --image-urn coreos:CoreOS:Stable:latest  \
                $RG vm-coreos$i $LOCATION Linux
            ((i++))
        done

