# mtze.rke2

Role to install a RKE2 Cluster.


# Role Variables

See `defaults` and `vars` folders for all possible variables. 

__Important__:
Make sure to set the `rke2_node_type` (can be `server` or `agent`() variable for your nodes. The easiest way is to create a group_var file for agent and for server (Control Plane) nodes and put the corresponding `rke2_node_type` in there. 


```
fetch_kube_config: true # Download the kubectl config file to local machine
cluster_name: # Is usesd to name the kubectl config file locally
```

# Example Playbook

## Example - Generate cluster token with this role

If the cluster token should be created with this role, the role must be executed on the first node exclusively. 
The `first_node_install` variable has to be set to true for the fist node. 
Later the token will be automatically resolved from the first node and propagated to the other nodes.

```yaml
host: server-node-1
roles: 
  - role: mtze.rke2
    vars: 
      first_node_install: true

host: all_nodes
roles: 
  - role: mtze.rke2
    vars: 
      control_plane_server: server-node-1
```
## Example - Generate cluster token externally
TBA

## Example - Generat cluster token with role and use kube-vip to deploy a HA Control Plane 

This role will automatically install and configure kube-vip to provide a floating IP for the Control Plane if you add the `control_plane_vip*` variables. 

```yaml
host: server-node-1
roles: 
  - role: mtze.rke2
    vars: 
      first_node_install: true
      control_plane_vip: 10.20.30.1
      control_plane_vip_hostname: control-plane.example.com
      control_plane_vip_interface: eth8

host: all_nodes
roles: 
  - role: mtze.rke2
    vars: 
      control_plane_server: server-node-1
```


# License

MIT

# Development Environment

```
virtualenv venv
. venv/bin/activate.fish # For fish shell users
pip3 install -r requirements.txt
```

# Author Information

Matthias Linhuber
github [at] linhuber.org
[mtze.me](https://mtze.me)

