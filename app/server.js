const express = require("express");
const path = require("path");
const { Pool } = require("pg");

const app = express();
app.set("trust proxy", true);
app.use(express.json({ limit: "100kb", strict: true }));
app.use((req, res, next) => {
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "SAMEORIGIN");
  res.setHeader("Referrer-Policy", "no-referrer-when-downgrade");
  res.setHeader("Strict-Transport-Security", "max-age=31536000; includeSubDomains; preload");
  next();
});
app.use(express.static(path.join(__dirname, "public")));

const PORT = Number(process.env.PORT || 3000);
const DB_PASSWORD = process.env.DB_PASSWORD || process.env.DB_PASS || "";

const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 5432,
  ssl: { rejectUnauthorized: false },
  max: 10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

pool.on("error", (err) => {
  console.error("Unexpected PG pool error:", err);
});

async function migrate() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.notes (
      id          bigserial PRIMARY KEY,
      title       text NOT NULL DEFAULT '',
      created_at  timestamptz NOT NULL DEFAULT now()
    );
  `);
  await pool.query(`
    DO $$
    BEGIN
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='notes' AND column_name='text'
      ) THEN
        ALTER TABLE public.notes DROP COLUMN text;
      END IF;
    END $$;
  `);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS idx_notes_created_at ON public.notes (created_at DESC);`
  );
}

app.get("/health", (_req, res) => res.status(200).send("ok"));

app.get("/ready", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.status(200).send("ready");
  } catch (e) {
    res.status(503).send("not-ready");
  }
});

app.get("/db", async (_req, res) => {
  try {
    await pool.query("SELECT 1");
    res.send("db-ok");
  } catch (e) {
    res.status(500).send("db-down: " + e.message);
  }
});

app.get("/api/notes", async (_req, res) => {
  const r = await pool.query(
    "SELECT id, title, created_at FROM public.notes ORDER BY id DESC LIMIT 200"
  );
  res.json(r.rows);
});

app.post("/api/notes", async (req, res) => {
  const title = (req.body?.title || "").trim();
  if (!title || title.length > 280) {
    return res.status(400).json({ error: "title required (1..280 chars)" });
  }
  const r = await pool.query(
    "INSERT INTO public.notes(title) VALUES($1) RETURNING id, title, created_at",
    [title]
  );
  res.status(201).json(r.rows[0]);
});

app.delete("/api/notes/:id", async (req, res) => {
  await pool.query("DELETE FROM public.notes WHERE id=$1", [req.params.id]);
  res.status(204).end();
});

app.get("/", (_req, res) =>
  res.sendFile(path.join(__dirname, "public/index.html"))
);

async function startWithRetries(maxSeconds = 90) {
  const deadline = Date.now() + maxSeconds * 1000;
  while (true) {
    try {
      await pool.query("SELECT 1");
      break;
    } catch (e) {
      if (Date.now() > deadline) {
        throw new Error("DB not reachable within startup window: " + e.message);
      }
      await new Promise((r) => setTimeout(r, 3000));
    }
  }
  await migrate();
  return new Promise((resolve) => {
    const server = app.listen(PORT, () => {
      console.log(`App listening on ${PORT}`);
      resolve(server);
    });
  });
}

let serverRef;
startWithRetries().then((s) => (serverRef = s)).catch((e) => {
  console.error("Startup failed:", e);
  process.exit(1);
});

async function gracefulShutdown(signal) {
  console.log(`Received ${signal}, shutting down gracefully...`);
  try {
    if (serverRef) {
      await new Promise((r) => serverRef.close(r));
    }
    await pool.end();
    console.log("Shutdown complete.");
    process.exit(0);
  } catch (e) {
    console.error("Shutdown error:", e);
    process.exit(1);
  }
}

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));