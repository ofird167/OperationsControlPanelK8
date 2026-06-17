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

### 2. Bootstrap the Cluster (All-in-One)
Run the master `aio.sh` orchestrator. This script will build the Ansible controller, spin up a 3-node High Availability cluster, scan your code for vulnerabilities with Trivy, and install Argo Rollouts, Velero, Linkerd, and your application stack:
```bash
./aio.sh
```

---

At the end of the `./aio.sh` run, it will automatically output a PowerShell command for you. Simply copy and paste it into an Administrator PowerShell to map your DNS:
*   **Windows Hosts (Administrator PowerShell)**:
    ```powershell
    Add-Content -Path "C:\Windows\System32\drivers\etc\hosts" -Value "`n<INGRESS_IP> `t app.local"
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
