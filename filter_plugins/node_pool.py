"""Work out which kubectl arguments bring a node in line with its pool."""


def _taint_string(taint):
    value = f"={taint['value']}" if taint.get("value") else ""
    return f"{taint['key']}{value}:{taint['effect']}"


def _key_and_effect(taint):
    return taint.split("=")[0].split(":")[0], taint.rsplit(":", 1)[1]


def node_pool_args(node, labels, taints, managed_prefix=""):
    current_labels = node["metadata"].get("labels", {})
    label_args = [f"{k}={v}" for k, v in labels.items() if current_labels.get(k) != str(v)]

    current_taints = node["spec"].get("taints", [])
    current_strings = [_taint_string(t) for t in current_taints]
    taint_args = [t for t in taints if t not in current_strings]

    # An empty prefix would match every key, kubelet and cloud labels included.
    if managed_prefix:
        label_args += [f"{k}-" for k in current_labels if k.startswith(managed_prefix) and k not in labels]
        wanted = {_key_and_effect(t) for t in taints}
        taint_args += [
            f"{t['key']}:{t['effect']}-"
            for t in current_taints
            if t["key"].startswith(managed_prefix) and (t["key"], t["effect"]) not in wanted
        ]

    return {"labels": label_args, "taints": taint_args}


class FilterModule:
    def filters(self):
        return {"node_pool_args": node_pool_args}
