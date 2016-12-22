#
# Make sure the AZURE_* variables are defined
#
if [ -z $AZURE_SUBSCRIPTION_ID ]
then
   echo "Please update the file azure.rc then source it before running this file"
   exit 1
fi

#
# Create a docker swarm with an external KV store
#
swarm_size=2			# size of the swarm including the master
vm_swarm=vm-swarm		# name of the VMs in the swarm	
vm_keystore=vm-keystore		# name of the external KV store

#
# Create the KV store VM. We need to open port 8500 (22 and 2376 are opened by default by docker-machine
#
docker-machine create -d azure --azure-open-port 8500 ${vm_keystore}

#azure  network nsg rule create --protocol tcp --destination-port-range 8500  --access allow --direction inbound $AZURE_RESOURCE_GROUP ${vm_keystore}-firewall  consul    500

sleep 60

# land the key-store cluster container
eval "$(docker-machine env ${vm_keystore})"
docker run -d \
    -p "8500:8500" \
    -h "consul" \
    progrium/consul -server -bootstrap

#
# Create the swarm master
#
  i=0
  docker-machine create \
    -d azure \
     --swarm --swarm-master \
     --swarm-discovery="consul://$(docker-machine ip ${vm_keystore}):8500" \
     --engine-opt="cluster-store=consul://$(docker-machine ip ${vm_keystore}):8500" \
     --engine-opt="cluster-advertise=eth0:2376" \
     ${vm_swarm}$i
  ((i++))
#
# Add Additional docker hosts
#
while [ $i -lt $swarm_size ]
do
  docker-machine create \
    -d azure \
    --swarm \
    --swarm-discovery="consul://$(docker-machine ip ${vm_keystore}):8500" \
    --engine-opt="cluster-store=consul://$(docker-machine ip ${vm_keystore}):8500" \
    --engine-opt="cluster-advertise=eth0:2376" \
    ${vm_swarm}$i
    ((i++))
done

