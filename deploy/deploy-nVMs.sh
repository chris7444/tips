# Create the other VMS
# Deploy 'n' VMs and a vip to access these VMs
#   two VM sizes are supported, one for the first VM, a second size for all other VMs
#   generally the first VM is the access VM and does not need to be under steroid (small size is enough)
#

MAXVMS=5 # don't want to deploy too many VMs and burn mu Azure credit

nvms=$1
if [[ -z $nvms ]]
then
   echo usage $0 count
   echo "   "   where count is the number of VMs you want to create
   exit 1
fi
if [[ $nvms -lt 1 ]] || [[ $nvms -gt $MAXVMS ]] 
then 
   echo $0: cannot deploy lesss than 1 VM or more than $MAXVMS VMs. 
   exit 1
fi
echo About to deploy $nvms VMs

#
# we deploy in a resource group, it is easier to delete all resources when we want to release the resources
#
# Do NOT use fancy characters in the name of the resource group, only alphanumeric
#
RG="nVMs"

#
# Deploy in West Europe
#
LOCATION="westeurope"

#
# Resources
#
IMAGE="Canonical:UbuntuServer:16.04-LTS:latest"
VNET="vnet-${RG}"
VNETPREFIX="10.7.0.0/16"
SUBNET="subnet-${RG}"
CIDR="10.7.0.0/16"
FIP="fip-${RG,,}"
MFQDN=${FIP}.${LOCATION}.cloudapp.azure.com
NSG="nsg-${RG}"
STORAGE="storage${RG,,}"

LEADER_SIZE="Basic_A0"
WORKER_SIZE="Standard_A1_v2" # required if we want availability sets
WORKER_SIZE="Basic_A0"

ADMIN_USER=chris
YAML="/tmp/cloud-config.yml"
CERT="azure.pub"

cat <<EOF >$YAML
#cloud-config
packages:
  - haproxy
  - docker.io
runcmd:
  - usermod -a -G chris ${ADMIN_USER}
EOF


#
# delete everything from the previous run
#
    azure group delete -q $RG

#
# Ready to go
#
azure group create $RG $LOCATION
azure network vnet create --address-prefixes $VNETPREFIX $RG $VNET $LOCATION
azure network vnet subnet create $RG $VNET $SUBNET $CIDR
azure storage account create --location $LOCATION --resource-group $RG --sku-name LRS --kind Storage $STORAGE

#
# create leader/access VM
#
azure vm create  \
    --custom-data=$YAML \
    --disable-boot-diagnostics \
    --vm-size=$LEADER_SIZE \
    --admin-username ${ADMIN_USER} --ssh-publickey-file $CERT \
    --nic-name nic-worker0  --vnet-name $VNET --vnet-subnet-name $SUBNET \
    --public-ip-name $FIP --public-ip-domain-name $FIP \
    --image-urn $IMAGE \
    $RG vm-worker0 $LOCATION Linux

#
# Create the other VMS
#

i=1
while [[ i -lt $nvms ]] 
do 
    azure vm create  \
        --custom-data=$YAML \
        --disable-boot-diagnostics \
        --vm-size=$WORKER_SIZE \
        --admin-username ${ADMIN_USER} --ssh-publickey-file $CERT \
        --nic-name nic-worker${i}   --vnet-name $VNET --vnet-subnet-name $SUBNET \
        --image-urn $IMAGE \
        $RG vm-worker${i} $LOCATION Linux
        ((i++)) 
done

#
# Create NSG and assign to master VM
#
#azure network nsg create $RG $NSG westeurope
#azure  network nsg rule create --protocol tcp --destination-port-range 22          --access allow --direction inbound $RG $NSG  ssh    100
#azure  network nsg rule create --protocol tcp --destination-port-range 31900-31999 --access allow --direction inbound $RG $NSG  myapps 110
#azure  network nic set --network-security-group-name $NSG $RG nic-worker0

#
# log something
#

public_ip=$(azure network public-ip list $RG | awk "/$FIP/ {print \$8  \" \" \$10}")
echo "FIP at ${public_ip}"
i=0
while [[ $i -lt $nvms ]]
do
    priv_ip=`azure network nic show $RG nic-worker${i} | awk -F":" '/Private IP address/ { print $3}'`
    echo "Private IP VM vm-worker${i} ${priv_ip}"
    ((i++))
done
