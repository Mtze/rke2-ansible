---
name: orbstack-integration-test
description: Test the rke2 Ansible role against real RKE2 on throwaway OrbStack machines. Use before a release, after changing tokens, restarts, upgrades, node pools, policies or the rendered RKE2 config, or when asked to run the role on real nodes without touching a cluster.
---

# OrbStack integration test

The tests in `tests/` use fake binaries and catch logic errors. They cannot show whether RKE2 accepts what the role renders. This skill runs the role on real RKE2 on local, disposable OrbStack machines.

It has found bugs the fakes could not: an IPv6 mask that crashes the controller manager on single-stack clusters, tokens that never reached later hosts because `run_once` decided on the first host only, a late `agent-token` that stops every second server restart, and a changed policy that RKE2 only noticed at its next restart.

## Run it

```bash
.claude/skills/orbstack-integration-test/run.sh > /tmp/rke2-orb.log 2>&1
```

Run it in the background, a full run takes 25 to 35 minutes. The script prints `PASS` or `FAIL` per check, ends with a summary and exits non-zero on failure. Add `--keep` to leave the machines running for inspection.

It needs `orb`, `ansible-playbook` on the machine you run it from, internet access and about 30 GiB of free disk. With too little space `orb create` hangs without an error. It creates and deletes only machines named `rke2-it-*`. With a failing upgrade it prints the journal of the server.

## Rules

- **Do not edit the role while the script runs.** Every play reads the role straight from the working tree, so an edit changes what later stages test. Stop the run first with `pkill -f orbstack-integration-test/run.sh`.
- After a stop, delete leftovers with `orb delete -f rke2-it-s rke2-it-a rke2-it-n rke2-it-c rke2-it-f rke2-it-b`, because a killed script may not clean up.
- Keep the versions at the top of `run.sh` current. Check that a tag has release assets before you use it, some RKE2 tags have none.
- Add a stage or a `check` when you add behavior that only real RKE2 can prove.

## What it covers

| Stage | What it proves |
| --- | --- |
| Install with the old role | The starting point of a real migration, from tag `v2.0.0` |
| Migrate | A cluster from the old role stays `Ready` and keeps its server token |
| Repeat run | `changed=0` and no restart |
| Restarts | Servers keep restarting after the migration |
| Defaults | No ingress controller, audit log, seccomp, `kubectl` and `calicoctl` without environment variables |
| Deny policy and node ports | Real admission decisions, real blocked and open connections from a pod |
| Upgrade | Refusal in a normal run, then a real upgrade with snapshot, drain and uncordon |
| Move to an agent token | The documented order with `rke2 token rotate` on a running cluster |
| Fresh cluster | The agent joins with the agent token, holds no server password, and servers restart |
| Newest RKE2 | A newer minor version stays without an ingress controller |
| CIS profile | A fresh install with the hardened profile |

## What it cannot cover

The machines share the kernel of OrbStack and are closer to containers than to VMs.

| Topic | Why not | Test it on |
| --- | --- | --- |
| Longhorn tasks and the V2 Data Engine | `systemd-modules-load` is masked, there is no GRUB, and huge pages and modules belong to the shared kernel | A real VM |
| kube-vip | It needs ARP on a real interface | A real VM |
| Several servers and etcd quorum | The script runs one server to stay fast | Add a server if your change depends on it |
| Dual-stack | The machines run single-stack here | A real VM |
| x86 specifics | Apple silicon runs arm64 images, including the SSE4.2 check | A real VM |

## Working with the machines

The role reaches a machine over OrbStack SSH, with the machine name as the user:

```yaml
ansible_host: orb
ansible_user: rke2-it-s
```

Open a root shell on a machine:

```bash
orb -m rke2-it-s sudo -i
```

Read the logs of a failed node:

```bash
orb -m rke2-it-s sudo journalctl -u rke2-server --no-pager -n 100
```

Use the IP address of a machine, as `hostname -I` reports it, rather than a host name. RKE2 puts the node IP into its certificates.

A node that stays `NotReady` usually means a crash in the control plane, not the network. Check `kubectl get pods -n kube-system` and the logs of a crash-looping pod first.
