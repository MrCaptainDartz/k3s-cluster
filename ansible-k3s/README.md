# HA K3s Cluster with Ansible

This project automates the deployment of a highly available (HA) K3s cluster using Ansible.

It includes the following elements out of the box:

- **3 Control Plane nodes** with embedded etcd for resilient data.
- **[kube-vip](https://kube-vip.io/)** to provide a virtual IP (VIP) to access the Kubernetes API server, running here in ARP mode.
- **[MetalLB](https://metallb.universe.tf/)** to provide IPs accessible on the local network for `LoadBalancer` type services.
- **Ceph CSI** to automatically connect the cluster to your existing Proxmox/Ceph distributed storage, providing persistent volumes via RBD and CephFS.

The deployment uses the highly popular Ansible role [ansible-role-k3s](https://github.com/PyratLabs/ansible-role-k3s).

## Prerequisites

- **Ansible >= 2.10** installed on the machine running the commands.
- **Python 3** with the `netaddr` package installed locally (`pip3 install netaddr`).
- Configured SSH key access to all your target servers/VMs (the playbook uses the `ubuntu` user by default, who has passwordless `sudo` rights).

## Quick Start

### 1. Install the dependency role

Before starting, download the Ansible dependency:

```bash
cd ansible-k3s
ansible-galaxy install -r requirements.yml
```

### 2. Customize the configuration

Copy the provided example configuration files to adapt them to your infrastructure:

```bash
cp inventory/hosts.yml.example inventory/hosts.yml
cp inventory/group_vars/all.yml.example inventory/group_vars/all.yml
```

- **`inventory/hosts.yml`**: Add the actual IPs of your machines and their login credentials here.
- **`inventory/group_vars/all.yml`**: Adjust configuration variables such as the VIP address, MetalLB IP range, and your Ceph credentials.

> **Important**: Never commit `hosts.yml` and `all.yml` if they contain or will contain passwords (like `ceph_client_key`). The directory already uses `.gitignore` to prevent accidental leaks, but be careful.

#### Main variables (`all.yml`)

Here are some important variables based on the provided examples:

| Variable              | Example                                | Explanation                                                            |
| --------------------- | -------------------------------------- | ---------------------------------------------------------------------- |
| `k3s_release_version` | `stable`                               | K3s version to deploy (can be a specific release like `v1.31.2+k3s1`). |
| `k3s_vip`             | `192.168.1.10`                         | The target IP for kube-vip. This IP must be available on the network.  |
| `k3s_vip_interface`   | `{{ ansible_default_ipv4.interface }}` | On which network interface to share the VIP.                           |
| `metallb_ip_range`    | `192.168.1.150-192.168.1.199`          | The IP range dynamically assigned by MetalLB to your applications.     |
| `ceph_fsid`           | `YOUR-CEPH-FSID-HERE`                  | The unique identification UUID of your Proxmox/Ceph cluster.           |
| `ceph_client_key`     | `YOUR-CEPH-KEYRING...`                 | The secret key that allows K3s to authenticate storage requests.       |
| `ceph_monitors`       | `['192.168.1.200', ...]`               | The IPs of the available Ceph monitors on the network.                 |

### 3. Run the deployment

Simply run the playbook:

```bash
ansible-playbook -i inventory/hosts.yml site.yml
```

## Architecture

The generated architecture, based on the default dummy variables of the project (`all.yml.example` and `hosts.yml.example`), looks like this:

```mermaid
flowchart TD
    Client(["User / Admin"])

    subgraph VIP ["Virtual IP API"]
        KubeVIP("kube-vip: 192.168.1.10")
    end

    subgraph LoadBalancer ["MetalLB"]
        direction LR
        LBPool["Allocated IP range<br>192.168.1.150 - 192.168.1.199"]
    end

    Client -->|"kubectl / port 6443"| VIP
    Client -->|"Dynamic web traffic"| LoadBalancer

    VIP --> N1
    VIP --> N2
    VIP --> N3

    subgraph ClusterK3s ["K3s Cluster (Control Planes & etcd)"]
        direction LR
        N1["k3s-node-01<br>192.168.1.101"]
        N2["k3s-node-02<br>192.168.1.102"]
        N3["k3s-node-03<br>192.168.1.103"]
    end

    ClusterK3s -.- LoadBalancer

    subgraph CephStorage ["External Ceph Cluster"]
        direction LR
        Mon1["Monitor<br>192.168.1.200"]
        Mon2["Monitor<br>192.168.1.201"]
        Mon3["Monitor<br>192.168.1.202"]
        Data[("RBD & CephFS Shares")]
    end

    N1 -->|"Ceph CSI Driver"| CephStorage
    N2 -->|"Ceph CSI Driver"| CephStorage
    N3 -->|"Ceph CSI Driver"| CephStorage
```

## Project Structure

```
ansible-k3s/
├── ansible.cfg                          # Local Ansible settings
├── requirements.yml                     # Dependencies (the k3s role)
├── site.yml                             # The installation playbook
├── inventory/
│   ├── hosts.yml.example                # Blank inventory with your target nodes
│   └── group_vars/
│       └── all.yml.example              # Centralization of cluster variables
└── templates/
    ├── 01-kube-vip-rbac.yml.j2          # Manifest files injected by the role
    ├── 02-kube-vip-daemonset.yml.j2
    ├── 04-metallb-config.yml.j2
    ├── 05-ceph-secrets.yml.j2
    ├── 06-ceph-storageclasses.yml.j2
    └── 07-ceph-csi-helmcharts.yml.j2
```

## Verification

To check the health of the deployed component, you can run these queries:

```bash
# Retrieve the remote configuration file for kubectl
scp ubuntu@<A-NODE-IP>:/etc/rancher/k3s/k3s.yaml ~/.kube/config

# Update the server URL inside the config to use the VIP instead of 127.0.0.1
sed -i 's/127.0.0.1/YOUR_VIP_ADDRESS/' ~/.kube/config

# Check the presence of the servers
kubectl get nodes -o wide

# Diagnose the kube-vip interface
kubectl get pods -n kube-system -l app.kubernetes.io/name=kube-vip-ds

# Verify MetalLB
kubectl get pods -n metallb-system

# Verify the Ceph storage configuration
kubectl get pods -n ceph-csi
kubectl get storageclass
```
