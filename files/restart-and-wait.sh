#!/bin/sh
# Restart RKE2 and block until this node serves again, so callers can go one node at a time.
# Usage: restart-and-wait.sh <server|agent> <node name> <timeout in seconds>
set -eu

type=$1
node=$2
limit=$3

PATH="$PATH:/var/lib/rancher/rke2/bin"
if [ "$type" = server ]; then
  kubeconfig=/etc/rancher/rke2/rke2.yaml
else
  kubeconfig=/var/lib/rancher/rke2/agent/kubelet.kubeconfig
fi

# The RKE2 units have no start timeout, a node that cannot come up would block the run forever.
timeout "$limit" systemctl restart "rke2-$type" || {
  echo "rke2-$type did not restart within ${limit}s" >&2
  exit 1
}

healthy() {
  ready=$(kubectl --kubeconfig "$kubeconfig" get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}') || return 1
  [ "$ready" = True ] || return 1
  # The API server of a server talks to its local etcd member only, so this checks that member.
  [ "$type" != server ] || [ "$(kubectl --kubeconfig "$kubeconfig" get --raw /readyz/etcd)" = ok ]
}

waited=0
until healthy 2>/dev/null; do
  if [ "$waited" -ge "$limit" ]; then
    echo "$node did not become healthy within ${limit}s" >&2
    exit 1
  fi
  sleep 5
  waited=$((waited + 5))
done
