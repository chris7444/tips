#
# Deploy a docker swarm on azure
#


# we always deploy one master, the number of workers can be changed
NB_WORKERS=2

#
# we deploy in a resource group, it is easier to delete all resources when we want to release the resources
#
RG="docker"

#
# Deploy in West Europe
#
LOCATION="westeurope"

#
# Resources
#
IMAGE="Canonical:UbuntuServer:16.04-LTS:latest"

VNET="vnet-${RG}"
VNETPREFIX="10.6.0.0/16"

SUBNET="subnet-${RG}"
CIDR="10.6.0.0/16"
FIP="fip-${RG}"
MFQDN=${FIP}.${LOCATION}.cloudapp.azure.com

NSG="nsg-${RG}"

MASTER="${RG}-manager"
MASTER_SIZE="Basic_A1"

WORKER="${RG}-worker"
WORKER_SIZE="Basic_A1"
WORKER_SIZE="Standard_A1_v2"
AVAILABILITY_SET="avs-${RG}"

ADMIN_USER=core
YAML="/tmp/cloud-config.yml"
CERT="azure.pub"

cat <<EOF >$YAML
#cloud-config
packages:
  - docker.io
runcmd:
  - usermod -a -G docker ${ADMIN_USER}
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
        # first VM (ie the swarm master) is created with a FIP
        #
        azure vm create  \
            --custom-data=$YAML \
            --disable-boot-diagnostics \
            --vm-size=$MASTER_SIZE \
            --admin-username ${ADMIN_USER} --ssh-publickey-file $CERT \
            --nic-name nic-$MASTER  --vnet-name $VNET --vnet-subnet-name $SUBNET \
            --public-ip-name $FIP --public-ip-domain-name $FIP \
            --image-urn $IMAGE \
            $RG vm-${MASTER} $LOCATION Linux

        #
        # Other VMS created without a FIP
        #
	i=1
	while [ $i -le $NB_WORKERS ] 
        do
            azure vm create  \
                --custom-data=$YAML \
                --disable-boot-diagnostics \
                --vm-size=$WORKER_SIZE \
                --admin-username ${ADMIN_USER} --ssh-publickey-file $CERT \
                --nic-name nic-${WORKER}$i   --vnet-name $VNET --vnet-subnet-name $SUBNET \
                --image-urn $IMAGE \
                --availset-name ${AVAILABILITY_SET} \
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
# it seems that apt install docker.io is aynchronous, in some cases the docker command is not available especially in thee lastly provisionned VM
#
echo sleeping 2mns for docker installation to finish
sleep 120

#
# initialize the cluster/swarm
#
master_ip=`azure network nic show $RG nic-${MASTER} | awk -F":" '/Private IP address/ { print $3}'`
ssh-keygen -R ${MFQDN}
ssh -A ${ADMIN_USER}@${MFQDN}  -o StrictHostKeyChecking=no ifconfig eth0
ssh -A ${ADMIN_USER}@${MFQDN}  -o StrictHostKeyChecking=no docker swarm init --advertise-addr ${master_ip}

# Configure the other VMs as workers
token=$(ssh -A ${ADMIN_USER}@${MFQDN} docker swarm join-token --quiet worker)
i=1
while [ $i -le $NB_WORKERS ]
do
    priv_ip=`azure network nic show $RG nic-${WORKER}$i | awk -F":" '/Private IP address/ { print $3}'`
    ssh -A ${ADMIN_USER}@${MFQDN}  -o StrictHostKeyChecking=no ssh  -o StrictHostKeyChecking=no $priv_ip docker swarm join --token $token ${master_ip}:2377
    ((i++))
done

#
# log something
#

cluster_fip=$(azure network public-ip list $RG | awk "/$FIP/ {print \$8  \" \" \$10}")
echo "Cluster FIP at ${cluster_fip}"
master_ip=`azure network nic show $RG nic-${MASTER} | awk -F":" '/Private IP address/ { print $3}'`
echo "Private IP VM ${MASTER} ${master_ip}"

i=1
while [ $i -le $NB_WORKERS ]
do
    priv_ip=`azure network nic show $RG nic-${WORKER}$i | awk -F":" '/Private IP address/ { print $3}'`
    echo "Private IP VM ${WORKER}${i} ${priv_ip}"
    ((i++))
done
ssh -A ${ADMIN_USER}@${MFQDN}  -o StrictHostKeyChecking=no docker node ls
