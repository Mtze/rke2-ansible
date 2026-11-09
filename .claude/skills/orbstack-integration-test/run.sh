#!/bin/bash
# Runs the role against real RKE2 on throwaway OrbStack machines. See SKILL.md.
# Usage: run.sh [--keep]     --keep leaves the machines running for inspection
set -u

REPO=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/rke2-orb.XXXXXX")
KEEP=${1:-}

OLD_ROLE_TAG=v2.0.0
VERSION="v1.35.9+rke2r1"
UPGRADE_TO="v1.35.10+rke2r1"
NEWEST="v1.36.6+rke2r1"
S=rke2-it-s
A=rke2-it-a
N=rke2-it-n
C=rke2-it-c
F=rke2-it-f
B=rke2-it-b
FAILED=0

# Reads the commands from stdin, so that quotes survive the trip through orb.
on() { printf '%s\n' "$2" | orb -m "$1" sudo -i bash; }
K() { on "$S" "/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml $1"; }

check() {  # check <what> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1: wanted [$2], got [$3]"
    FAILED=$((FAILED + 1))
  fi
}

play() {  # play <inventory> <playbook> [ansible args...], leaves the output in $WORK/last
  local inventory=$1 playbook=$2
  shift 2
  ansible-playbook -i "$WORK/$inventory" "$WORK/$playbook" "$@" > "$WORK/last" 2>&1
  local rc=$?
  grep -E 'fatal:|^ERROR' "$WORK/last" | cut -c1-300
  return $rc
}
changed() { grep -E ' : ok=' "$WORK/last" | sed -E 's/.*changed=([0-9]+).*/\1/' | awk '{s+=$1} END {print s+0}'; }

token_kind() {
  on "$1" 'grep ^token: /etc/rancher/rke2/config.yaml | sed -E "s/^token: K10[0-9a-f]+::([a-z]+):.*/\1/"'
}
started() { on "$1" "systemctl show -p ActiveEnterTimestamp --value $2"; }

new_machine() {
  orb delete -f "$1" >/dev/null 2>&1
  orb create ubuntu:noble "$1" >/dev/null || { echo "cannot create $1"; exit 1; }
  sleep 3
  orb -m "$1" sudo apt-get -qq -y install python3 >/dev/null 2>&1
}

try_pod() {  # try_pod <namespace> <tolerations as JSON>, prints what the API server answers
  K "-n $1 run t --image=busybox:1.37 --dry-run=server --overrides '{\"apiVersion\":\"v1\",\"spec\":{\"tolerations\":$2}}' 2>&1"
}

probe() {  # probe <namespace> <pod>, tries the targets from a pod on the agent
  local script='for t in '"$S_IP:10250 $S_IP:9345 $A_IP:10250 $S_IP:6443 1.1.1.1:443"'; do nc -w3 -z ${t%:*} ${t#*:}; echo $t=$?; done'
  K "-n $1 run $2 --image=busybox:1.37 --restart=Never --overrides '{\"apiVersion\":\"v1\",\"spec\":{\"nodeName\":\"$A\"}}' --command -- sh -c '$script'" >/dev/null 2>&1
  for _ in $(seq 1 40); do
    [ "$(K "-n $1 get pod $2 -o jsonpath={.status.phase}")" = Succeeded ] && break
    sleep 5
  done
  K "-n $1 logs $2"
  K "-n $1 delete pod $2 --now" >/dev/null 2>&1
}

# Each cluster goes away after its stage, several machines at once fill the disk.
drop() { [ "$KEEP" = --keep ] || orb delete -f "$@" >/dev/null 2>&1; }

cleanup() {
  if [ "$KEEP" = --keep ]; then
    echo "Kept: $S $A $N $C $F $B, work dir $WORK"
  else
    for m in "$S" "$A" "$N" "$C" "$F" "$B"; do orb delete -f "$m" >/dev/null 2>&1; done
    rm -rf "$WORK"
  fi
}
trap cleanup EXIT

mkdir "$WORK/old-role"
git -C "$REPO" archive "$OLD_ROLE_TAG" | tar -x -C "$WORK/old-role"

new_machine "$S"
new_machine "$A"
S_IP=$(orb -m "$S" hostname -I | awk '{print $1}')
A_IP=$(orb -m "$A" hostname -I | awk '{print $1}')
echo "server $S_IP, agent $A_IP"

cat > "$WORK/cluster.yml" <<EOF
---
all:
  vars:
    ansible_host: orb
    ansible_python_interpreter: /usr/bin/python3
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
    cluster_name: it
    rke2_version: "$VERSION"
    fetch_kube_config: false
    # OrbStack masks systemd-modules-load, the machines share the kernel of the host.
    install_longhorn_dependencies: false
    # The old role renders the IPv6 mask on a single-stack cluster, which crashes the controller manager.
    node_cidr_mask_ipv6: ""
    control_plane_server: "https://$S_IP:9345"
    rke2_upgrade_snapshot_local_path: "$WORK/snapshots"
    rke2_upgrade_drain_args: [--ignore-daemonsets, --delete-emptydir-data, --disable-eviction, --force, --timeout=120s]
  children:
    servers:
      hosts:
        $S:
          ansible_user: $S
          rke2_node_type: server
    agents:
      hosts:
        $A:
          ansible_user: $A
          rke2_node_type: agent
EOF

cat > "$WORK/single.yml" <<EOF
---
all:
  vars:
    ansible_host: orb
    ansible_python_interpreter: /usr/bin/python3
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
    fetch_kube_config: false
    install_longhorn_dependencies: false
    rke2_node_type: server
  hosts:
    $N:
      ansible_user: $N
      cluster_name: newest
      rke2_version: "$NEWEST"
    $C:
      ansible_user: $C
      cluster_name: cis
      rke2_version: "$VERSION"
      rke2_cis_profile: cis
EOF

cat > "$WORK/fresh-cluster.yml" <<EOF
---
all:
  vars:
    ansible_host: orb
    ansible_python_interpreter: /usr/bin/python3
    ansible_ssh_common_args: "-o StrictHostKeyChecking=no"
    cluster_name: fresh
    rke2_version: "$VERSION"
    fetch_kube_config: false
    install_longhorn_dependencies: false
  children:
    servers:
      hosts:
        $F:
          ansible_user: $F
          rke2_node_type: server
    agents:
      hosts:
        $B:
          ansible_user: $B
          rke2_node_type: agent
EOF

for pair in "old:$WORK/old-role" "new:$REPO"; do
  name=${pair%%:*}
  role=${pair#*:}
  cat > "$WORK/site-$name.yml" <<EOF
---
- name: Bootstrap
  hosts: servers
  roles:
    - role: $role
      vars:
        first_node_install: true
- name: Join
  hosts: all
  roles:
    - role: $role
EOF
done

cat > "$WORK/fresh.yml" <<EOF
---
- name: Install
  hosts: all
  roles:
    - role: $REPO
      vars:
        first_node_install: true
EOF

cat > "$WORK/upgrade.yml" <<EOF
---
- name: Upgrade
  hosts: servers:agents
  serial: 1
  tasks:
    - name: Upgrade this node
      ansible.builtin.include_role:
        name: $REPO
        tasks_from: upgrade
EOF

echo "=== install with the old role $OLD_ROLE_TAG"
play cluster.yml site-old.yml -e install_calicoctl=false; check "old role installs" 0 $?
check "agent starts with the server token" server "$(token_kind "$A")"

echo "=== migrate to this role"
play cluster.yml site-new.yml; check "migration run" 0 $?
check "agent keeps the server token on a running cluster" server "$(token_kind "$A")"
check "server gets no agent token by itself" 0 "$(on "$S" 'grep -c "^agent-token:" /etc/rancher/rke2/config.yaml')"
check "both nodes Ready" 2 "$(K "get nodes --no-headers" | grep -c ' Ready')"

echo "=== repeat run"
before=$(started "$A" rke2-agent)
play cluster.yml site-new.yml; check "repeat run" 0 $?
check "repeat run changes nothing" 0 "$(changed)"
check "agent not restarted" "$before" "$(started "$A" rke2-agent)"

echo "=== restarts on the migrated cluster"
for i in 1 2; do
  on "$S" 'timeout 240 systemctl restart rke2-server'; check "server restart $i" 0 $?
done

echo "=== defaults"
check "no ingress controller" 0 "$(K "get pods -A --no-headers" | grep -ciE 'ingress|traefik')"
check "audit log at metadata level" Metadata "$(on "$S" 'tail -1 /var/lib/rancher/rke2/server/logs/audit.log' | sed -E 's/.*"level":"([A-Za-z]+)".*/\1/')"
check "seccomp default" 1 "$(on "$S" 'grep -c seccomp-default=true /etc/rancher/rke2/config.yaml')"
check "kubectl on the server without KUBECONFIG" 2 "$(on "$S" 'kubectl get nodes --no-headers | wc -l' | tr -d ' ')"
check "kubectl on the agent without KUBECONFIG" 1 "$(on "$A" "kubectl get node $A --no-headers | wc -l" | tr -d ' ')"
check "agent cannot read secrets" 0 "$(on "$A" 'kubectl get secrets -A --no-headers 2>/dev/null | wc -l' | tr -d ' ')"
check "calicoctl without environment" 3 "$(on "$S" 'calicoctl get nodes 2>/dev/null | grep -c .' | tr -d ' ')"
binding() { K "get validatingadmissionpolicybinding -o jsonpath={.items[*].spec.validationActions}"; }
for _ in $(seq 1 36); do
  [ "$(binding)" = '["Warn","Audit"]' ] && break
  sleep 5
done
check "policy defaults to Warn" '["Warn","Audit"]' "$(binding)"

echo "=== Deny policy and node port protection"
play cluster.yml site-new.yml -e rke2_control_plane_policy=Deny -e "{\"rke2_protected_node_networks\": [\"$S_IP/32\", \"$A_IP/32\"]}"
check "policy run" 0 $?
check "policy switched to Deny" '["Deny"]' "$(binding)"
K "create namespace tenant" >/dev/null 2>&1
check "tenant cannot tolerate every taint" 1 "$(try_pod tenant '[{"operator":"Exists"}]' | grep -c 'denied')"
check "tenant cannot tolerate the control plane" 1 "$(try_pod tenant '[{"key":"CriticalAddonsOnly","operator":"Exists"}]' | grep -c 'denied')"
check "tenant can tolerate other taints" 0 "$(try_pod tenant '[{"key":"foo","operator":"Exists"}]' | grep -c 'denied')"
check "kube-system is exempt" 0 "$(try_pod kube-system '[{"operator":"Exists"}]' | grep -c 'denied')"
tenant=$(probe tenant p1)
echo "$tenant"
for blocked in "$S_IP:10250" "$S_IP:9345" "$A_IP:10250"; do
  check "tenant blocked from $blocked" 1 "$(echo "$tenant" | grep -c "^$blocked=[1-9]")"
done
for open in "$S_IP:6443" "1.1.1.1:443"; do
  check "tenant reaches $open" "$open=0" "$(echo "$tenant" | grep "^$open=")"
done
check "kube-system reaches the kubelet" "$S_IP:10250=0" "$(probe kube-system p2 | grep "^$S_IP:10250=")"

echo "=== upgrade"
play cluster.yml site-new.yml -e "rke2_version=$UPGRADE_TO"
check "normal run refuses a version change" 2 $?
grep -q 'tasks_from: upgrade' "$WORK/last"; check "and says why" 0 $?
play cluster.yml upgrade.yml -e "rke2_version=$UPGRADE_TO"
rc=$?
check "upgrade run" 0 $rc
if [ $rc -ne 0 ]; then
  echo "--- rke2-server journal"
  on "$S" 'journalctl -u rke2-server --no-pager -n 40 | cut -c1-300'
fi
check "server at the new version" "$UPGRADE_TO" "$(K "get node $S -o jsonpath={.status.nodeInfo.kubeletVersion}")"
check "agent at the new version" "$UPGRADE_TO" "$(K "get node $A -o jsonpath={.status.nodeInfo.kubeletVersion}")"
check "nodes uncordoned" 0 "$(K "get nodes --no-headers" | grep -c SchedulingDisabled)"
check "etcd healthy" ok "$(K "get --raw /readyz/etcd")"
check "policy still Deny after the restart" '["Deny"]' "$(binding)"
check "snapshot copied off the cluster" 1 "$(find "$WORK/snapshots" -name 'pre-upgrade-*' 2>/dev/null | wc -l | tr -d ' ')"
play cluster.yml upgrade.yml -e "rke2_version=$UPGRADE_TO"; check "second upgrade run" 0 $?
check "second upgrade run changes nothing" 0 "$(changed)"

echo "=== move the running cluster to an agent token"
X="-e rke2_version=$UPGRADE_TO -e rke2_control_plane_policy=Deny"
play cluster.yml site-new.yml $X -e rke2_agent_token=it-agent-secret -l servers; check "servers learn the agent token" 0 $?
on "$S" 'rke2 token rotate --token "$(cat /var/lib/rancher/rke2/server/node-token)" >/dev/null 2>&1'; check "token rotate" 0 $?
play cluster.yml site-new.yml $X -e rke2_agent_token=it-agent-secret; check "all nodes move over" 0 $?
check "agent moved to the agent token" node "$(token_kind "$A")"
for i in 1 2; do
  on "$S" 'timeout 240 systemctl restart rke2-server'; check "server restart $i after the migration" 0 $?
done
on "$A" 'timeout 120 systemctl restart rke2-agent; sleep 20'
check "both nodes Ready after the migration" 2 "$(K "get nodes --no-headers" | grep -c ' Ready')"

drop "$S" "$A"

echo "=== fresh cluster gets the agent token from the start"
new_machine "$F"
new_machine "$B"
F_IP=$(orb -m "$F" hostname -I | awk '{print $1}')
play fresh-cluster.yml site-new.yml -e "control_plane_server=https://$F_IP:9345"; check "fresh cluster" 0 $?
check "agent joins with the agent token" node "$(token_kind "$B")"
password=$(on "$F" 'sed -E "s/.*::server://" /var/lib/rancher/rke2/server/node-token')
check "worker does not hold the server password" 0 "$(on "$B" "grep -c '$password' /etc/rancher/rke2/config.yaml")"
for i in 1 2; do
  on "$F" 'timeout 240 systemctl restart rke2-server'; check "fresh server restart $i" 0 $?
done
on "$B" 'timeout 120 systemctl restart rke2-agent; sleep 20'
check "fresh agent comes back" active "$(on "$B" 'systemctl is-active rke2-agent')"

drop "$F" "$B"

echo "=== fresh install of the newest RKE2 stays without ingress"
new_machine "$N"
play single.yml fresh.yml -l "$N"; check "fresh newest install" 0 $?
check "newest runs" "$NEWEST" "$(on "$N" 'rke2 --version' | awk 'NR==1{print $3}')"
check "newest has no ingress" 0 "$(on "$N" 'kubectl get pods -A --no-headers' | grep -ciE 'ingress|traefik')"

drop "$N"

echo "=== fresh install with the CIS profile"
new_machine "$C"
play single.yml fresh.yml -l "$C"; check "fresh CIS install" 0 $?
check "CIS node Ready" 1 "$(on "$C" 'kubectl get nodes --no-headers' | grep -c ' Ready')"
check "etcd runs as its own user" etcd "$(on "$C" 'stat -c %U /var/lib/rancher/rke2/server/db/etcd')"

echo
if [ "$FAILED" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "$FAILED CHECK(S) FAILED"; exit 1; fi
