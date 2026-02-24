# Wazuh Manager Role

Installs and configures the Wazuh Manager (Server) and Filebeat. Includes certificate installation, Filebeat setup, and indexer integration.

## What This Role Does

- Adds Wazuh repositories and GPG keys (APT/RPM).
- Installs `wazuh-manager` and `filebeat`.
- Downloads Wazuh Filebeat configuration, template, and module.
- Configures Filebeat output hosts and keystore credentials.
- Installs certificates from `wazuh-certificates.tar` into `/etc/filebeat/certs`.
- Updates indexer settings in `/var/ossec/etc/ossec.conf`.
- Enables and starts `wazuh-manager` and `filebeat`.

## Defaults (AIO-Friendly)

- `wazuh_manager_manage_certificates: true`
- `wazuh_manager_indexer_hosts` uses the host IP by default
- `wazuh_fips_enabled: true`
- Agent protocol default is TCP

## Key Variables

### Certificates

- `wazuh_certificates_tar_src` (string, default `""`)
- `wazuh_manager_manage_certificates` (bool, default `true`)
- `wazuh_manager_certificates_workdir` (string, default `/root`)
- `wazuh_manager_certificates_tar_path` (string, default `/root/wazuh-certificates.tar`)

### Indexer Connectivity

- `wazuh_manager_indexer_hosts` (list)
- `wazuh_manager_indexer_username` (string, default `admin`)
- `wazuh_manager_indexer_password` (string, default `admin`)
- `wazuh_manager_indexer_keystore_force` (bool, default `false`)
- `wazuh_manager_filebeat_keystore_force` (bool, default `false`)

### Agent Protocol

- `wazuh_manager_agent_protocol` (string, default `tcp`)

### FIPS / SELinux / fapolicyd

- `wazuh_fips_enabled` (bool, default `true`)
- `wazuh_manager_selinux_manage` (bool, default `true`)
- `wazuh_manager_fapolicyd_manage` (bool, default `true`)
- `wazuh_manager_fapolicyd_allow_paths` (list)

### Firewalld

- `wazuh_manager_firewalld_manage` (bool, default `true`)
- `wazuh_manager_firewalld_ports` (list)
- `wazuh_manager_firewalld_agent_sources` (list, default `[]`)
  - When set, uses rich rules to restrict access to the given CIDRs.

## Examples

### AIO (Defaults)

```yaml
- hosts: wazuh_aio
  become: true
  roles:
    - role: wazuh_manager
```

### Distributed (Use Shared Cert Bundle)

```yaml
- hosts: wazuh_managers
  become: true
  roles:
    - role: wazuh_manager
      vars:
        wazuh_single_node: false
        wazuh_certificates_tar_src: "/tmp/wazuh-certs/wazuh-certificates.tar"
        wazuh_manager_indexer_hosts:
          - "https://10.0.0.10:9200"
```
