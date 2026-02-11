# Wazuh Server role (Rocky Linux)

This role installs Wazuh components on Rocky Linux. You can enable any combination of indexer, manager, and dashboard by setting booleans per inventory group.

## Components and packages

Wazuh ships separate packages for the indexer, manager, and dashboard (plus Filebeat for manager-to-indexer shipping). The defaults in this role map directly to those packages.

## Repository defaults

By default the role adds the Wazuh YUM repository and imports the Wazuh GPG key using the official base URL and key locations.

## Role variables (highlights)

Set these in group_vars/host_vars as needed:

```yaml
# component toggles
wazuh_install_indexer: false
wazuh_install_manager: false
wazuh_install_dashboard: false

# repo (can disable if you manage repos separately)
wazuh_manage_repo: true
wazuh_repo_baseurl: "https://packages.wazuh.com/4.x/yum/"
wazuh_repo_gpgkey: "https://packages.wazuh.com/key/GPG-KEY-WAZUH"

# connectivity
wazuh_indexer_hosts: ["https://indexer-1.example.local:9200"]
wazuh_manager_api_hosts: ["manager-1.example.local"]

# credentials (override in vault)
wazuh_indexer_admin_user: admin
wazuh_indexer_admin_password: admin
wazuh_manager_api_user: wazuh
wazuh_manager_api_password: wazuh

# lab-only: disable TLS for the indexer
wazuh_indexer_tls_enabled: true

# filebeat module (manager)
wazuh_filebeat_install_module: true
wazuh_filebeat_enable_module: true
wazuh_filebeat_module_url: "https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.3.tar.gz"

# firewalld (optional)
wazuh_manage_firewalld: false

# fapolicyd (optional)
wazuh_manage_fapolicyd: false
wazuh_fapolicyd_rules:
  - "allow perm=any all : dir=/usr/share/wazuh-dashboard/node/bin/"
  - "allow perm=any all : dir=/usr/share/wazuh-dashboard/node/fallback/bin/"
wazuh_manage_fapolicyd_trust: false
wazuh_fapolicyd_trust_files:
  - /usr/share/wazuh-dashboard/node/fallback/bin/node
```

## Inventory-driven defaults

By default, the role derives component toggles and connection targets from inventory groups:

- Hosts in `wazuh_indexer` -> `wazuh_install_indexer: true`
- Hosts in `wazuh_manager` -> `wazuh_install_manager: true`
- Hosts in `wazuh_dashboard` -> `wazuh_install_dashboard: true`
- `wazuh_indexer_hosts` is built from `wazuh_indexer` group names using `wazuh_indexer_host_scheme` and `wazuh_indexer_http_port`
- `wazuh_manager_api_hosts` uses the `wazuh_manager` group names

To disable this behavior, set:

```yaml
wazuh_auto_from_inventory: false
```

## Example inventory

```ini
[wazuh_indexer]
indexer-1 ansible_host=10.10.10.10

[wazuh_manager]
manager-1 ansible_host=10.10.10.20

[wazuh_dashboard]
dashboard-1 ansible_host=10.10.10.30

[wazuh:children]
wazuh_indexer
wazuh_manager
wazuh_dashboard
```

## Single-host example (all services)

Use the same host in all three groups and enable all toggles for that host.

```ini
[wazuh_indexer]
wazuh-1 ansible_host=10.10.10.10

[wazuh_manager]
wazuh-1 ansible_host=10.10.10.10

[wazuh_dashboard]
wazuh-1 ansible_host=10.10.10.10

[wazuh:children]
wazuh_indexer
wazuh_manager
wazuh_dashboard
```

`group_vars/wazuh.yml` (or `host_vars/wazuh-1.yml`)
```yaml
wazuh_install_indexer: true
wazuh_install_manager: true
wazuh_install_dashboard: true
wazuh_indexer_hosts:
  - https://wazuh-1.example.local:9200
wazuh_manager_api_hosts:
  - wazuh-1.example.local
```

### Example group vars

`group_vars/wazuh_indexer.yml`
```yaml
wazuh_install_indexer: true
wazuh_indexer_cluster_name: wazuh-cluster
wazuh_indexer_seed_hosts:
  - indexer-1
wazuh_indexer_initial_manager_nodes:
  - indexer-1
```

`group_vars/wazuh_manager.yml`
```yaml
wazuh_install_manager: true
wazuh_indexer_hosts:
  - https://indexer-1.example.local:9200
```

`group_vars/wazuh_dashboard.yml`
```yaml
wazuh_install_dashboard: true
wazuh_indexer_hosts:
  - https://indexer-1.example.local:9200
wazuh_manager_api_hosts:
  - manager-1.example.local
```

## Example playbook

```yaml
- name: Install Wazuh
  hosts: wazuh
  become: true
  roles:
    - Wazuh/Server
```

## Caveats and how to apply them

### Disable TLS for the indexer (lab only)

This is not appropriate for production or STIG-compliant environments. It disables the OpenSearch security plugin.

```yaml
wazuh_indexer_tls_enabled: false
```

### Manage firewalld automatically

Opens ports for enabled components (9200/9300, 55000, and the dashboard port).

```yaml
wazuh_manage_firewalld: true
```

### Inventory-driven defaults

By default, component toggles and connectivity are derived from inventory groups. To opt out:

```yaml
wazuh_auto_from_inventory: false
```

### Fapolicyd allowlist

On STIG-hardened hosts with fapolicyd, Wazuh Dashboard may fail to start because the bundled Node binary is blocked from execution. Enable the fapolicyd integration to install an auditable allowlist rule:

```yaml
wazuh_manage_fapolicyd: true
```

You can add additional rules via `wazuh_fapolicyd_rules`. If your policy still blocks execution, enable trust updates as well:

```yaml
wazuh_manage_fapolicyd_trust: true
```

### Filebeat module for Wazuh

Wazuh expects the Filebeat module to be installed under `/usr/share/filebeat/module/wazuh`. This role downloads and installs it by default. If you manage the module yourself, disable it here:

```yaml
wazuh_filebeat_install_module: false
```

To keep Filebeat running without the module, also disable the module config:

```yaml
wazuh_filebeat_enable_module: false
```

## Notes

- When `wazuh_install_manager` is true, the role configures Filebeat to ship to the indexer list in `wazuh_indexer_hosts`.
- When `wazuh_install_dashboard` is true, the role configures the dashboard to reach both the indexer and the Wazuh API.
- The dashboard package sometimes requires `libcap` on EL-based systems, so it is included by default.
- Disabling TLS is intended for lab/testing only. It is not appropriate for production or STIG-compliant environments.
- When `wazuh_indexer_tls_enabled` is false, the role also disables the OpenSearch security plugin.
- If `wazuh_manage_firewalld` is true, the role opens ports for enabled components (9200/9300, 55000, and the dashboard port).
- If `wazuh_manage_fapolicyd` is true, the role installs allowlist rules and restarts fapolicyd.
