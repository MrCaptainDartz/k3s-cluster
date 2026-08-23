# Ansible — `infra-services` VM Configuration

Automates OS provisioning, security hardening, and Rootless Podman deployment of core services:
- **Traefik v3**: Rootless HTTPS reverse proxy with 90-day ECDSA P-384 certificates, automated PKI rotation, and HTTP (80) -> HTTPS (443) redirection.
- **Forgejo**: Local Git server with auto-created admin and SSH on port 2222.
- **OpenBao 2.6**: Open-source secret manager with Raft storage, declarative audit logging, internal PKI Root CA, AppRoles, and Web UI.

---

## ⚙️ Configuration

Copy the template files:
```bash
cp inventory/hosts.yml.example inventory/hosts.yml
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
```

Key variables to review in `inventory/group_vars/all.yml`:
- `ansible_host`: Static IP of the VM (default: `10.20.4.253`).
- `traefik_forgejo_domain`: Domain for Forgejo (default: `git.infra-services.local`).
- `traefik_openbao_domain`: Domain for OpenBao (default: `openbao.infra-services.local`).
- `openbao_pki_domain`: Base domain for internal PKI wildcard certificates (default: `infra-services.local`).
- `openbao_pki_cert_ttl`: Validity duration for issued TLS certificates (default: `2160h` / 90 days).
- `traefik_cert_renew_threshold_seconds`: Renewal threshold in seconds (default: `2592000` / 30 days).
- `forgejo_admin_username`, `forgejo_admin_email`: Initial Forgejo admin account.
- Passwords left blank (`""`) are auto-generated on first deploy and safely preserved across re-runs.

---

## 🚀 Quickstart

```bash
ansible-playbook -i inventory/hosts.yml playbook.yml
```

---

## 🔐 Automated Bootstrap & PKI Rotation

On first boot (when OpenBao is uninitialized), the playbook automatically:
1. **Initializes OpenBao** with configurable Shamir secret shares/thresholds.
2. **Deploys unseal keys** to `/home/services/openbao/.unseal_keys` (`0600`) and enables the automated systemd unseal service.
3. **Configures the Declarative JSON Audit Device** (`/bao/logs/audit.log`) with logrotate (`/etc/logrotate.d/openbao-audit`).
4. **Mounts the `kv-v2` secret engine** at `secret/`.
5. **Creates Security Policies**: `admin-policy`, `eso-k3s-policy`, `ansible-policy`, and `traefik-cert-renewer-policy`.
6. **Configures Authentication Methods**:
   - `userpass`: Creates nominative admin user with auto-generated strong password.
   - `approle`: Creates `ansible` AppRole (for playbook automation) and `traefik-cert-renewer` AppRole.
7. **Initializes Internal PKI Engine**:
   - Generates Internal Root CA (ECDSA P-384, 20-year TTL).
   - Configures PKI issuing role (`allowed_domains: [openbao_pki_domain]`).
   - Issues wildcard server certificate `*.infra-services.local` (90-day validity).
8. **Configures Autonomous TLS Rotation for Traefik**:
   - Deploys `/home/services/traefik/renew-cert.sh` (`0750`).
   - Deploys systemd user units `traefik-cert-renewer.service` and `traefik-cert-renewer.timer`.
   - The daily timer checks certificate expiration: if `< 30 days` remaining, it requests a new certificate from OpenBao using its AppRole and reloads Traefik with zero downtime.

---

## 🌐 Endpoints & Output Files

- **Forgejo HTTPS**: `https://git.infra-services.local`
- **Forgejo Git SSH**: `ssh://git@git.infra-services.local:2222`
- **OpenBao HTTPS**: `https://openbao.infra-services.local`
- **Root CA Certificate**: Saved to `output/openbao-ca.crt` (import this certificate into your browser or OS trust store to trust all `*.infra-services.local` HTTPS endpoints without warnings).
- **Admin Credentials**: Saved automatically to `output/`:
  - `output/forgejo-credentials.txt`: Forgejo admin username & password.
  - `output/openbao-credentials.txt`: Initial Root Token, Unseal Keys, nominative admin account, Ansible AppRole (Role ID & Secret ID), Traefik AppRole, and PKI summary.


