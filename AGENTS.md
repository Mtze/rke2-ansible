# Working on this repository

`mtze.rke2` is an Ansible role that installs and operates RKE2 clusters on Debian-family hosts. It has no collection dependencies, keep it that way. The [README](README.md) explains what the role does and why. This file covers how to change it.

## Commands

Run both before you call a change done:

```bash
ansible-lint
ansible-playbook -i tests/inventory.yml tests/main.yml --skip-tags needs_real_host
```

The tests need neither hosts nor a cluster. For changes that RKE2 itself has to accept, use the skill [orbstack-integration-test](.claude/skills/orbstack-integration-test/SKILL.md), which runs the role on real RKE2 on throwaway machines.

Never run the role against real hosts, commit, push or release without the maintainer's explicit approval.

## Layout

| Path | Content |
| --- | --- |
| `defaults/main.yml` | Everything a user can set. Every variable is documented in the README. |
| `vars/main.yml` | Derived values such as `rke2_bootstrap`, not meant to be overridden |
| `tasks/main.yml` | The normal run |
| `tasks/upgrade.yml`, `tasks/upgrade-node.yml` | The upgrade entry point, `tasks_from: upgrade` with `serial: 1` |
| `filter_plugins/` | Logic too involved for Jinja, as plain Python |
| `files/restart-and-wait.sh` | The only way the role restarts RKE2, used by the handler and the upgrade |
| `templates/rke2_config.yml.j2` | The RKE2 config |
| `tests/` | Localhost suite, `tests/bin/` holds the fake binaries |
| `docs/plans/` | One plan per larger change |

## Rules the role depends on

Each of these exists because something broke without it.

- **A normal run never upgrades.** It refuses when the installed version differs from `rke2_version`. Version changes go through `tasks_from: upgrade` only.
- **No `run_once` on a decision that differs per host.** Facts survive between plays. `run_once` with a `when` decides on the first host alone, so a first host that still holds a token skips the task for everyone. Let each host ask for itself. `run_once` is fine for creating something once.
- **Find the first server through `rke2_first_server`,** never through the first play host. With `--limit <pool>` the play may hold agents only.
- **Do not rely on RKE2 to notice a changed manifest.** It can take until its next restart. Security policies are applied with `kubectl` as soon as they change.
- **Every RKE2 restart goes through `files/restart-and-wait.sh`,** so the next node waits for health. Do not add a plain `service: state=restarted` for `rke2-server` or `rke2-agent`.
- **Tokens stay secret.** Use `no_log: true` on every task that touches one, and `diff: false` on the config template. S3 credentials and the agent token secret are rendered on servers only.
- **Agents join with the agent token where one exists.** Never add `agent-token` to a running cluster automatically: every second server restart then fails with `passwd newer than datastore` until `rke2 token rotate` has run.
- **Conditions must be booleans.** Write `x | length > 0`, not `x`. `ansible-core` 2.19 and newer fail on anything else.
- **Tasks that render the config need the token.** Token discovery is tagged `always` for that reason.
- **`get_url` needs `force: true`** when a newer version should replace an existing file.
- **The role never formats disks.** Disk preparation belongs to the playbooks that use the role.
- **Defaults must not surprise a running cluster.** New options stay off or in a reporting mode unless they cannot break a workload, or a major release changes a default on purpose and the migration section of the README says so.

## Making a change

**New variable:** add it to `defaults/main.yml` with a comment, add a row to the matching table in the README, and cover it in `tests/main.yml`.

**New task:** give it an FQCN module name, a descriptive `name`, `become: true` where needed, and tags like its neighbors. If it can only run on a real host, tag it `needs_real_host` and say so in the test.

**New logic with branches:** put it in `filter_plugins/` and add a table-driven case in `tests/main.yml`.

**Testing a change:** a test is worth keeping only if it fails when the code is wrong. Break the code once on purpose and watch the test fail. Do not rewrite an existing test before you have checked that the code is right.

**Behavior that users notice:** add it to the migration section of the README in the same change. Large changes get a file in `docs/plans/`.

**Bumping dependencies:**
- `rke2_version`: check that the tag ships release assets.
- `calicoctl_version`: use the Calico version in the release notes of that RKE2 version.
- `kube_vip_version`: add the image digest to `kube_vip_digests` and compare the template with the generated manifest, see the README. The selector of the DaemonSet is immutable, keep it.

## Style

- Comments explain why, not what, in plain language.
- No em dashes or en dashes anywhere, only hyphens.
- Documentation is in English, in active voice and present tense.
- Use the terms "server" and "agent" for node types and "node pool" for pools.

## Releasing

Create a GitHub release with a semantic version tag. The workflow `.github/workflows/main.yml` imports the role to Ansible Galaxy. Consumers pin a tag, so a change reaches a cluster only when its pin moves.
