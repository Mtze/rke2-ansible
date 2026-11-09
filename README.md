# mtze.rke2

`mtze.rke2` is an Ansible role that installs and operates [RKE2](https://docs.rke2.io) Kubernetes clusters.
It is for people who run several RKE2 clusters over a long time, with Ansible, on Debian-family hosts.

The role covers the first install and everything after it: node pools, upgrades, restarts and hardening.
If you hit a problem or miss a feature, open an [issue](https://github.com/Mtze/rke2-ansible/issues).

## Contents

- [Why this role exists](#why-this-role-exists)
- [What sets this role apart](#what-sets-this-role-apart)
- [Quick start](#quick-start)
- [Requirements](#requirements)
- [Installation](#installation)
- [Role variables](#role-variables)
- [Tags](#tags)
- [Usage](#usage)
- [Security](#security)
- [Example playbooks](#example-playbooks)
- [Migration](#migration)
- [Development](#development)

---

## Why this role exists

Installing RKE2 takes one script and one config file.
Keeping a cluster healthy for years takes more, and the problems below come from running production clusters.

**Node pools drift.**
RKE2 applies `node-label` and `node-taint` only when a node registers.
A changed node pool does nothing on a node that has already joined, and the config file still looks correct.

**Day 2 is the hard part.**
A one-shot install does not cover upgrades.
An upgrade needs one node at a time, servers first, at most one minor version per step, and a health check between nodes.
One skipped step can take down etcd quorum.

**Some upgrades cannot work, and you only learn that halfway.**
Some RKE2 tags are published without release assets.
runc 1.4 does not start on kernel 5.4.
Kubernetes 1.35 needs cgroup v2.
An upgrade should find all of this before it touches a node.

**Work on one node pool must not disturb the others.**
A run with `--limit <pool>` has only that node pool in the play.
The token and the API server still live on a server outside the play, and a config written without a token leaves a node unable to join.

**The server token is too powerful for an agent.**
Without care, every agent holds the server token, which grants full access to the cluster.
One compromised agent then means a compromised cluster.

**User workloads on servers have crashed clusters.**
A taint alone does not stop them, because anyone who can create a pod can add a toleration.

**Defaults change under you.**
RKE2 deploys Traefik by default from v1.36.
A cluster that brings its own Gateway or Ingress does not want that.

---

## What sets this role apart

**A normal run never upgrades.**
If a node runs another version than `rke2_version`, the run stops with a message.
No variable change moves a cluster to a new version by accident.

**Upgrades are a separate entry point with preflight checks.**
`tasks_from: upgrade` refuses to run unless it has one node per batch.
Before it touches a node, it checks release assets, cgroup version, kernel version, the minor version step of a server, and that agents wait for all servers.

**Restarts are health-checked and go one node at a time.**
After a config change, a restart waits until the node is `Ready`, and on servers until the local etcd member is healthy.
The next node starts only after that.

**Node pools stay in sync on joined nodes.**
The role compares labels and taints with the API server and applies the difference through `kubectl`.
With `rke2_node_managed_prefix` it also removes what no longer belongs to the node pool.

**`--limit <pool>` is safe.**
The token comes from a fixed server of the cluster, even when the play holds only agents.
If no token is found, the role stops before it writes a config.

**Agents get their own token.**
Agents join with a separate secret that does not let a node join as a server.
The role creates this secret for you.

**No ingress controller by default.**
The role sets `ingress-controller: none`.
Choosing one is a single variable.

**An admission policy protects the control plane.**
A policy watches pods that tolerate the control plane taints or every taint.
It starts in `Warn` mode, and `Deny` refuses those pods.

**No Ansible collection dependencies.**
The role uses `ansible.builtin` modules only and has no role dependencies.

**The test suite needs neither hosts nor a cluster.**
It runs on localhost against fake `rke2`, `kubectl` and `systemctl` binaries, and CI runs it on every push.

---

## Quick start

Install the role:

```bash
ansible-galaxy install mtze.rke2
```

Describe the cluster in the inventory.
Keep `rke2_node_type` and `cluster_name` there, so the role can find the first server with `--limit`.

```yaml
# inventory.yml
all:
  vars:
    cluster_name: prod
    control_plane_server: https://server-1.example.com:9345
  children:
    servers:
      vars:
        rke2_node_type: server
      hosts:
        server-1.example.com:
          first_node_install: true
        server-2.example.com:
        server-3.example.com:
    agents:
      vars:
        rke2_node_type: agent
      hosts:
        agent-1.example.com:
        agent-2.example.com:
```

Bootstrap the first server, then join the rest:

```yaml
# site.yml
- name: Bootstrap the first server
  hosts: server-1.example.com
  any_errors_fatal: true
  roles:
    - mtze.rke2

- name: Join all other nodes
  hosts: servers:agents
  any_errors_fatal: true
  roles:
    - mtze.rke2
```

```bash
ansible-playbook -i inventory.yml site.yml
```

The kubeconfig lands in `~/.kube/config-prod`.
Without a VIP it points at `127.0.0.1`, so change the address before you use it from another machine.

---

## Requirements

- Ansible Core 2.17 or newer.
- Fact gathering turned on for the plays that use the role.
- Root through `become` on all nodes.
- Internet access from the nodes to `get.rke2.io` and GitHub.

Supported platforms:

| Distribution | Release |
|---|---|
| Ubuntu | 26.04 (resolute) |
| Debian | 11 (bullseye) |
| Debian | 12 (bookworm) |

---

## Installation

From [Ansible Galaxy](https://galaxy.ansible.com/mtze/rke2):

```bash
ansible-galaxy install mtze.rke2
```

Latest from Git:

```bash
ansible-galaxy install git+https://github.com/Mtze/rke2-ansible.git,main
```

---

## Role variables

All variables live in [defaults/main.yml](defaults/main.yml).
Override them in the inventory, `group_vars` or `host_vars`.

### Cluster

| Variable | Default | Description |
|---|---|---|
| `rke2_node_type` | _(empty, required)_ | `server` or `agent`. Set it for every host, in the inventory. |
| `cluster_name` | `rke2` | Names the local kubeconfig and snapshot directory, and finds the first server. Every cluster in an inventory needs its own name. Set it in the inventory. |
| `rke2_version` | `v1.35.9+rke2r1` | RKE2 version. A change takes effect only through an [upgrade](#upgrades). See the [releases](https://github.com/rancher/rke2/releases). |
| `rke2_download_url` | `https://get.rke2.io` | URL of the RKE2 install script. |
| `rke2_download_path` | `/opt` | Directory on the node for the install script. |
| `first_node_install` | `false` | Set to `true` on one server only. It bootstraps the cluster on that server. |
| `cluster_domain` | _(empty)_ | Cluster domain name. Empty keeps the RKE2 default. |
| `additional_hostnames` | `[]` | Extra `tls-san` entries. `inventory_hostname` and `ansible_hostname` are always included. |
| `disabled_components` | `[rke2-ingress-nginx]` | RKE2 components to disable. Valid items: `rke2-coredns`, `rke2-ingress-nginx`, `rke2-kube-proxy`, `rke2-metrics-server`. |
| `rke2_first_server` | _(computed)_ | Server that hands out tokens and runs `kubectl` for the other nodes. Defaults to the first server in the inventory with the same `cluster_name`, then to the first host of the play. Set it when `rke2_node_type` comes from play vars. |
| `rke2_kubectl` | `[/var/lib/rancher/rke2/bin/kubectl, --kubeconfig, /etc/rancher/rke2/rke2.yaml]` | `kubectl` command as a list, used on `rke2_first_server`. |
| `rke2_restart_timeout` | `600` | Seconds a restarted node gets to become healthy. |
| `debug_output` | `false` | Print extra debug output. Tokens stay hidden. |

### Tokens

| Variable | Default | Description |
|---|---|---|
| `cluster_token` | _(empty)_ | Server token. If empty, the role reads it from `rke2_first_server`. Set it to join a cluster this role did not bootstrap. |
| `rke2_agent_token` | `""` | Secret that lets agents join but not servers. If empty, the role creates one at bootstrap. On a running cluster, follow the [migration](#agent-token). |
| `rke2_agent_token_file` | `/etc/rancher/rke2/agent-token.key` | Where the generated secret lives on `rke2_first_server`. |
| `rke2_server_data_dir` | `/var/lib/rancher/rke2/server` | Where RKE2 keeps its tokens on a server. |

### Server options

Only servers receive these options, so S3 credentials never reach an agent.

| Variable | Default | Description |
|---|---|---|
| `rke2_ingress_controller` | `[none]` | Value of the RKE2 option `ingress-controller`. Use `[traefik]` for the packaged controller. An empty list leaves the choice to RKE2. |
| `rke2_kube_apiserver_args` | `[]` | Extra kube-apiserver arguments as `key=value`. |
| `rke2_etcd_snapshot_schedule` | `""` | Cron expression for etcd snapshots. Empty keeps the RKE2 default, every 12 hours. |
| `rke2_etcd_snapshot_retention` | `""` | Number of snapshots to keep. Empty keeps the RKE2 default, 5 snapshots. |
| `rke2_etcd_s3` | `{}` | S3 options without the `etcd-s3-` prefix, for example `{endpoint: s3.example.com, bucket: etcd, access-key: ..., secret-key: ...}`. |

### Node pool variables

| Variable | Default | Description |
|---|---|---|
| `rke2_node_labels` | `{}` | Labels of the node. |
| `rke2_node_taints` | `[]` | Taints of the node, as `key=value:effect` or `key:effect`. |
| `rke2_node_managed_prefix` | `""` | Remove labels and taints with this key prefix that are no longer listed. Empty means the role never removes anything. |
| `rke2_kubelet_args` | `[]` | Extra kubelet arguments as `key=value`, for example reservations and eviction thresholds. |

### CNI

| Variable | Default | Description |
|---|---|---|
| `cni_plugin` | `calico` | One of `none`, `calico`, `canal`, `cilium`. |
| `install_calicoctl` | `true` | Install `calicoctl` when `cni_plugin` is `calico`. |
| `calicoctl_version` | `v3.32.2` | `calicoctl` version. Keep it in line with the Calico version of your RKE2 release. |
| `calicoctl_host_architecture` | _(computed)_ | `amd64` on `x86_64`, otherwise `arm64`. |
| `calicoctl_checksum` | _(empty)_ | Expected checksum, for example `sha256:abc123...`. Empty verifies against the `SHA256SUMS` file of the release. |

### Network

| Variable | Default | Description |
|---|---|---|
| `cluster_cidr` | _(empty)_ | Pod address space. List IPv4 and IPv6 for dual-stack, for example `198.18.0.0/16,fcfe::1:0:0/96`. |
| `service_cidr` | _(empty)_ | Service address space. List IPv4 and IPv6 for dual-stack. |
| `node_ips` | _(computed)_ | Address of the default route, plus IPv6 on dual-stack clusters. Set it per host to use another interface. |
| `node_cidr_mask_ipv4` | `24` | Pod subnet size per node for IPv4. |
| `node_cidr_mask_ipv6` | `112` | Pod subnet size per node for IPv6. |

### Control plane VIP

| Variable | Default | Description |
|---|---|---|
| `control_plane_vip` | _(empty)_ | Virtual IP of the control plane. Setting it deploys kube-vip on all servers. |
| `control_plane_vip_hostname` | _(empty)_ | DNS name of the VIP. |
| `control_plane_vip_interface` | _(empty)_ | Interface on which kube-vip answers ARP for the VIP. |
| `kube_vip_version` | `v1.3.1` | kube-vip version. See the [releases](https://github.com/kube-vip/kube-vip/releases). |
| `kube_vip_digests` | `{v1.3.1: sha256:1962f9daf226503f7e6b107f595cb28b7917fd2d0113957075e19a3e5a6c1e33}` | Image digests of tested versions. Other versions go by their tag. |
| `kube_vip_image` | _(computed)_ | `ghcr.io/kube-vip/kube-vip:<kube_vip_version>`, plus `@<digest>` if the version is in `kube_vip_digests`. |
| `control_plane_server` | `https://{{ control_plane_vip_hostname }}:9345` | URL that nodes use to join. Set it when you do not use a VIP. |

### kubectl and kubeconfig

| Variable | Default | Description |
|---|---|---|
| `kubectl_install_on_nodes` | `true` | Link the `kubectl` shipped with RKE2 to `/usr/local/bin` and link `/root/.kube/config` to the local kubeconfig. |
| `fetch_kube_config` | `true` | Fetch the kubeconfig to the machine that runs Ansible. |
| `local_kube_config_path` | `~/.kube/config-{{ cluster_name }}` | Local path of the fetched kubeconfig. |

### Security variables

See [Security](#security) for what each variable does and how to tighten it.

| Variable | Default | Description |
|---|---|---|
| `rke2_audit_log` | `true` | Write an API server audit log at metadata level. Servers only. |
| `rke2_kubelet_seccomp_default` | `true` | Give pods the seccomp profile of the container runtime unless they ask for another one. |
| `rke2_cis_profile` | `""` | Set to `cis` to run the RKE2 CIS profile. Fresh installations only. |
| `rke2_system_namespaces` | `[kube-system, calico-system, tigera-operator]` | Namespaces that may tolerate the control plane taints and reach the protected node ports. |
| `rke2_control_plane_policy` | `Warn` | `Warn` reports, `Deny` refuses the pod, empty turns the policy off. |
| `rke2_protected_node_networks` | `[]` | Node addresses as CIDRs. Empty turns the node port protection off. Calico only. |
| `rke2_protected_node_ports` | `[2379, 2380, 9345, 10249, 10250, 10256, 10257, 10259]` | TCP ports that pods outside `rke2_system_namespaces` cannot reach. |

### Upgrade variables

| Variable | Default | Description |
|---|---|---|
| `rke2_upgrade_drain_args` | `[--ignore-daemonsets, --delete-emptydir-data, --timeout=600s]` | Arguments for `kubectl drain`. A single-server cluster also needs `--disable-eviction` and `--force`. |
| `rke2_upgrade_min_kernel` | `5.10` | Oldest kernel an upgrade accepts. runc 1.4 does not start on kernel 5.4. |
| `rke2_upgrade_snapshot_local_path` | `~/rke2-etcd-snapshots/{{ cluster_name }}` | Local copy of the snapshot when `rke2_etcd_s3` is empty. It holds all secrets of the cluster. |
| `rke2_etcd_snapshot_dir` | `/var/lib/rancher/rke2/server/db/snapshots` | Where RKE2 stores snapshots on a server. |

### Longhorn

| Variable | Default | Description |
|---|---|---|
| `install_longhorn_dependencies` | `true` | Install `nfs-common`, `open-iscsi` and `cryptsetup`, enable `iscsid`, load `iscsi_tcp` and `dm_crypt`, and keep `multipathd` away from `sd*` devices if it is installed. Debian family only. Do not use it on hosts that boot from multipath storage. The role does not prepare the data disk. |
| `install_longhorn_v2_dependencies` | `false` | Prepare the node for the [V2 Data Engine](#longhorn-v2-data-engine). Needs `install_longhorn_dependencies`. Set it per node pool. |
| `longhorn_v2_huge_pages` | `1024` | Huge pages of 2 MiB reserved for SPDK. Longhorn asks for 1024, which is 2 GiB per node. |

---

## Tags

The variable checks, the version check and the token discovery run with every tag.

| Tag | What runs |
|---|---|
| `validate` | Variable and OS family checks. |
| `install` | Installation tasks, including rendering the config. |
| `configure` | Config rendering, node pool sync and kubeconfig fetch. Restarts a node whose config changed. |
| `download` | Download of the install script on a node without RKE2. |
| `rke2` | RKE2 installation tasks, including rendering the config. |
| `kubectl` | `kubectl` link and kubeconfig link on the node. |
| `calico` | `calicoctl` download and configuration. |
| `kube-vip` | kube-vip manifests. |
| `policies` | Admission policy and node port protection manifests. |
| `longhorn` | Longhorn dependencies. |
| `needs_real_host` | Tasks that the localhost tests skip: the upgrade check for release assets, and the boot configuration of the V2 Data Engine. Skip it on a real host only if nodes cannot reach GitHub during an upgrade. |

To re-apply the config without an install:

```bash
ansible-playbook site.yml --tags configure
```

---

## Usage

### Bootstrapping a new cluster

Run the role on the first server with `first_node_install: true` before you run it on any other node.
RKE2 creates the server token there, and the role hands it to the other hosts.

`first_node_install` can stay in the inventory.
A node that already holds an etcd database joins through the usual `server:` entry and does not bootstrap again.
This needs `control_plane_vip`, `control_plane_vip_hostname` or `control_plane_server` in that play.
A single server with none of them stays in bootstrap mode.

### Joining nodes

Point new nodes at the cluster with one of two options.

With kube-vip, set `control_plane_vip` and `control_plane_vip_hostname`.
The role derives the join URL from them.

Without kube-vip, set `control_plane_server` to an existing server:

```yaml
control_plane_server: https://server-1.example.com:9345
```

For clusters this role created, the token comes from `rke2_first_server`, so `--limit <pool>` works.
For a cluster the role did not bootstrap, set `cluster_token`.
The role stops if it finds no token, so a node never restarts without one.

### Node pools

Set the variables per node pool through inventory groups:

```yaml
# group_vars/pool_storage/rke2.yml
rke2_node_labels:
  example.com/pool: storage
rke2_node_taints:
  - example.com/pool=storage:NoSchedule
rke2_node_managed_prefix: example.com/
rke2_kubelet_args:
  - max-pods=110
```

Roll the node pool out on its own:

```bash
ansible-playbook -i inventory.yml site.yml --limit pool_storage
```

The role reads each node from the API server through `kubectl` on `rke2_first_server` and applies the difference.
With `rke2_node_managed_prefix` set, a node that leaves a node pool also loses the old labels and taints with that prefix.
Without it, the role only adds and never removes.
Labels under `node-role.kubernetes.io/` are not allowed for self-registration, so use your own prefix.

A changed label, taint or kubelet argument also changes the RKE2 config, so the node restarts once.
Restarts go one node at a time, and each one waits for the node to become healthy.
A node that fails its health check stops the rollout, so the remaining nodes keep running untouched.

### kubectl and calicoctl on nodes

As root, both work without any environment variable:

```bash
kubectl get nodes
calicoctl get nodes
```

Regular users go through `sudo`.
Servers get the admin kubeconfig.
Agents get only the kubelet credentials, so `kubectl get node <own name>` works there, and listing all nodes or reading secrets does not.
`calicoctl` is installed on all nodes and configured on servers only.

### Upgrades

Set `rke2_version` to the target version and run the upgrade entry point with `serial: 1`:

```yaml
- name: Upgrade the servers first, then the agents
  hosts: servers:agents
  serial: 1
  tasks:
    - name: Upgrade this node
      ansible.builtin.include_role:
        name: mtze.rke2
        tasks_from: upgrade
```

The upgrade refuses a batch of more than one node.
A node already at `rke2_version` is left alone, so you can run the playbook again after a failure.

Before a node moves, the role stops if any of these fails:

| Check | Rule |
|---|---|
| Release assets | The release ships the `rke2.linux` archive for the node architecture. |
| cgroup | Kubernetes 1.35 and newer needs cgroup v2. |
| Kernel | At least `rke2_upgrade_min_kernel`. |
| Direction | Downgrades are refused. |
| Minor version step | A server moves at most one minor version. Plan several runs for a larger jump. |
| Order | An agent moves only when all servers run the target version. |

Before `rke2_first_server` moves, the role saves an etcd snapshot.
It stays on S3 when `rke2_etcd_s3` is set.
Otherwise the role copies it to `rke2_upgrade_snapshot_local_path` on the machine that runs Ansible.

Each node is drained, installed and restarted, and the role waits until the node is `Ready` at the new version.
Servers also have to pass the etcd health check.
A node that was cordoned before stays cordoned, and cordoned servers can block the RKE2 Helm jobs.

An upgrade only moves the version.
Run the normal playbook afterwards to apply config changes.

### Longhorn V2 Data Engine

Set `install_longhorn_v2_dependencies: true` on every node pool that stores or attaches V2 volumes:

```yaml
# group_vars/pool_storage/rke2.yml
install_longhorn_v2_dependencies: true
```

The role then does this on each of those nodes:

| Step | Detail |
|---|---|
| Kernel check | Stops below kernel 6.7. Debian 11 and 12 ship older kernels and need a newer one first. |
| CPU check | Stops on x86 without SSE4.2. |
| Kernel modules | Loads `vfio_pci`, `uio_pci_generic` and `nvme-tcp` now and at every boot. A missing module stops the run. |
| Huge pages | Reserves `longhorn_v2_huge_pages` now through `sysctl` and at every boot through GRUB, then restarts RKE2 once so that the kubelet sees them. No reboot is needed. |

If the kernel cannot provide the huge pages at runtime because memory is fragmented, the run stops. A reboot fixes that, because GRUB is already configured.

The role does not touch the data disk. The V2 Data Engine needs a raw block device without a file system or partition table, which Longhorn then uses as a `block` disk. Do not mount it or add it to `/etc/fstab`. Enabling the engine and adding the disk are Longhorn settings, outside this role.

Each node with V2 volumes gives up the huge pages as memory, plus at least one CPU core for SPDK. Longhorn's interrupt mode, `data-engine-interrupt-mode-enabled`, saves most of that CPU on idle nodes at a small cost in latency.

---

## Security

| Feature | Default | How to tighten it |
|---|---|---|
| [Agent token](#agent-token) | Generated at bootstrap, used by agents | Set it from a vault, migrate existing clusters by hand |
| [No ingress controller](#no-ingress-controller) | `[none]` | Nothing to do, `[traefik]` opts in |
| [Control plane protection](#control-plane-protection) | Policy in `Warn`, no taint | Add the taint, switch to `Deny` |
| [Node ports](#node-ports) | Off | Set `rke2_protected_node_networks` |
| [Audit log](#audit-log) | On | Ship it off the node |
| [seccomp](#seccomp) | On | Require it per namespace with Pod Security |
| [CIS profile](#cis-profile) | Off | Set `rke2_cis_profile: cis` on a fresh installation |
| [Supply chain](#supply-chain) | `calicoctl` checksum, kube-vip digest | Pin your own values |
| [Token handling](#token-handling) | Never printed | Nothing to do |

### Agent token

The server token grants full access to the cluster, so it does not belong on an agent.
RKE2 offers a second secret, the agent token, that lets agents join but not servers.

A new cluster gets it from the start.
At bootstrap the role creates a secret on `rke2_first_server`, in `rke2_agent_token_file`, and every server gets it as `agent-token` in its config.
Agents read `/var/lib/rancher/rke2/server/agent-token` from the first server and join with that.

To tighten it, set `rke2_agent_token` from a vault before the bootstrap.
A replaced first server then keeps the same secret.
Without a vault, copy `rke2_agent_token_file` to the replacement before you run the role.

**The role does not add an agent token to a running cluster by itself.**
A cluster bootstrapped without one keeps using the server token for its agents until you migrate it.
RKE2 does not write a late `agent-token` to its datastore, and every second restart of a server then fails with `passwd newer than datastore`.
A token rotation writes it, so the migration has a fixed order:

1. Set `rke2_agent_token` and run the role with `--limit servers`. The servers restart one at a time.
2. Before any server restarts again, rotate the server token on one server:

   ```bash
   rke2 token rotate --token "$(cat /var/lib/rancher/rke2/server/node-token)"
   ```

3. If `cluster_token` is in your variables, set it to the new content of `node-token`.
4. Run the role on all nodes. Servers take the new server token, and agents move to the agent token.

If a server already refuses to start with that error, remove `/var/lib/rancher/rke2/server/cred/passwd`, start it, and continue with step 2.

The server token also encrypts the data a snapshot restore needs, so store the current token with your snapshots.

### No ingress controller

RKE2 deploys an ingress controller by default, Traefik from v1.36.
The role sets `ingress-controller: none` through `rke2_ingress_controller`, so a cluster runs only what you deploy.
Set `[traefik]` to get the packaged controller.

### Control plane protection

A taint keeps ordinary pods off the servers, but anyone who can create a pod can add a toleration.
The role therefore combines a taint with an admission policy.

The role does not set the taint by itself.
Set it on servers through `rke2_node_taints`:

```yaml
# group_vars/servers/rke2.yml
rke2_node_taints:
  - CriticalAddonsOnly=true:NoExecute
```

**On an existing cluster, `NoExecute` evicts running pods at once, so plan a window.**
The role applies the taint to joined nodes through `kubectl`.
Do not set this taint on a cluster without agents, because the pods would have nowhere to go.

`rke2_control_plane_policy` deploys a ValidatingAdmissionPolicy that applies to pods outside `rke2_system_namespaces`.
It flags pods that tolerate `CriticalAddonsOnly`, `node-role.kubernetes.io/control-plane`, `node-role.kubernetes.io/etcd`, `node-role.kubernetes.io/master`, or every taint.
The policy needs Kubernetes 1.30 or newer.

| Value | Effect |
|---|---|
| `Warn` | The API server warns the client and records it in the audit log. Pods still run. |
| `Deny` | The API server refuses the pod. |
| empty | The role does not deploy the policy. |

Roll it out in this order:

1. Start with `Warn`, the default.
2. Find the namespaces with pods that the policy flags, for example with the command below.
3. Add every namespace with a DaemonSet that tolerates all taints to `rke2_system_namespaces`. Fix or remove everything else.
4. Switch to `rke2_control_plane_policy: Deny`.

```bash
kubectl get pods -A -o json | jq -r '.items[] | select(any(.spec.tolerations[]?; (.key // "") | . == "" or IN("CriticalAddonsOnly", "node-role.kubernetes.io/control-plane", "node-role.kubernetes.io/etcd", "node-role.kubernetes.io/master"))) | .metadata.namespace' | sort -u
```

The role applies a changed policy at once, so a switch between `Warn` and `Deny` takes effect during the run.
Turning the policy off later needs a manual `kubectl delete`, because removing a setting does not remove the deployed object.
The role also leaves its manifest on the servers.
Set `rke2_control_plane_policy: ""`, delete the manifest on every server, then delete the objects:

```bash
rm /var/lib/rancher/rke2/server/manifests/rke2-control-plane-policy.yaml  # on every server
kubectl delete validatingadmissionpolicybinding,validatingadmissionpolicy rke2-control-plane-tolerations
```

The taint uses no managed prefix, so remove it with `kubectl taint node <node> CriticalAddonsOnly-` after you take it out of `rke2_node_taints`.

### Node ports

Pods can reach the node network, including the kubelet and etcd ports.
With Calico, the role can block this.
The protection is off by default and does nothing with another CNI.

Set `rke2_protected_node_networks` to the CIDRs of your nodes.
Pods outside `rke2_system_namespaces` then cannot reach `rke2_protected_node_ports`.

```yaml
rke2_protected_node_networks:
  - 10.20.30.0/24
```

Namespaces that scrape node metrics, such as monitoring, belong in `rke2_system_namespaces`.
That list also exempts them from the admission policy, so add only namespaces you trust on both counts.

Port 6443, the API server, stays reachable.
To turn the protection off, delete `/var/lib/rancher/rke2/server/manifests/rke2-node-ports-policy.yaml` on every server and remove the `GlobalNetworkPolicy` and `Tier` named `rke2-node-protection` by hand.

### Audit log

`rke2_audit_log` writes who did what and when to `/var/lib/rancher/rke2/server/logs/audit.log` on every server.
The policy logs at metadata level, so the content of secrets and requests stays out of the log.
It skips health checks, leases and events.

To tighten it, ship the file off the node.
Set retention through `rke2_kube_apiserver_args`, for example `audit-log-maxage=30`.

### seccomp

`rke2_kubelet_seccomp_default` sets `seccomp-default=true` on every kubelet.
Pods without a seccomp profile then run with the profile of the container runtime.
A pod that needs more asks for it in its own `securityContext`.

### CIS profile

`rke2_cis_profile: cis` sets the RKE2 CIS profile on every node.
The role installs the kernel parameters that the profile needs and creates the `etcd` user on servers.

Use it on fresh installations only.
The profile makes Pod Security stricter, so workloads that run today may be refused.
The role does not check this for you.

### Supply chain

`calicoctl` is verified against the checksums of its release, and `calicoctl_checksum` pins your own value.
The kube-vip image is pinned by digest for tested versions through `kube_vip_digests`.
Add an entry there when you use another version, otherwise that version goes by its tag.
The RKE2 install script comes from `rke2_download_url` without a checksum, so point it at a reviewed copy if you need more.

### Token handling

Token tasks run with `no_log`, so tokens are never printed, not even with `debug_output: true`.
The config task runs with `diff: false`, so tokens and S3 credentials do not show in `--diff`.
`/etc/rancher/rke2/config.yaml` has mode `0600`.

### What the role does not cover

| Topic | Where it belongs |
|---|---|
| Pod Security levels per namespace | Namespace labels, set with your workloads or cluster configuration |
| Stronger sandboxing for untrusted code | A dedicated runtime and `RuntimeClass`, set up outside this role |
| Tenant RBAC | Your cluster configuration |
| Host patching | Your OS maintenance process |
| Resource reservations | `rke2_kubelet_args`, the role sets none. Give servers a higher `kube-reserved`, for example `kube-reserved=cpu=1,memory=2Gi` |

---

## Example playbooks

The playbooks below assume `rke2_node_type` and `cluster_name` in the inventory, as in the [quick start](#quick-start).

### Single server with agents

```yaml
- name: Bootstrap the server
  hosts: server-1.example.com
  any_errors_fatal: true
  roles:
    - role: mtze.rke2
      vars:
        first_node_install: true

- name: Join the agents
  hosts: agents
  any_errors_fatal: true
  roles:
    - role: mtze.rke2
      vars:
        control_plane_server: https://server-1.example.com:9345
```

### HA control plane with kube-vip

kube-vip runs on every server when `control_plane_vip` is set.
All nodes get `tls-san` entries for the VIP and its hostname, and the fetched kubeconfig points at the VIP.

```yaml
# group_vars/all/rke2.yml
control_plane_vip: 10.20.30.1
control_plane_vip_hostname: control-plane.example.com
control_plane_vip_interface: eth0
```

```yaml
- name: Bootstrap the first server
  hosts: server-1.example.com
  any_errors_fatal: true
  roles:
    - role: mtze.rke2
      vars:
        first_node_install: true

- name: Join all other nodes
  hosts: servers:agents
  any_errors_fatal: true
  roles:
    - mtze.rke2
```

### Dual-stack cluster

Both `cluster_cidr` and `service_cidr` must list an IPv4 and an IPv6 range.
Each node gets a subnet of each family from `cluster_cidr`, so make that range large enough.
A dual-stack VIP through kube-vip is not supported.

```yaml
# group_vars/all/rke2.yml
cluster_cidr: 198.18.0.0/16,fcfe::1:0:0/96
service_cidr: 198.19.0.0/16,fcfe::1:ffff:0/112
node_cidr_mask_ipv4: 24
node_cidr_mask_ipv6: 112
```

Use the same playbook as in the [quick start](#quick-start).

### Hardened servers

```yaml
# group_vars/servers/rke2.yml
rke2_node_type: server
rke2_node_taints:
  - CriticalAddonsOnly=true:NoExecute
rke2_control_plane_policy: Deny
rke2_protected_node_networks:
  - 10.20.30.0/24
```

Read [Control plane protection](#control-plane-protection) before you use this on an existing cluster.

---

## Migration

### From v2

**A normal run refuses a version change.**
If a node runs another version than `rke2_version`, the role stops.
The default of `rke2_version` moved to `v1.35.9+rke2r1`, so pin it to what runs, or [upgrade](#upgrades).

**Expect one restart per node on the first run.**
`node-ip` now comes from facts, and the config gains new entries.
Restarts go one node at a time, and the next node waits for health.
Set `node_ips` per host where the default route is not the cluster interface.
Check this before the first run: a changed IP on a server breaks its etcd member.

**Existing clusters keep the server token on their agents.**
Only clusters bootstrapped with v3 get an agent token by themselves.
To move an existing cluster, follow the [migration](#agent-token) in exactly that order.

**Servers get `ingress-controller: none`, also on clusters that relied on the packaged controller.**
Set `rke2_ingress_controller` before the first run if you want one.
Use `[traefik]`, or `[ingress-nginx]` and keep `rke2-ingress-nginx` out of `disabled_components`.

**The audit log and seccomp default are on.**
Servers write an [audit log](#audit-log), and pods without a profile get the [seccomp](#seccomp) profile of the runtime.
Set `rke2_audit_log: false` or `rke2_kubelet_seccomp_default: false` to keep the old behavior.

**The control plane policy is deployed in `Warn` mode.**
No pod is refused, but clients see warnings for pods that the policy flags.
See the [rollout](#control-plane-protection) before you add the taint or switch to `Deny`.
On clusters older than Kubernetes 1.30, set `rke2_control_plane_policy: ""`.

**`kubectl` comes from RKE2.**
`kubectl_version` and `kubectl_checksum` are gone.
`/usr/local/bin/kubectl` becomes a link, and `/root/.kube/config` is replaced by a link to the local kubeconfig.

**kube-vip changed.**
It runs on all servers, `kube_vip_rbac_manifest_url` is gone, and the manifest uses the option names of current kube-vip.
The default version is `v1.3.1`.

**A node without a token stops the play.**
Keep `rke2_node_type` and `cluster_name` in the inventory, or set `rke2_first_server`.

**Tokens are no longer printed**, not even with `debug_output: true`.

**Longhorn preparation does more.**
With `install_longhorn_dependencies: true`, nodes also install `cryptsetup`, enable `iscsid`, load kernel modules and get a multipath blacklist.

**The minimum is Ansible Core 2.17, and the list of supported platforms changed.**
See [Requirements](#requirements).

### From v1

Move to v2 first, then follow the notes above.
Two v2 changes still matter: `rke2_node_type` is required on every host, and `additional_hostnames` only adds to the `tls-san` entries the role always writes.

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

Run the tests, which need neither hosts nor a cluster:

```bash
ansible-playbook -i tests/inventory.yml tests/main.yml --skip-tags needs_real_host
```

The tag `needs_real_host` marks tasks that need GitHub or change the boot configuration of a host.
CI runs the linter and the tests on every push and pull request.

To test against real RKE2 on throwaway local machines, use the skill in [.claude/skills/orbstack-integration-test](.claude/skills/orbstack-integration-test/SKILL.md).
[AGENTS.md](AGENTS.md) holds the rules and conventions for changing this repository.

### Refreshing the kube-vip manifest

[templates/kube-vip.yml.j2](templates/kube-vip.yml.j2) derives from the output of the [kube-vip manifest generator](https://kube-vip.io/docs/installation/daemonset/).
When you change `kube_vip_version`, generate the manifest for that version, compare it with the template, and add the new digest to `kube_vip_digests`.

```bash
docker run --rm ghcr.io/kube-vip/kube-vip:v1.3.1 manifest daemonset \
  --arp \
  --interface eth0 \
  --address 10.20.30.1 \
  --controlplane \
  --taint \
  --leaderElection \
  --inCluster
```

### Releasing

Create a GitHub release.
The [Push to Ansible Galaxy](.github/workflows/main.yml) workflow imports the role to Galaxy.

---

## License

MIT

## Acknowledgements

This role is based on the [work](https://www.youtube.com/watch?v=QqSgiezqMAA&t=472s) of Adrian Goins.

## Author

Matthias Linhuber
[mtze.me](https://mtze.me)
