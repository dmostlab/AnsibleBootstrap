# Group Vars Guide

Source of truth for role behavior lives in `roles/*/README.md`. This file documents shared configuration patterns.

## Common Overrides

### Shared Certificates Bundle

```yaml
wazuh_certificates_tar_src: "/tmp/wazuh-certs/wazuh-certificates.tar"
```

### Distributed Indexer Hosts

```yaml
wazuh_single_node: false

wazuh_manager_indexer_hosts:
  - "https://10.0.0.11:9200"
  - "https://10.0.0.12:9200"

wazuh_dashboard_opensearch_hosts:
  - "https://10.0.0.11:9200"
  - "https://10.0.0.12:9200"

wazuh_dashboard_wazuh_api_url: "https://10.0.0.21"
```

### Manager Agent Protocol and Firewall Sources

```yaml
wazuh_manager_agent_protocol: "tcp"

wazuh_manager_firewalld_agent_sources:
  - "10.0.40.0/24"
```
