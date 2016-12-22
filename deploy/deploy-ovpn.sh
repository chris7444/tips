#
# Deploy ubuntu VM
#

#
# we deploy in a resource group, it is easier to delete all resources when we want to release the resources
#
RG="ovpn"					# this is the resource group
LOCATION="westeurope"				# we deploy in west europe

#
# Resources
#
IMAGE="Canonical:UbuntuServer:16.04-LTS:latest"
VNET="vnet-${RG}"				# network to be deployed
VNETPREFIX="10.5.0.0/16"			# with the following address space
SUBNET="subnet-${RG}"				# name of subnet
CIDR="10.5.0.0/16"				# CIDR for the subnet
FIP="fip-${RG}"					# DNS name for the FIP
MFQDN=${FIP}.${LOCATION}.cloudapp.azure.com	# FQDN of FIP
NSG="nsg-${RG}"					# network security group
MASTER="${RG}"					# name of the VM to be deployed
MASTER_SIZE="Basic_A0"				# Size of the VM to be deployed
ADMIN_USER=chris				# Admin user name
CERT="azure.pub"				# SSH KEY to be pushed in the VM

#
# cloud config file 
#
YAML="/tmp/cloud-config.yml"
cat <<EOF >$YAML
#cloud-config
package_upgrade: true
packages:
  - docker.io
  - openvpn
  - easy-rsa
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
# Create NSG and assign to master VM
#
azure network nsg create $RG $NSG westeurope
azure network nsg rule create --protocol tcp --destination-port-range 22   --access allow --direction inbound $RG $NSG  ssh  100
azure network nsg rule create --protocol udp --destination-port-range 1194 --access allow --direction inbound $RG $NSG  ovpn 110
azure network nic set --network-security-group-name $NSG $RG nic-${MASTER}

echo sleeping 2mns for docker installation to finish
sleep 120

#
# log something
#

cluster_fip=$(azure network public-ip list $RG | awk "/$FIP/ {print \$8  \" \" \$10}")
echo "FIP at ${cluster_fip}"
master_ip=`azure network nic show $RG nic-${MASTER} | awk -F":" '/Private IP address/ { print $3}'`
echo "Private IP VM ${MASTER} ${master_ip}"
