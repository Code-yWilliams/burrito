import cors from "cors";
import express from "express";
import { Pool } from "pg";

// Connection settings come from the standard PG* env vars
// (PGHOST, PGUSER, PGPASSWORD, PGDATABASE), set by the Helm chart.
const pool = new Pool({ connectionTimeoutMillis: 3000 });
const port = Number(process.env.PORT) || 3000;

// Browsers only let the SPA (a different origin) read responses when the
// API names that origin explicitly — never "*" here.
const allowedOrigins = (process.env.ALLOWED_ORIGINS ?? "http://localhost:5173")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);

const app = express();
app.use(cors({ origin: allowedOrigins }));

app.get("/healthz", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok", db: "ok" });
  } catch {
    res.status(503).json({ status: "degraded", db: "unreachable" });
  }
});

app.use((_req, res) => {
  res.status(404).json({ error: "not found" });
});

const server = app.listen(port, () => {
  console.log(`burrito listening on :${port}`);
});

process.on("SIGTERM", () => {
  server.close(() => {
    pool.end().then(() => process.exit(0));
  });
});
