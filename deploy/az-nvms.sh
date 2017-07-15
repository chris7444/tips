# Create the other VMS
# Deploy 'n' VMs and a vip to access these VMs
#   two VM sizes are supported, one for the first VM, a second size for all other VMs
#   generally the first VM is the access VM and does not need to be under steroid (small size is enough)
#

#
# we deploy in a resource group, it is easier to delete all resources when we want to release the resources
#
# Do NOT use fancy characters in the name of the resource group, only alphanumeric
#
RG="nVMs"

MAXVMS=5 # don't want to deploy too many VMs and burn mu Azure credit

#
# Check Argument
#
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
  - unzip
  - jq
runcmd:
  - usermod -a -G chris ${ADMIN_USER}
  - apt-get remove -y docker docker-engine docker.io
  - apt-get update
  - apt-get install -y  apt-transport-https  ca-certificates curl software-properties-common
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
  - apt-key fingerprint 0EBFCD88
  - add-apt-repository  "deb [arch=amd64] https://download.docker.com/linux/ubuntu  $(lsb_release -cs)   stable"
  - apt-get update
  - apt-get -y install docker-ce
  - usermod -a -G docker ${ADMIN_USER}
EOF



#
# delete everything from the previous run
#
echo Deleting Resource Group $RG
az group delete --yes --name $RG

#
# Ready to go
#

# Verify that the name of the storage account is not in use
echo Verifying Storage Account Name
available=$(az storage account check-name --name ${STORAGE} | jq -r .nameAvailable)
if [[ $available != true ]] 
then 
    echo Storage Account Name $STORAGE is in use
    exit 1
fi


echo Creating Resource Group $RG
az group create --name $RG --location $LOCATION

echo Creating Storage Account $STORAGE
az storage account create --name $STORAGE --resource-group $RG --sku Standard_LRS --kind Storage --location $LOCATION

echo Creating vNet $VNET
az network vnet create --address-prefixes $VNETPREFIX --resource-group $RG  --location $LOCATION --name $VNET

echo Creating subnet $SUBNET $CIDR
az network vnet subnet create --address-prefix $CIDR --name $SUBNET --resource-group $RG --vnet-name $VNET

echo Creating Public IP
az network public-ip  create --resource-group $RG --location $LOCATION --dns-name $FIP --name $FIP


#
# Create the VMS
#

i=0
while [[ $i -lt $nvms ]] 
do 

    if [[ $i -eq 0 ]] 
    then
        size=$LEADER_SIZE
        public_ip=$FIP
    else
        size=$WORKER_SIZE
        public_ip=''
    fi

    echo Creating NIC for VM${i}
    az network nic create                 \
        --location $LOCATION              \
        --resource-group $RG              \
        --subnet $SUBNET                  \
        --vnet-name $VNET                 \
        --public-ip-address=$public_ip    \
        --name nic-worker${i}

    echo Creating VM${i}
    az vm create                          \
        --custom-data $YAML               \
        --size $size                      \
        --admin-username ${ADMIN_USER}    \
        --ssh-key-value $CERT             \
        --nics nic-worker${i}             \
        --image $IMAGE                    \
        --resource-group $RG              \
        --location $LOCATION              \
        --storage-account $STORAGE        \
        --use-unmanaged-disk              \
        --name vm-worker${i}
    ((i++)) 
done

#
# Create NSG and assign to master VM, houlsd be debugged, was never used
#
az network nsg create --name $NSG --resource-group $RG --location $LOCATION
az network nsg rule create --name ssh --nsg-name $NSG --priority 150 -g $RG --access Allow --direction Inbound --protocol tcp --destination-port-range 22
#azure  network nsg rule create --protocol tcp --destination-port-range 31900-31999 --access allow --direction inbound $RG $NSG  myapps 110
az network nic update --network-security-group $NSG --name nic-worker0 -g $RG


#
# log something
#
az vm  list-ip-addresses --output table -g $RG
