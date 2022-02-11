# mtze.rke2

Role to install a [RKE2](https://docs.rke2.io) Kubernetes (K8s) Cluster.

This role offers the following features: 
- Bootstrap a cluster control plane 
- Install additional control plane nodes 
- Install worker nodes
- Configure [kube-vip](https://kube-vip.io) to provide a high available control plane (in ARP mode)
- Install `kubectl` on all nodes for local debugging (configurable)
- Install `calicoctl` on all nodes if calico is used as CNI (configurable)

This role is still in development - If you encounter problems or have feature requests, please open an [issue](https://github.com/Mtze/rke2-ansible/issues).

# Installation 
You can install the role using [Ansible Galaxy](https://galaxy.ansible.com/mtze/rke2)

```
ansible-galaxy install mtze.rke2
```

Manual install of latest version: 

```
ansible-galaxy install git+https://github.com/Mtze/rke2-ansible.git,main
```

# Role Variables

See `defaults` and `vars` folders for all possible variables. 

__Important__:

Make sure to set the `rke2_node_type` (can be `server` or `agent`) variable for your nodes. The easiest way is to create a group_var file for agent and for server (Control Plane) nodes and put the corresponding `rke2_node_type` in there. 

## Cluster Bootstrap 
If you bootstrap a cluster with this role, you have to execute this role on one node only with the `first_node_install` variable set to `true`. 
This will automatically instantiate the cluster on one node which then can be joined by additional nodes - An example can be seen below. 

By default, this role will not install an ingress controler! The default CNI plugin is calico. Both can be configured with the corresponding variables. 

## Kubeconfig
This role can fetch the kubeconfig file from the cluster to your local machine. This is enabled by default. Configure the following variables to adjust the behavior.
```
fetch_kube_config: true
local_kube_config_path: "~/.kube/config-{{ cluster_name }}"
```

## Control Plane virtual IP (VIP) with [kube-vip](https://kube-vip.io)
If you opt for a High available control plane with kube-vip, you have to configure the following variables: 
```yaml
# If kube-vip is used, define the cluster control plane virtual ip and associated DNS name here. These will be added as tls-san.
control_plane_vip: <IP Here>
control_plane_vip_hostname: <DNS name that resolves to control_plane_vip here>
control_plane_vip_interface: <Interface Interface on which the control plane will ARP for the VIP here >
```

## Install without kube-vip base control plane
To be able to join the cluster, nodes have to find a control plane node. You can specify the desired control plane node by hand: 

This is not needed for kube-vip - The role will use the virtual, floating IP (VIP) to join new nodes to the cluster.

## Additional Nodes for an existing cluster
If you install additional nodes for a cluster __not__ instantiated by this role, you can specify the cluster token by hand. 
```yaml
cluster_token: <tocken here>
```
This is not necessary for clusters bootstrapped with this role - The token will be resolved automatically! 

# Example Playbook

## Example - Generate cluster token with this role

If the cluster token should be created with this role, the role must be executed on the first node exclusively. 
The `first_node_install` variable has to be set to true for the fist node. 
Later the token will be automatically resolved from the first node and propagated to the other nodes.

```yaml
host: server-node-1.example.com
roles: 
  - role: mtze.rke2
    vars: 
      first_node_install: true

host: all_nodes
roles: 
  - role: mtze.rke2
    vars: 
      control_plane_server:  https://control-node1.example.com:9345
```

## Example - General cluster token with role and use kube-vip to deploy a HA Control Plane 

This role will automatically install and configure kube-vip to provide a floating IP for the Control Plane if you add the `control_plane_vip*` variables. 

```yaml
host: server-node-1.example.com
roles: 
  - role: mtze.rke2
    vars: 
      first_node_install: true
      control_plane_vip: 10.20.30.1
      control_plane_vip_hostname: control-plane.example.com
      control_plane_vip_interface: eth0

host: all_nodes
roles: 
  - role: mtze.rke2
    vars: 
      control_plane_vip: 10.20.30.1
      control_plane_vip_hostname: control-plane.example.com
      control_plane_vip_interface: eth0
```

## Example - Deoloy Dualstack Cluster 
You can deploy a dual stack cluster with this role. There are some important considerations to make: 
- You have to define both, `cluster_cidr` and `service_cidr` with IPv4 and IPv6 address spaces. 
- Make sure both address spaces are big enough so that each node can get a `/node_cidr_mask_ipv4` and a `/node_cidr_mask_ipv6` from the `cluster_cidr` address space. (Hence the more complex IPv6 example here)
- A dual stack VIP is currently not supported by the role. 

```
- name: Setup frist host
  host: server-node-1.example.com

  roles:
    - role: mtze.rke2
      vars: 
        first_node_install: true
        cluster_cidr: "198.18.0.0/16,fcfe::1:0:0/96"
        service_cidr: "198.19.0.0/16,fcfe::1:ffff:0/112"
        node_cidr_mask_ipv4: 24
        node_cidr_mask_ipv6: 112
        cni_plugin: calico
        control_plane_vip: 10.20.30.1
        control_plane_vip_hostname: control-plane.example.com
        control_plane_vip_interface: eth0

- name: Setup frist host
  host: all_nodes

  roles:
    - role: mtze.rke2
      vars: 
        cluster_cidr: "198.18.0.0/16,fcfe::1:0:0/96"
        service_cidr: "198.19.0.0/16,fcfe::1:ffff:0/112"
        node_cidr_mask_ipv4: 24
        node_cidr_mask_ipv6: 112
        cni_plugin: calico
        control_plane_vip: 10.20.30.1
        control_plane_vip_hostname: control-plane.example.com
        control_plane_vip_interface: eth0
```

# License

MIT

# Development Environment

```
virtualenv venv
. venv/bin/activate.fish # For fish shell users
pip3 install -r requirements.txt
```
# Acknolegements
This role is based on the [work](https://www.youtube.com/watch?v=QqSgiezqMAA&t=472s) of Adrian Goins ([Twitter](https://twitter.com/adriandotgoins), [Youtube](https://www.youtube.com/adriandotgoins)). 

# Author Information

Matthias Linhuber
github [at] linhuber.org
[mtze.me](https://mtze.me)

