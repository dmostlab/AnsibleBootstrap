# Wazuh Dashboard Role

Installs and configures the Wazuh Dashboard. Includes repository setup, package install, dashboard configuration, certificate installation, and Wazuh API integration.

## What This Role Does

- Adds Wazuh repositories and GPG keys (APT/RPM).
- Installs `wazuh-dashboard`.
- Configures `/etc/wazuh-dashboard/opensearch_dashboards.yml` (server host/port and OpenSearch hosts).
- Renders `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml`.
- Installs certificates from `wazuh-certificates.tar` into `/etc/wazuh-dashboard/certs`.
- Starts and enables the dashboard service.

## Defaults (AIO-Friendly)

- `wazuh_dashboard_manage_certificates: true`
- `wazuh_dashboard_server_port: 443`
- `wazuh_fips_enabled: true`

## Key Variables

### Certificates

- `wazuh_certificates_tar_src` (string, default `""`)
- `wazuh_dashboard_manage_certificates` (bool, default `true`)
- `wazuh_dashboard_certificates_workdir` (string, default `/root`)
- `wazuh_dashboard_certificates_tar_path` (string, default `/root/wazuh-certificates.tar`)

### Dashboard Configuration

- `wazuh_dashboard_server_host` (string, default `0.0.0.0`)
- `wazuh_dashboard_server_port` (int, default `443`)
- `wazuh_dashboard_opensearch_hosts` (list)
- `wazuh_dashboard_opensearch_username` (string, default `kibanaserver`)
- `wazuh_dashboard_opensearch_password` (string, default `kibanaserver`)
- `wazuh_dashboard_keystore_force` (bool, default `false`)

### Wazuh API (Dashboard Integration)

- `wazuh_dashboard_wazuh_api_url` (string)
- `wazuh_dashboard_wazuh_api_port` (int, default `55000`)
- `wazuh_dashboard_wazuh_api_username` (string, default `wazuh-wui`)
- `wazuh_dashboard_wazuh_api_password` (string, default `wazuh-wui`)

### FIPS / SELinux / fapolicyd

- `wazuh_fips_enabled` (bool, default `true`)
- `wazuh_dashboard_selinux_manage` (bool, default `true`)
- `wazuh_dashboard_fapolicyd_manage` (bool, default `true`)
- `wazuh_dashboard_fapolicyd_allow_paths` (list)

### Firewalld

- `wazuh_dashboard_firewalld_manage` (bool, default `true`)
- `wazuh_dashboard_firewalld_ports` (list, default `["443/tcp"]`)

## Examples

### AIO (Defaults)

```yaml
- hosts: wazuh_aio
  become: true
  roles:
    - role: wazuh_dashboard
```

### Distributed (Use Shared Cert Bundle)

```yaml
- hosts: wazuh_dashboards
  become: true
  roles:
    - role: wazuh_dashboard
      vars:
        wazuh_certificates_tar_src: "/tmp/wazuh-certs/wazuh-certificates.tar"
        wazuh_dashboard_opensearch_hosts:
          - "https://10.0.0.10:9200"
        wazuh_dashboard_wazuh_api_url: "https://10.0.0.20"
```
