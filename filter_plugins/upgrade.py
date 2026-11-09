"""Decide whether a node may move to a new RKE2 version."""
import re

# Kubernetes 1.35 refuses to start the kubelet on cgroup v1.
CGROUP_V2_REQUIRED_FROM_MINOR = 35


def _numbers(version):
    match = re.match(r"v?(\d+)\.(\d+)(?:\.(\d+))?", version)
    return tuple(int(n or 0) for n in match.groups())


def upgrade_problems(installed, target, node_type, cgroup_v2, kernel, min_kernel, server_nodes=()):
    if not installed:
        return ["RKE2 is not installed on this node, a normal run installs it"]

    old, new = _numbers(installed), _numbers(target)
    problems = []
    if new < old:
        problems.append(f"{target} is older than the installed {installed}, downgrades are not supported")
    if node_type == "server" and new[1] - old[1] > 1:
        problems.append(f"servers move at most one minor version, {installed} to {target} is too far")
    if new[1] >= CGROUP_V2_REQUIRED_FROM_MINOR and not cgroup_v2:
        problems.append(f"{target} needs cgroup v2, this node runs cgroup v1")
    if _numbers(kernel) < _numbers(min_kernel):
        problems.append(f"kernel {kernel} is older than the required {min_kernel}")

    behind = [n["metadata"]["name"] for n in server_nodes if n["status"]["nodeInfo"]["kubeletVersion"] != target]
    if behind:
        problems.append(f"upgrade the servers first, not yet at {target}: {', '.join(behind)}")
    return problems


class FilterModule:
    def filters(self):
        return {"upgrade_problems": upgrade_problems}
