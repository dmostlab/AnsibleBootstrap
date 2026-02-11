#!/bin/bash

# --- CONFIGURATION ---
TARGET_IP="INSERT IP"
TARGET_USER="Ansible User Account"
PROJECT_DIR="$HOME/ansible-lab"

echo "🛠️  STEP 1: Installing Enterprise Toolkit (Ansible & Dependencies)..."
sudo dnf install -y epel-release
sudo dnf install -y ansible-core python3-pip git sshpass

echo "📦 STEP 2: Installing Hardening Roles from Ansible Galaxy..."
ansible-galaxy-collection-install fedora.linux_system_roles
ansible-galaxy install RedHatOfficial.rhel9_stig

echo "📁 STEP 3: Initializing Project Structure..."
mkdir -p $PROJECT_DIR/{group_vars,inventory,roles}
cd $PROJECT_DIR

echo "🔑 STEP 4: Generating FIPS-Compliant ECDSA Key..."
# Ed25519 is blocked by FIPS:STIG; ECDSA P-256 is the FIPS-approved standard.
if [ ! -f ~/.ssh/id_ecdsa_fips ]; then
    ssh-keygen -t ecdsa -b 256 -f ~/.ssh/id_ecdsa_fips -N ""
fi

echo "📤 STEP 5: Pushing Key to Target (Password required for last time)..."
ssh-copy-id -i ~/.ssh/id_ecdsa_fips.pub $TARGET_USER@$TARGET_IP

echo "📝 STEP 6: Creating Configuration Files (The 'Golden State')..."

# Create group_vars/all.yml
cat <<EOF > $PROJECT_DIR/group_vars/all.yml
---
# --- TASK KILLERS (Prevents AWK/Shadow hangs) ---
DISA_STIG_RHEL_09_411015: false
DISA_STIG_RHEL_09_411010: false
DISA_STIG_RHEL_09_232230: false
aide_periodic_cron_checking: true 

# --- SSH SECURITY OVERRIDES ---
# We confirmed 'Permission Denied' was a FIPS/Algorithm mismatch.
# These ensure 'Key-Only' access without PAM interference.
passwordauthentication: "no"
usepam: "no"
kbdinteractiveauthentication: "no"
authenticationmethods: "publickey"
rhel9stig_ssh_allowed_users: ["$TARGET_USER"]

# --- GLOBAL LOGIC ---
rhel9stig_run_fixing: true
rhel9stig_fips_mode: true
rhel9stig_gui_present: false
login_banner_text: "TEST Lab - Authorized Access Only"
EOF

# Create inventory
cat <<EOF > $PROJECT_DIR/inventory/lab_hosts.ini
[management]
rocky-target-01 ansible_host=$TARGET_IP
EOF

# Create site.yml
cat <<EOF > $PROJECT_DIR/site.yml
---
- name: Tier 1 - Hardened OS Baseline
  hosts: management
  become: true
  roles:
    - role: RedHatOfficial.rhel9_stig
EOF

echo "🚀 STEP 7: Executing Initial Hardening Run..."
# We pass aide_periodic_cron_checking via -e to ensure the role doesn't crash
ansible-playbook -i inventory/lab_hosts.ini site.yml -K \
  -e "aide_periodic_cron_checking=true"

echo "✅ BOOTSTRAP COMPLETE."