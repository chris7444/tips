#
# Create the Key-Value store "cluster" VM
#

docker-machine create -d azure mh-keystore

#
# Apparently there is a bug in the NSG assigned to this VM, port 8500 is not open
#
#echo Opening port 8500 on the key-value store 
azure  network nsg rule create --protocol tcp --destination-port-range 8500  --access allow --direction inbound $AZURE_RESOURCE_GROUP mh-keystore-firewall  consul    500


# land the key-store cluster container
eval "$(docker-machine env mh-keystore)"
docker run -d \
    -p "8500:8500" \
    -h "consul" \
    progrium/consul -server -bootstrap

#
# Create the swarm master
#
docker-machine create \
    -d azure \
     --swarm --swarm-master \
     --swarm-discovery="consul://$(docker-machine ip mh-keystore):8500" \
     --engine-opt="cluster-store=consul://$(docker-machine ip mh-keystore):8500" \
     --engine-opt="cluster-advertise=eth0:2376" \
     mhs-demo0

#
# Add Additional docker hosts
#

docker-machine create \
    -d azure \
    --swarm \
    --swarm-discovery="consul://$(docker-machine ip mh-keystore):8500" \
    --engine-opt="cluster-store=consul://$(docker-machine ip mh-keystore):8500" \
    --engine-opt="cluster-advertise=eth0:2376" \
    mhs-demo1


