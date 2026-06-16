const express = require('express');
const { Pool } = require('pg');
const os = require('os');

const app = express();
const port = process.env.PORT || 5000;
const appVersion = process.env.APP_VERSION || 'v1-stable';

// Middleware for CORS (only allow local dashboard origin for security)
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*'); // In local simulation, allow dashboard to query
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
  res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  next();
});

// Configure PostgreSQL pool
const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  user: process.env.DB_USER || 'dbadmin',
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME || 'app_db',
  port: parseInt(process.env.DB_PORT || '5432', 10),
  connectionTimeoutMillis: 5000,
});

// Helper to initialize table
async function initDb() {
  let retries = 5;
  while (retries > 0) {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS visits (
          id SERIAL PRIMARY KEY,
          visited_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
      `);
      console.log('Database visits table initialized successfully.');
      break;
    } catch (err) {
      console.error(`Database initialization failed. Retries remaining: ${retries - 1}`, err.message);
      retries -= 1;
      // Wait 3 seconds before retrying
      await new Promise(res => setTimeout(res, 3000));
    }
  }
}

initDb();

// 1. Healthcheck Endpoint
app.get('/health', async (req, res) => {
  try {
    const result = await pool.query('SELECT 1');
    if (result.rows.length > 0) {
      res.json({ status: 'healthy', database: 'connected' });
    } else {
      res.status(500).json({ status: 'unhealthy', database: 'unexpected response' });
    }
  } catch (err) {
    // TODO(security): Log detailed error internally, send generic message to client
    console.error('Healthcheck DB Error:', err.message);
    res.status(500).json({ status: 'unhealthy', database: 'disconnected', error: 'Internal Database Connection Error' });
  }
});

// 2. Status Endpoint
app.get('/status', async (req, res) => {
  let dbStatus = 'disconnected';
  try {
    await pool.query('SELECT 1');
    dbStatus = 'connected';
  } catch (err) {
    console.error('Status DB check failed:', err.message);
  }

  // Mask the DB password status for security
  const isDbPasswordSet = !!process.env.DB_PASSWORD;

  res.json({
    hostname: os.hostname(),
    version: appVersion,
    environment: {
      CONFIG_MAP_VAL: process.env.CONFIG_MAP_VAL || 'Default Config Value',
      SECRET_DB_PASSWORD_SET: isDbPasswordSet
    },
    database: {
      host: process.env.DB_HOST || 'localhost',
      name: process.env.DB_NAME || 'app_db',
      user: process.env.DB_USER || 'dbadmin',
      status: dbStatus
    }
  });
});

// 3. Visit Tracker (Demonstrates Database Persistence & Write operations)
app.get('/visit', async (req, res) => {
  try {
    // Parameterized/prepared statement execution for SQL Injection protection
    await pool.query('INSERT INTO visits DEFAULT VALUES');
    const result = await pool.query('SELECT COUNT(*) FROM visits');
    const count = result.rows[0].count;
    res.json({ count: parseInt(count, 10), version: appVersion, hostname: os.hostname() });
  } catch (err) {
    console.error('Database query error on /visit:', err.message);
    res.status(500).json({ error: 'Failed to record visit in the database' });
  }
});

// 4. Reset visits (for test environments)
app.post('/reset-visits', async (req, res) => {
  try {
    await pool.query('TRUNCATE TABLE visits');
    res.json({ message: 'Visit logs reset successfully.' });
  } catch (err) {
    console.error('Database query error on /reset-visits:', err.message);
    res.status(500).json({ error: 'Failed to reset visits' });
  }
});

app.listen(port, '0.0.0.0', () => {
  console.log(`Backend API version ${appVersion} listening on port ${port}`);
});
