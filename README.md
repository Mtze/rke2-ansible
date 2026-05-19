# mtze.rke2

Ansible role to install a [RKE2](https://docs.rke2.io) Kubernetes cluster.

Features:
- Bootstrap a single-node or multi-server control plane
- Install additional control plane nodes and worker (agent) nodes
- Configure [kube-vip](https://kube-vip.io) for a high-available control plane (ARP mode)
- Install `kubectl` on all nodes for local debugging (configurable)
- Install `calicoctl` on all nodes when Calico is used as CNI (configurable)
- Install Longhorn block-storage dependencies (configurable)
- Automatic cluster token discovery and propagation across play hosts
- Fetch kubeconfig to the local machine after install

If you encounter problems or have feature requests, open an [issue](https://github.com/Mtze/rke2-ansible/issues).

---

## Requirements

- Ansible Core >= 2.15.0
- Supported platforms:
  - Ubuntu 20.04 (focal)
  - Ubuntu 22.04 (jammy)
  - Debian 11 (bullseye)
  - Debian 12 (bookworm)

Install dev dependencies:

```bash
virtualenv venv
source venv/bin/activate   # or: . venv/bin/activate.fish
pip install -r requirements.txt
```

---

## Installation

Via [Ansible Galaxy](https://galaxy.ansible.com/mtze/rke2):

```bash
ansible-galaxy install mtze.rke2
```

Latest from Git:

```bash
ansible-galaxy install git+https://github.com/Mtze/rke2-ansible.git,main
```

---

## Role Variables

All variables are in [defaults/main.yml](defaults/main.yml). Override them in your inventory, group_vars, or host_vars.

### General

| Variable | Default | Description |
|---|---|---|
| `rke2_node_type` | **required** | `server` or `agent`. Must be set for every host. |
| `cluster_name` | `rke2` | Used to name the local kubeconfig file. |
| `rke2_version` | `v1.31.3+rke2r1` | RKE2 version to install. See [releases](https://github.com/rancher/rke2/releases). |
| `rke2_download_url` | `https://get.rke2.io` | URL to the RKE2 install script. |
| `rke2_download_path` | `/opt` | Local path to download the install script to. |
| `first_node_install` | `false` | Set to `true` on the first server node to bootstrap the cluster. |
| `cluster_token` | _(auto)_ | Cluster join token. Auto-discovered from an existing server if not set. |
| `cluster_domain` | _(empty)_ | Cluster domain name. |
| `additional_hostnames` | `[]` | Extra SANs to add to the RKE2 TLS certificate. `inventory_hostname` and `ansible_hostname` are always included automatically. |
| `disabled_components` | `[rke2-ingress-nginx]` | RKE2 components to disable. Valid values: `rke2-coredns`, `rke2-ingress-nginx`, `rke2-kube-proxy`, `rke2-metrics-server`. |
| `debug_output` | `false` | Print extra debug output during the play. |

### CNI

| Variable | Default | Description |
|---|---|---|
| `cni_plugin` | `calico` | CNI plugin. One of: `calico`, `canal`, `cilium`, `none`. |
| `install_calicoctl` | `true` | Install `calicoctl` when CNI is `calico`. |
| `calicoctl_version` | `v3.29.1` | `calicoctl` version to install. |
| `calicoctl_host_architecture` | _(auto)_ | `amd64` or `arm64`, derived from `ansible_architecture`. |
| `calicoctl_checksum` | _(empty)_ | Optional SHA256 checksum for the `calicoctl` binary, e.g. `sha256:abc123...`. Skipped if empty. |

### Network

| Variable | Default | Description |
|---|---|---|
| `cluster_cidr` | _(empty)_ | Pod IP address space. Set both IPv4 and IPv6 for dual-stack, e.g. `198.18.0.0/16,fcfe::1:0:0/96`. |
| `service_cidr` | _(empty)_ | Service IP address space. |
| `node_ips` | _(empty)_ | Explicit node IP(s) for multi-homed hosts, e.g. `192.168.1.10`. |
| `node_cidr_mask_ipv4` | `24` | Per-node pod CIDR size for IPv4. |
| `node_cidr_mask_ipv6` | `112` | Per-node pod CIDR size for IPv6. |

### Control plane VIP (kube-vip)

| Variable | Default | Description |
|---|---|---|
| `control_plane_vip` | _(empty)_ | Floating virtual IP for the control plane, e.g. `10.20.30.1`. |
| `control_plane_vip_hostname` | _(empty)_ | DNS name resolving to `control_plane_vip`. |
| `control_plane_vip_interface` | _(empty)_ | Network interface on which kube-vip will ARP for the VIP. |
| `kube_vip_version` | `v0.9.1` | kube-vip version. See [releases](https://github.com/kube-vip/kube-vip/releases). |
| `kube_vip_rbac_manifest_url` | `https://kube-vip.io/manifests/rbac.yaml` | URL for the kube-vip RBAC manifest. Override to use a local mirror. |
| `control_plane_server` | `https://{{ control_plane_vip_hostname }}:9345` | Control plane URL used by nodes to join the cluster. Change this when not using kube-vip. |

### kubectl

| Variable | Default | Description |
|---|---|---|
| `kubectl_install_on_nodes` | `true` | Install `kubectl` on all nodes. |
| `kubectl_version` | `v1.33.0` | `kubectl` version to install. Run `curl -L https://dl.k8s.io/release/stable.txt` for the latest. |
| `kubectl_checksum` | _(empty)_ | Optional SHA256 checksum for the `kubectl` binary. Skipped if empty. |
| `fetch_kube_config` | `true` | Fetch the cluster kubeconfig to the local machine after install. |
| `local_kube_config_path` | `~/.kube/config-{{ cluster_name }}` | Local path to write the kubeconfig to. |

### Longhorn

| Variable | Default | Description |
|---|---|---|
| `install_longhorn_dependencies` | `true` | Install `nfs-common` and `open-iscsi` (Debian/Ubuntu only). A warning is printed for other OS families. |

---

## Tags

Every task is tagged so you can run subsets of the role:

| Tag | What runs |
|---|---|
| `validate` | Variable and OS-family checks only |
| `install` | All installation tasks (scripts, binaries, services) |
| `configure` | Config file rendering and service restart |
| `download` | Only download tasks (binaries, manifests) |
| `rke2` | RKE2-specific tasks |
| `kubectl` | kubectl install tasks |
| `calico` | calicoctl install tasks |
| `kube-vip` | kube-vip manifest deploy tasks |
| `longhorn` | Longhorn dependency install tasks |

Examples:

```bash
# Re-apply config only (no re-install)
ansible-playbook site.yml --tags configure

# Download binaries only (useful to pre-cache on airgapped nodes)
ansible-playbook site.yml --tags download
```

---

## Usage

### Bootstrapping a new cluster

The role must run on the first server node with `first_node_install: true` before running on all other nodes. This generates the cluster token on the first node and propagates it automatically to all other hosts in the play.

### Joining an existing cluster

If the cluster was not bootstrapped with this role, set `cluster_token` manually in your vars. For clusters created by this role the token is resolved automatically.

### Control plane URL

Without kube-vip, set `control_plane_server` to point to an existing server node:

```yaml
control_plane_server: "https://server-node-1.example.com:9345"
```

With kube-vip, set `control_plane_vip` and `control_plane_vip_hostname`. The role will derive the server URL from `control_plane_vip_hostname` automatically.

---

## Example Playbooks

### Simple cluster (no HA, single server)

```yaml
- name: Bootstrap first server
  hosts: server-node-1.example.com
  roles:
    - role: mtze.rke2
      vars:
        rke2_node_type: server
        first_node_install: true

- name: Join remaining nodes
  hosts: all_nodes
  roles:
    - role: mtze.rke2
      vars:
        control_plane_server: "https://server-node-1.example.com:9345"
```

> `rke2_node_type` is most cleanly set via `group_vars` (e.g. `group_vars/servers/rke2.yml` and `group_vars/agents/rke2.yml`) rather than inline vars.

### HA control plane with kube-vip

kube-vip is deployed automatically when `control_plane_vip` is set on the first node install.

```yaml
- name: Bootstrap first server with kube-vip
  hosts: server-node-1.example.com
  roles:
    - role: mtze.rke2
      vars:
        rke2_node_type: server
        first_node_install: true
        control_plane_vip: 10.20.30.1
        control_plane_vip_hostname: control-plane.example.com
        control_plane_vip_interface: eth0

- name: Join all remaining nodes
  hosts: all_nodes
  roles:
    - role: mtze.rke2
      vars:
        control_plane_vip: 10.20.30.1
        control_plane_vip_hostname: control-plane.example.com
        control_plane_vip_interface: eth0
```

All nodes receive `tls-san` entries for both `control_plane_vip` and `control_plane_vip_hostname`.

### Dual-stack cluster

Important considerations:
- Both `cluster_cidr` and `service_cidr` must include both IPv4 and IPv6 ranges.
- Each node gets a `/{node_cidr_mask_ipv4}` and `/{node_cidr_mask_ipv6}` subnet from `cluster_cidr`. Ensure the cluster CIDR is large enough.
- Dual-stack VIP (kube-vip) is not currently supported.

```yaml
- name: Bootstrap first server
  hosts: server-node-1.example.com
  roles:
    - role: mtze.rke2
      vars:
        rke2_node_type: server
        first_node_install: true
        cluster_cidr: "198.18.0.0/16,fcfe::1:0:0/96"
        service_cidr: "198.19.0.0/16,fcfe::1:ffff:0/112"
        node_cidr_mask_ipv4: 24
        node_cidr_mask_ipv6: 112
        cni_plugin: calico

- name: Join all nodes
  hosts: all_nodes
  roles:
    - role: mtze.rke2
      vars:
        cluster_cidr: "198.18.0.0/16,fcfe::1:0:0/96"
        service_cidr: "198.19.0.0/16,fcfe::1:ffff:0/112"
        node_cidr_mask_ipv4: 24
        node_cidr_mask_ipv6: 112
        cni_plugin: calico
```

---

## Upgrading from v1

The following changes in v2.0 require attention when upgrading:

**`rke2_node_type` is now strictly required.** The role now fails at the validate stage if the variable is undefined or empty. Ensure every host sets `rke2_node_type: server` or `rke2_node_type: agent`.

**`additional_hostnames` behavior changed.** Previously the variable lived in `vars/main.yml` and contained `{{ inventory_hostname }}`, making it non-overridable. It now lives in `defaults/main.yml` as an empty list (`[]`). `inventory_hostname` and `ansible_hostname` are always written to `tls-san` by the template, so nothing is lost. If you set `additional_hostnames` in your inventory, those entries are now purely additive.

**`min_ansible_version` raised to 2.15.** Ansible Core < 2.15 is no longer supported.

**The interactive confirmation pause was removed.** The role is now fully unattended. There is no prompt before the install script runs.

**`import_tasks` vs `include_tasks` for core task files.** `check-variables.yml` and `install-rke2.yml` are now imported statically (`import_tasks`). Tag filtering behavior at the play level is slightly different; test custom tag usage after upgrading.

---

## Development

```bash
virtualenv venv
source venv/bin/activate   # or: . venv/bin/activate.fish
pip install -r requirements.txt
```

Run the linter:

```bash
ansible-lint
```

### Releasing

Create a GitHub release. The [Push to Ansible Galaxy](.github/workflows/main.yml) workflow will import the role to Galaxy automatically.

---

## License

MIT

---

## Acknowledgements

This role is based on the [work](https://www.youtube.com/watch?v=QqSgiezqMAA&t=472s) of Adrian Goins.

## Author

Matthias Linhuber
[mtze.me](https://mtze.me)
