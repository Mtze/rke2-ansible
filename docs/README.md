# RKE2


# Kube-vip 


## Generate Manifests

The process is described [here](https://kube-vip.io/install_static/#generating-a-manifest). 

To generate a HA control plane (in ARP mode) use the following command: 
```
docker run ghcr.io/kube-vip/kube-vip manifest daemonset \
        --arp 
        --interface <NIC on Host - e.g. ens18> 
        --address <VIP IP - e.g. 10.3.2.1>
        --controlplane 
        --leaderElection 
        --inCluster
```
