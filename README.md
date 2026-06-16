# On-Premises Kubernetes Cluster Simulation Platform

This project provides an automated, production-like, on-premises Kubernetes cluster environment running locally. It simulates physical VM nodes using Docker containers running systemd and leverages Ansible to bootstrap and configure a three-node Kubernetes cluster (1 control plane, 2 worker nodes).

The entire system requires **only Docker** to run on the host. All other operations tools (Ansible, Helm, and kubectl) are self-contained inside a containerized **Controller Environment**, keeping your host clean and independent.

---

## 1. Architectural Overview

The deployment architecture is orchestrated on a custom Docker bridge network (`k8s-net`):

```mermaid
flowchart TB
    subgraph Host ["Local Host Machine"]
        direction TB
        subgraph Net ["Docker Bridge Network (k8s-net: 172.20.0.0/16)"]
            
            subgraph Controller ["Controller Container (k8s-ops-controller)"]
                Ansible[Ansible Core]
                Kube[kubectl & Helm]
            end
            
            subgraph Node1 ["Control Plane (k8s-control-plane: 172.20.0.10)"]
                K3sS[k3s Server]
                APIS[kube-apiserver]
            end
            
            subgraph Node2 ["Worker 1 (k8s-worker-1: 172.20.0.11)"]
                K3sA1[k3s Agent]
                Containerd1[containerd]
            end
            
            subgraph Node3 ["Worker 2 (k8s-worker-2: 172.20.0.12)"]
                K3sA2[k3s Agent]
                Containerd2[containerd]
            end
            
            Node1 --> Node2
            Node1 --> Node3
        end
        
        Socket["/var/run/docker.sock"] <--> Controller
        KubeConfig["secrets/k3s.kubeconfig"] <--> Host
        LocalPersist["data/"] <--> Node1 & Node2 & Node3
    end
```

### Infrastructure Components
1.  **Ansible Controller Container (`infra/control/Dockerfile`)**: An isolated environment containing Ansible, Helm, and kubectl that mounts the host's Docker socket and workspace directory to provision and manage the nodes.
2.  **Simulated VM Nodes (`jrei/systemd-ubuntu:22.04`)**: Run Ubuntu 22.04 with systemd, simulating independent bare-metal machines.
3.  **K3s Distribution**: Bootstraps the control plane and links worker nodes. Default Traefik and local-storage options are disabled so they can be manually customized.
4.  **MetalLB (Layer 2 Mode)**: Handles IP allocation for `LoadBalancer` type services within the `172.20.0.200-172.20.0.250` range.
5.  **NGINX Ingress Controller**: Serves as the reverse proxy, terminating self-signed TLS certificates for `app.local` and routing requests.
6.  **ArgoCD (GitOps)**: Manages cluster manifests and enforces drift detection and self-healing.
7.  **Prometheus & Grafana (kube-prometheus-stack)**: Gathers metrics and provides dashboard visualization.

---

## 2. Local Setup & Bootstrapping

### Prerequisites
*   Docker (v20.10+) running on Linux (or WSL2 on Windows).
*   Internet connectivity (first-time image builds and Helm repository synchronization).

### Quickstart Bootstrap
1.  **Configure Environment**:
    Create the `/secrets` directory and populate your local variables:
    ```bash
    mkdir -p secrets
    cp example.env secrets/.env
    ```
    *If you have a running HashiCorp Vault instance, populate the `VAULT_ADDR` and `VAULT_TOKEN` variables inside `secrets/.env`. Otherwise, the script will automatically generate secure default credentials.*

2.  **Run Bootstrap**:
    Run the master bootstrap orchestrator:
    ```bash
    ./scripts/bootstrap.sh
    ```
    This script builds the Ansible controller, spins up the containers, installs k3s, compiles the application images, imports them to the node registries, and deploys all configurations.

3.  **Map Domain**:
    Retrieve the Ingress LoadBalancer IP using:
    ```bash
    export KUBECONFIG=secrets/k3s.kubeconfig
    kubectl get svc -n ingress-nginx ingress-nginx-controller
    ```
    Map this IP to the local domain `app.local` in your hosts file:
    *   **Linux/WSL hosts**:
        ```bash
        # Append to /etc/hosts
        echo "<INGRESS_IP> app.local" | sudo tee -a /etc/hosts
        ```
    *   **Windows Hosts (Administrator PowerShell)**:
        ```powershell
        Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n<INGRESS_IP> app.local" -Force
        ```

4.  **Access Dashboard**:
    Navigate to `https://app.local` in your web browser. (Bypass the self-signed TLS browser warning to load the Ops Hub Dashboard).

---

## 3. Operations Verification

### Persistent Storage (PVC) Test
1.  Go to the **Database & PVC** tab on the dashboard.
2.  Click **Register New Visit**. The counter increments, sending a transaction to PostgreSQL.
3.  Simulate a database node crash by deleting the Postgres pod:
    ```bash
    kubectl delete pod -l app=postgres
    ```
4.  Once the pod reschedules and starts up, refresh the dashboard. The visit count is preserved, proving dynamic persistence using host-mounted folders (`data/`).

### Ingress Canary Split Test
1.  Go to the **Diagnostics & Canary** tab on the dashboard.
2.  Click **Trigger 100 Requests**. The dashboard fires 100 parallel requests to `/api/visit`.
3.  The visual bar displays the split distribution. NGINX routes ~80% of traffic to the `v1-stable` deployment and ~20% of traffic to the `v2-canary` deployment based on the weights configured.
4.  Alternatively, verify from the command line:
    ```bash
    ./scripts/test-canary.sh
    ```

---

## 4. Teardown & Clean Destruction
To cleanly delete the application resources, uninstall Helm charts, stop the simulated VM containers, and free all port bindings, execute:
```bash
./scripts/destroy.sh
```

---

## 5. Design Decisions & Trade-Offs
*   **Docker Container VMs vs. Vagrant/Multipass**: Running VM hypervisors inside sandboxed environments often fails due to nested virtualization constraints. Simulating VMs via systemd containers guarantees reliability and portability on any host running Docker.
*   **Ansible inside Controller Container**: Isolating Ansible inside a controller image prevents host machine pollution and dependencies mismatch.
*   **Local-Path Provisioner with Host Bindings**: Selected over Longhorn to conserve CPU/memory resources on a single development machine while maintaining strict filesystem persistence.
*   **Secrets Fallback**: The `get-secrets.sh` script queries HashiCorp Vault. If Vault is unavailable, it falls back to local secure string generation to prevent bootstrap blockages.

---

## 6. License
Distributed under the MIT License. See [LICENSE](LICENSE) for details.
