# Role update: v3.0.0

Background: the new `aet` cluster needs node pools, and rolling out a pool with `--limit` must not touch other nodes.
The findings come from the `aet-cluster-plan` in the `aet-infrastructure` repository.
A split into `v2.1.0` and `v3.0.0` was planned first, and Matthias decided on 2026-11-09 to ship everything as `v3.0.0`.

## Decisions

| Question | Decision |
| --- | --- |
| Labels and taints removed from the variables | Removed only under `rke2_node_managed_prefix`, without it the role never removes anything |
| Longhorn data disk | Handled in `aet-infrastructure`, so the role never touches disks and needs no collections. The V2 Data Engine uses a raw block device |
| Tests | Localhost suite in `tests/` with fake binaries, run in CI |
| `calicoctl` | Stays, and now works on servers without any environment variables |
| `kubectl` on nodes | The binary RKE2 ships, linked into the PATH, with `/root/.kube/config` in place |
| Default ingress controller | None. `rke2_ingress_controller` defaults to `[none]`, because RKE2 deploys Traefik from v1.36 and a cluster that brings its own Gateway or Ingress does not want that. `[traefik]` opts in |
| Control plane policy | Deployed in `Warn` by default, so an upgrade from v2 refuses no pod. `Deny` is a deliberate step after the rollout |
| Control plane taint | Not set by the role, because `NoExecute` evicts running pods at once. Operators set it through `rke2_node_taints` |
| Node port protection | Off by default, because it needs the node networks of the cluster |

## Content

| Topic | Change |
| --- | --- |
| Node pools | `rke2_node_labels`, `rke2_node_taints`, `rke2_kubelet_args`, reconciliation through `kubectl` |
| `--limit <pool>` | Token comes from the first server of the cluster, found through `cluster_name`, and the role stops rather than writing a config without a token |
| Token exposure | `no_log` on token tasks, `diff: false` on the config, token-printing debug tasks removed |
| Bootstrap | A node with etcd data never renders the bootstrap config, so full runs stop restarting the first server twice |
| Upgrades | Own entry point `tasks_from: upgrade`, one node at a time, normal runs refuse a version change |
| Preflight | Release assets, cgroup v2 from 1.35, kernel, at most one minor for servers, agents after servers |
| Restarts | Handler and upgrade share `files/restart-and-wait.sh`, which waits for `Ready` and etcd |
| Longhorn | `iscsid`, `cryptsetup`, kernel modules and a multipath blacklist |
| Agent token | Automatic at bootstrap only. Running clusters move by hand, because a late `agent-token` needs `rke2 token rotate` |
| Longhorn V2 Data Engine | Opt-in per node pool: kernel check, modules, huge pages. The data disk stays raw and is handled outside the role |
| kube-vip | All servers, RBAC shipped with the role, options aligned with v1.3 |
| New options | `rke2_ingress_controller`, `rke2_kube_apiserver_args`, etcd snapshot schedule, retention and S3 |
| Fixes found on the way | `calicoctl version --output=json` does not exist, and `get_url` without `force` never replaced a binary |
| Dependencies | RKE2 v1.35.9, calicoctl v3.32.2 (matches that RKE2), kube-vip v1.3.1, `ansible-core` up to 2.22, GitHub Actions v7 |
| Agent token | `rke2_agent_token` and `rke2_agent_token_file`, the role creates the secret on the first server, agents read `/var/lib/rancher/rke2/server/agent-token`, and `rke2 token rotate` follows after agents have moved |
| Ingress | `ingress-controller: none` on servers by default through `rke2_ingress_controller` |
| Control plane protection | Taint `CriticalAddonsOnly=true:NoExecute` through `rke2_node_taints`, plus a ValidatingAdmissionPolicy through `rke2_control_plane_policy`, with exemptions in `rke2_system_namespaces` |
| Node ports | Calico policy through `rke2_protected_node_networks` and `rke2_protected_node_ports` |
| Audit log | `rke2_audit_log`, metadata level, on by default |
| seccomp | `rke2_kubelet_seccomp_default`, on by default |
| CIS profile | `rke2_cis_profile` prepares the host, for fresh installations only The role does not enforce this, it only documents it. |
| Supply chain | `calicoctl` verified against the checksums of its release, kube-vip pinned by digest through `kube_vip_digests` |
| Out of scope | Pod Security levels per namespace, sandboxing, tenant RBAC, host patching, resource reservations through `rke2_kubelet_args` |
| Documentation | README rewritten around why the role exists and what sets it apart, with a Security section, the kube-vip note folded in from `docs/README.md` |
