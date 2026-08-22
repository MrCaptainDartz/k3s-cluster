# Ansible — `infra-services` VM Configuration

Automates OS provisioning, security hardening, and Rootless Podman deployment of core services:
- **Traefik v3**: HTTPS reverse proxy with 30-year ECDSA P-384 self-signed certificate and HTTP (80) -> HTTPS (443) redirection.
- **Forgejo**: Local Git server with auto-created admin and SSH on port 2222.
- **Infisical**: Hardened secret manager (SSRF protection, JWT tuning, read-only rootfs, authenticated Redis).

---

## ⚙️ Configuration

Copy the template files:
```bash
cp inventory/hosts.yml.example inventory/hosts.yml
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
```

Key variables to review in `inventory/group_vars/all.yml`:
- `ansible_host`: Static IP of the VM (`10.20.4.253`).
- `traefik_forgejo_domain`: Domain for Forgejo (default: `git.infra-services.local`).
- `traefik_infisical_domain`: Domain for Infisical (default: `infisical.infra-services.local`).
- `forgejo_admin_username`, `forgejo_admin_email`: Initial Forgejo admin account.
- Passwords left blank (`""`) are auto-generated and safely preserved across re-runs.

---

## 🚀 Quickstart

```bash
ansible-playbook -i inventory/hosts.yml playbook.yml
```

---

## 🌐 Access Endpoints

- **Forgejo HTTPS**: `https://git.infra-services.local`
- **Forgejo Git SSH**: `ssh://git@git.infra-services.local:2222`
- **Infisical HTTPS**: `https://infisical.infra-services.local`
- **Admin Credentials**: Saved to `output/forgejo-credentials.txt`
