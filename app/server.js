// Minimal Express + PG app (single listen, health, safe migration)

const express = require("express");
const bodyParser = require("body-parser");
const { Pool } = require("pg");
const path = require("path");

const app = express();
app.use(bodyParser.json());
app.use(express.static(path.join(__dirname, "public")));

const PORT = Number(process.env.PORT || 3000);

// Accept both DB_PASSWORD and legacy DB_PASS
const DB_PASSWORD = process.env.DB_PASSWORD || process.env.DB_PASS || "";

// Postgres pool
const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: DB_PASSWORD,
  database: process.env.DB_NAME,
  port: 5432,
  ssl: { rejectUnauthorized: false },
});

// Idempotent schema migration
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

// Health for ALB
app.get("/health", (_req, res) => res.status(200).send("ok"));

// DB probe
app.get("/db", async (_req, res) => {
  try {
    await pool.query("select 1");
    res.send("db-ok");
  } catch (e) {
    res.status(500).send("db-down: " + e.message);
  }
});

// API
app.get("/api/notes", async (_req, res) => {
  const r = await pool.query(
    "SELECT id, title, created_at FROM public.notes ORDER BY id DESC LIMIT 200"
  );
  res.json(r.rows);
});

app.post("/api/notes", async (req, res) => {
  const title = (req.body.title || "").trim();
  if (!title) return res.status(400).json({ error: "title required" });
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

// Index
app.get("/", (_req, res) =>
  res.sendFile(path.join(__dirname, "public/index.html"))
);

// Start after migration
(async () => {
  try {
    await migrate();
    app.listen(PORT, () => console.log(`App listening on ${PORT}`));
  } catch (e) {
    console.error("Migration failed:", e);
    process.exit(1);
  }
})();