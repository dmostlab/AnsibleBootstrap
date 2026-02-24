# Wazuh Indexer Role

Installs and configures the Wazuh Indexer using the official repositories and endpoints. Includes certificate generation, optional distribution, indexer configuration, and service management.

## What This Role Does

- Adds Wazuh repositories and GPG keys (APT/RPM).
- Installs `wazuh-indexer`.
- Configures `/etc/wazuh-indexer/opensearch.yml`.
- Generates SSL certificates and a `wazuh-certificates.tar` bundle (optional).
- Installs indexer certs under `/etc/wazuh-indexer/certs`.
- Starts and enables the indexer service.
- Optionally runs the security initialization script (currently disabled in tasks).

## Defaults (AIO-Friendly)

The role defaults are set for a single-node AIO install:
- `wazuh_single_node: true`
- `wazuh_indexer_generate_certs: true`
- `wazuh_indexer_manage_certificates: true`
- `wazuh_fips_enabled: true`

## Key Variables

### Core

- `wazuh_single_node` (bool, default `true`)
- `wazuh_indexer_node_name` (string, default `node-1`)
- `wazuh_indexer_network_host` (string, default `0.0.0.0`)

### Certificates

- `wazuh_certificates_tar_src` (string, default `""`)
- `wazuh_indexer_manage_certificates` (bool, default `true`)
- `wazuh_indexer_generate_certs` (bool, default `true`)
- `wazuh_indexer_distribute_certs` (bool, default `false`)
- `wazuh_indexer_cert_regen` (bool, default `false`)
- `wazuh_indexer_cert_cleanup` (bool, default `false`)
- `wazuh_indexer_certificates_workdir` (string, default `/root`)
- `wazuh_indexer_certificates_tar_path` (string, default `/root/wazuh-certificates.tar`)

### Security Init

- `wazuh_indexer_run_security_init` (bool, default `true`)
- `wazuh_indexer_security_init_manual` (bool, default `false`)

Note: The security initialization tasks are currently disabled in `roles/wazuh_indexer/tasks/main.yml`. Run the script manually if needed:
```
sudo /bin/bash /usr/share/wazuh-indexer/bin/indexer-security-init.sh
```

### FIPS / SELinux / fapolicyd

- `wazuh_fips_enabled` (bool, default `true`)
- `wazuh_indexer_fips_enable` (bool, default `{{ wazuh_fips_enabled }}`)
- `wazuh_indexer_selinux_manage` (bool, default `true`)
- `wazuh_indexer_fapolicyd_manage` (bool, default `true`)
- `wazuh_indexer_fapolicyd_allow_paths` (list)

### Firewalld

- `wazuh_indexer_firewalld_manage` (bool, default `true`)
- `wazuh_indexer_firewalld_ports` (list, default `["9200/tcp", "9300/tcp"]`)

## Examples

### AIO (Defaults)

```yaml
- hosts: wazuh_aio
  become: true
  roles:
    - role: wazuh_indexer
```

### Distributed (Use Shared Cert Bundle)

```yaml
- hosts: wazuh_indexers
  become: true
  roles:
    - role: wazuh_indexer
      vars:
        wazuh_single_node: false
        wazuh_certificates_tar_src: "/tmp/wazuh-certs/wazuh-certificates.tar"
```
