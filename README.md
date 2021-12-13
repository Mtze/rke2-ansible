# mtze.rke2

Role to install a RKE2 Cluster.

# Requirements

TBA

# Role Variables

TBA

# Dependencies

TBA

# Example Playbook


## Example - Generate cluster token with this role

If the cluster token should be created with this role, the role must be executed on the first node exclusifly. 
The `first_node_install` variable has to be set to true for the fist node. 
Later the token will be automatically resolved from the first node and propagated to the other nodes.

```
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
## Example - Generate cluster token externaly
TBA

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

