// app.js: Frontend controller for K8s Ops Hub Dashboard

const API_BASE = '/api';

// Tab Navigation Logic
const navItems = document.querySelectorAll('.nav-item');
const tabContents = document.querySelectorAll('.tab-content');
const pageTitle = document.getElementById('page-title');

navItems.forEach(item => {
    item.addEventListener('click', () => {
        const targetTab = item.getAttribute('data-tab');
        
        // Remove active class from all items and tabs
        navItems.forEach(nav => nav.classList.remove('active'));
        tabContents.forEach(tab => tab.classList.remove('active'));
        
        // Add active class to clicked item and target tab
        item.classList.add('active');
        document.getElementById(targetTab).classList.add('active');
        
        // Update top bar title
        if (targetTab === 'status-tab') pageTitle.textContent = 'Operations Control Panel';
        if (targetTab === 'db-tab') pageTitle.textContent = 'Database & Persistence';
        if (targetTab === 'config-tab') pageTitle.textContent = 'ConfigMaps & Secrets';
        if (targetTab === 'diagnostics-tab') pageTitle.textContent = 'Diagnostics & Canary Playgrounds';
    });
});

// Helper for Hosts file copying
function copyHostsText() {
    const codeElement = document.getElementById('hosts-code');
    navigator.clipboard.writeText(codeElement.textContent).then(() => {
        const copyBtn = document.querySelector('.copy-btn');
        copyBtn.textContent = 'Copied!';
        setTimeout(() => { copyBtn.textContent = 'Copy'; }, 2000);
    }).catch(err => {
        console.error('Failed to copy text: ', err);
    });
}

// Fetch System Status Metrics
async function fetchStatus() {
    try {
        const response = await fetch(`${API_BASE}/status`);
        if (!response.ok) throw new Error('API response error');
        
        const data = await response.json();
        
        // Update connection indicators
        document.getElementById('global-status-dot').className = 'pulse-indicator status-green';
        document.getElementById('global-status-text').textContent = 'System Connected';
        document.getElementById('health-api').textContent = 'Healthy (UP)';
        document.getElementById('health-api').className = 'health-state state-up';

        // Update Cluster Status Card
        document.getElementById('stat-pod').textContent = data.hostname || '-';
        document.getElementById('stat-version').textContent = data.version || '-';
        document.getElementById('stat-api-status').textContent = 'UP';
        document.getElementById('stat-api-status').className = 'status-badge badge-green';

        // Update Database details
        document.getElementById('db-val-host').textContent = data.database.host || '-';
        document.getElementById('db-val-name').textContent = data.database.name || '-';
        document.getElementById('db-val-user').textContent = data.database.user || '-';
        
        if (data.database.status === 'connected') {
            document.getElementById('health-db').textContent = 'Healthy (Connected)';
            document.getElementById('health-db').className = 'health-state state-up';
        } else {
            document.getElementById('health-db').textContent = 'Error (Disconnected)';
            document.getElementById('health-db').className = 'health-state state-down';
        }

        // Update Configs & Secrets
        document.getElementById('val-config-map').textContent = data.environment.CONFIG_MAP_VAL || 'Not Set';
        
        if (data.environment.SECRET_DB_PASSWORD_SET) {
            document.getElementById('val-secret-status').textContent = 'Active (Loaded)';
            document.getElementById('val-secret-status').className = 'text-success';
        } else {
            document.getElementById('val-secret-status').textContent = 'Not Configured';
            document.getElementById('val-secret-status').className = 'text-warning';
        }

    } catch (err) {
        console.error('Failed to fetch status:', err);
        // Update global indicator to disconnected
        document.getElementById('global-status-dot').className = 'pulse-indicator status-red';
        document.getElementById('global-status-text').textContent = 'Disconnected';
        document.getElementById('health-api').textContent = 'Unreachable';
        document.getElementById('health-api').className = 'health-state state-down';
        document.getElementById('health-db').textContent = 'Offline';
        document.getElementById('health-db').className = 'health-state state-down';
        
        document.getElementById('stat-api-status').textContent = 'DOWN';
        document.getElementById('stat-api-status').className = 'status-badge badge-red';
    }
}

// Fetch Visit count
async function fetchVisits() {
    try {
        const response = await fetch(`${API_BASE}/visit`);
        if (!response.ok) throw new Error('Failed to record/fetch visits');
        const data = await response.json();
        document.getElementById('visit-counter').textContent = data.count.toString();
    } catch (err) {
        console.error('Failed to fetch visits:', err);
    }
}

// Button visit click
document.getElementById('btn-visit').addEventListener('click', async () => {
    const btn = document.getElementById('btn-visit');
    btn.disabled = true;
    btn.textContent = 'Registering...';
    await fetchVisits();
    btn.disabled = false;
    btn.textContent = 'Register New Visit';
});

// Button reset click
document.getElementById('btn-reset-visits').addEventListener('click', async () => {
    if (!confirm('Are you sure you want to clear the visit history in the database?')) return;
    
    try {
        const response = await fetch(`${API_BASE}/reset-visits`, { method: 'POST' });
        if (!response.ok) throw new Error('Reset failed');
        document.getElementById('visit-counter').textContent = '0';
    } catch (err) {
        console.error('Failed to reset visits:', err);
    }
});

// Canary Test Runner (Fires 100 requests in parallel to determine traffic split)
document.getElementById('btn-run-canary').addEventListener('click', async () => {
    const btn = document.getElementById('btn-run-canary');
    const statusMsg = document.getElementById('canary-status');
    const barStable = document.getElementById('bar-stable');
    const barCanary = document.getElementById('bar-canary');
    const lblStable = document.getElementById('lbl-stable');
    const lblCanary = document.getElementById('lbl-canary');

    btn.disabled = true;
    statusMsg.textContent = 'Firing 100 requests to ingress routing...';

    let stableCount = 0;
    let canaryCount = 0;
    let failedRequests = 0;

    // We make 100 HTTP calls in parallel to see the routing distribution
    const requests = Array.from({ length: 100 }).map(async () => {
        try {
            // We call the visit endpoint (or any endpoint) to hit the router
            const response = await fetch(`${API_BASE}/visit?nocache=${Math.random()}`);
            if (!response.ok) throw new Error();
            const data = await response.json();
            
            if (data.version === 'v2-canary') {
                canaryCount++;
            } else {
                stableCount++;
            }
        } catch (err) {
            failedRequests++;
        }
    });

    await Promise.all(requests);

    const totalSuccess = stableCount + canaryCount;
    if (totalSuccess === 0) {
        statusMsg.textContent = 'Error: All test routing requests failed. Is ingress running?';
        btn.disabled = false;
        return;
    }

    const stablePercent = Math.round((stableCount / totalSuccess) * 100);
    const canaryPercent = Math.round((canaryCount / totalSuccess) * 100);

    // Update visuals
    barStable.style.width = `${stablePercent}%`;
    barCanary.style.width = `${canaryPercent}%`;
    lblStable.textContent = `${stablePercent}% (${stableCount})`;
    lblCanary.textContent = `${canaryPercent}% (${canaryCount})`;

    statusMsg.textContent = `Completed 100 requests. Success: ${totalSuccess}, Failures: ${failedRequests}.`;
    btn.disabled = false;
    
    // Refresh the general visits displays as well
    fetchVisits();
});

// Setup continuous polling loops
fetchStatus();
fetchVisits();
setInterval(fetchStatus, 5000);
