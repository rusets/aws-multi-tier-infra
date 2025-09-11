// Import core modules
const express = require("express");
const bodyParser = require("body-parser");
const { Pool } = require("pg");
const path = require("path");

// Initialize Express application
const app = express();

// Middleware: parse JSON request bodies
app.use(bodyParser.json());

// Middleware: serve static files from /public folder
app.use(express.static(path.join(__dirname, "public")));

// Define the application port (default: 3000)
const PORT = Number(process.env.PORT || 3000);

// Create a PostgreSQL connection pool using environment variables
const pool = new Pool({
  host: process.env.DB_HOST,          // Database host
  user: process.env.DB_USER,          // Database user
  password: process.env.DB_PASSWORD,  // Important: password comes from env
  database: process.env.DB_NAME,      // Database name
  port: 5432,                         // Default PostgreSQL port
  ssl: { rejectUnauthorized: false }  // Required for RDS (SSL enabled)
});

// Database migration: create or fix schema automatically
async function migrate() {
  // Ensure the "notes" table exists with correct columns
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.notes (
      id          bigserial PRIMARY KEY,
      title       text NOT NULL DEFAULT '',
      created_at  timestamptz NOT NULL DEFAULT now()
    );
  `);

  // If old "text" column exists → drop it (legacy cleanup)
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

  // Create index for faster queries on created_at
  await pool.query(`CREATE INDEX IF NOT EXISTS idx_notes_created_at ON public.notes (created_at DESC);`);
}

// Health check endpoint
app.get("/health", (_req, res) => res.send("ok"));

// Database connectivity check
app.get("/db", async (_req, res) => {
  try {
    await pool.query("select 1");
    res.send("db-ok");
  } catch (e) {
    res.status(500).send("db-down: " + e.message);
  }
});

// Get latest 200 notes (ordered by ID descending)
app.get("/api/notes", async (_req, res) => {
  const r = await pool.query("SELECT id, title, created_at FROM public.notes ORDER BY id DESC LIMIT 200");
  res.json(r.rows);
});

// Create a new note
app.post("/api/notes", async (req, res) => {
  const title = (req.body.title || "").trim();
  if (!title) return res.status(400).json({ error: "title required" });

  const r = await pool.query(
    "INSERT INTO public.notes(title) VALUES($1) RETURNING id, title, created_at",
    [title]
  );
  res.status(201).json(r.rows[0]);
});

// Delete a note by ID
app.delete("/api/notes/:id", async (req, res) => {
  await pool.query("DELETE FROM public.notes WHERE id=$1", [req.params.id]);
  res.status(204).end();
});

// Serve frontend index page
app.get("/", (_req, res) => res.sendFile(path.join(__dirname, "public/index.html")));

// --- Health check endpoint for ALB ---
app.get('/health', (_req, res) => {
  res.status(200).send('ok');
});

// --- Start server ---
app.listen(process.env.PORT || 3000, () => {
  console.log(`Server running on port ${process.env.PORT || 3000}`);
});

// Start server + run migrations before accepting requests
app.listen(PORT, async () => {
  try {
    await migrate();
    console.log("App listening on", PORT);
  } catch (e) {
    console.error("Migration failed:", e);
    process.exit(1); // Exit process if DB migration fails
  }
});