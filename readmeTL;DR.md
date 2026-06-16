# DevOps Quickstart Guide (TL;DR)

> 📚 **Looking for full architectural details and guides?** View the [Detailed README](README.md).

---

### 1. Initialize Secrets & Configuration
Create the `/secrets` directory and populate local variables:
```bash
mkdir -p secrets
cp example.env secrets/.env
```
*(Optionally populate `VAULT_ADDR` and `VAULT_TOKEN` inside `secrets/.env` if you wish to pull secrets from HashiCorp Vault).*

---

### 2. Bootstrap the Cluster
Run the master bootstrap command. This automatically builds the Ansible controller, boots the simulated VM containers, sets up k3s, compile images, and installs all Kubernetes addons via Helm:
```bash
./scripts/bootstrap.sh
```

---

### 3. Setup Local DNS Mapping
Retrieve the allocated IP of the Ingress Controller LoadBalancer:
```bash
export KUBECONFIG=secrets/k3s.kubeconfig
kubectl get svc -n ingress-nginx ingress-nginx-controller
```
Add this IP to your host machine's hosts file to map `app.local`:
*   **Linux/macOS Hosts**:
    ```bash
    echo "<INGRESS_IP> app.local" | sudo tee -a /etc/hosts
    ```
*   **Windows Hosts (Administrator PowerShell)**:
    ```powershell
    Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n<INGRESS_IP> app.local" -Force
    ```

---

### 4. Verify Dashboard & Canary Routing
*   **Browser Dashboard**: Access `https://app.local` (bypass self-signed TLS certificate alert).
*   **Automated Canary Test**: Execute the traffic split analysis:
    ```bash
    ./scripts/test-canary.sh
    ```
*   **Database Persistence Test**: Trigger database visits on the dashboard, delete the Postgres pod (`kubectl delete pod -l app=postgres`), and confirm that the visit count remains intact when the pod restarts.

---

### 5. Clean Teardown
To cleanly destroy the cluster, delete LoadBalancers, delete VM containers, and remove the custom Docker bridge network:
```bash
./scripts/destroy.sh
```
