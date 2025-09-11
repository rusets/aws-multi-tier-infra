#!/bin/bash
set -euo pipefail

LOG="/var/log/rdapp-userdata.log"
exec > >(tee -a "$LOG") 2>&1

echo "[$(hostname)] $(date -Is) user_data start"

# ===== Values are substituted by Terraform via templatefile(...) =====
REGION="${REGION}"
PARAM_PATH="${PARAM_PATH}"
APP_PORT="${APP_PORT}"
RDS_SECRET_ARN="${RDS_SECRET_ARN}"  # can be empty

export AWS_DEFAULT_REGION="$REGION"

echo "Installing base packages..."
# IMPORTANT: do not install curl (curl-minimal conflict on AL2023)
dnf -y makecache >/dev/null || true
dnf -y install unzip jq awscli coreutils findutils git nodejs nodejs-npm postgresql15 >/dev/null

echo "Preparing /opt/app structure..."
install -d -m 0755 /opt/app/releases
install -d -m 0755 /opt/app/current

get_param () {
  local name="$1"
  aws ssm get-parameter --name "$name" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || true
}

echo "Reading SSM parameters..."
ASSETS_BUCKET="$(get_param "$PARAM_PATH/assets_bucket")"
if [[ -z "$ASSETS_BUCKET" ]]; then
  ASSETS_BUCKET="$(get_param "/multi-tier-demo/assets_bucket")"
fi

ARTIFACT_KEY="$(get_param "$PARAM_PATH/app/artifact_key")"
if [[ -z "$ARTIFACT_KEY" ]]; then
  ARTIFACT_KEY="artifacts/app-initial.zip"
fi

DB_HOST="$( get_param "$PARAM_PATH/db/host" || true )"
DB_USER="$( get_param "$PARAM_PATH/db/username" || true )"
DB_PASS="$( get_param "$PARAM_PATH/db/password" || true )"
DB_NAME="$( get_param "$PARAM_PATH/db/name" || true )"
[[ -z "$DB_NAME" ]] && DB_NAME="notes"

# If RDS secret is provided, it has priority
if [[ -n "$RDS_SECRET_ARN" ]]; then
  echo "Reading RDS creds from Secrets Manager: $RDS_SECRET_ARN"
  secret_json="$(aws secretsmanager get-secret-value --secret-id "$RDS_SECRET_ARN" --query SecretString --output text 2>/dev/null || true)"
  if [[ -n "$secret_json" && "$secret_json" != "null" ]]; then
    t="$(jq -r '.host // empty'      <<<"$secret_json")"; [[ -n "$t" ]] && DB_HOST="$t"
    t="$(jq -r '.username // empty'  <<<"$secret_json")"; [[ -n "$t" ]] && DB_USER="$t"
    t="$(jq -r '.password // empty'  <<<"$secret_json")"; [[ -n "$t" ]] && DB_PASS="$t"
    t="$(jq -r '.dbname // empty'    <<<"$secret_json")"; [[ -n "$t" ]] && DB_NAME="$t"
  fi
fi

echo "ASSETS_BUCKET=$ASSETS_BUCKET"
echo "ARTIFACT_KEY=$ARTIFACT_KEY"
echo "DB_HOST=$DB_HOST DB_NAME=$DB_NAME"

ts="$(date +%Y%m%d-%H%M%S)"
zip_dst="/opt/app/releases/app-$ts.zip"

echo "Downloading s3://$ASSETS_BUCKET/$ARTIFACT_KEY -> $zip_dst"
aws s3 cp "s3://$ASSETS_BUCKET/$ARTIFACT_KEY" "$zip_dst" --only-show-errors

echo "Extracting to /opt/app/current..."
rm -rf /opt/app/current/*
unzip -o "$zip_dst" -d /opt/app/current >/dev/null

pushd /opt/app/current >/dev/null
if [[ -f package-lock.json || -f npm-shrinkwrap.json ]]; then
  echo "npm ci (lockfile found, omit=dev)..."
  npm ci --omit=dev || { echo "npm ci failed, fallback to npm install"; npm install --omit=dev; }
else
  echo "No lockfile; npm install --omit=dev..."
  npm install --omit=dev
fi
popd >/dev/null

echo "Writing /opt/app/current/.env ..."
cat >/opt/app/current/.env <<ENVEOF
PORT=$APP_PORT
DB_HOST=$DB_HOST
DB_USER=$DB_USER
# Keep both for backward/forward compatibility:
DB_PASSWORD=$DB_PASS
DB_PASS=$DB_PASS
DB_NAME=$DB_NAME
ENVEOF
chmod 0640 /opt/app/current/.env

# === Database migration ===
# Prefer Knex; if no knexfile.js -> fallback to SQL.
if [[ -f /opt/app/current/knexfile.js ]]; then
  echo "Knex detected; running migrations (without sourcing .env)..."
  # Pass DB vars explicitly to avoid bash parsing issues with secrets
  DB_HOST="$DB_HOST" \
  DB_USER="$DB_USER" \
  DB_PASSWORD="$DB_PASS" \
  DB_NAME="$DB_NAME" \
  NODE_ENV=production \
  npx --yes knex migrate:latest --knexfile /opt/app/current/knexfile.js || {
    echo "Knex migration failed; exiting so systemd/ASG can replace instance."
    exit 1
  }
else
  echo "Knex not found; using SQL fallback migration..."
  # Create DB if needed (ignore 'already exists')
  PGPASSWORD="$DB_PASS" psql "sslmode=require host=$DB_HOST user=$DB_USER dbname=postgres" \
    -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE \"$DB_NAME\"" 2>/dev/null || echo "DB $DB_NAME already exists"

  # Idempotent schema
  PGPASSWORD="$DB_PASS" psql "sslmode=require host=$DB_HOST user=$DB_USER dbname=$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS public.notes (
  id          bigserial PRIMARY KEY,
  title       text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='notes' AND column_name='text'
  ) THEN
    UPDATE public.notes
       SET title = COALESCE(title,'') ||
                   CASE WHEN (title IS NULL OR title='') AND text IS NOT NULL
                        THEN text ELSE '' END
     WHERE (title IS NULL OR title='');
    ALTER TABLE public.notes DROP COLUMN text;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_notes_created_at ON public.notes(created_at DESC);
SQL
fi

# === DB migration (idempotent) ===
# This block ensures schema matches the app expectations:
# - Create database if needed
# - Create table notes(id, title, created_at) if missing
# - If legacy column "text" exists, migrate data into "title" then drop it
# - Create index on created_at if missing
if [[ -n "$DB_HOST" && -n "$DB_USER" && -n "$DB_NAME" ]]; then
  echo "Running DB migration..."

  # Create database if it does not exist (Postgres has no IF NOT EXISTS for DB; ignore error)
  PGPASSWORD="$DB_PASS" psql "sslmode=require host=$DB_HOST user=$DB_USER dbname=postgres" \
    -v ON_ERROR_STOP=1 \
    -c "CREATE DATABASE $DB_NAME" 2>/dev/null || echo "DB $DB_NAME already exists"

  # Apply schema and migration idempotently
  PGPASSWORD="$DB_PASS" psql "sslmode=require host=$DB_HOST user=$DB_USER dbname=$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
-- Ensure target table exists with the expected columns
CREATE TABLE IF NOT EXISTS public.notes (
  id          bigserial PRIMARY KEY,
  title       text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- If legacy column "text" exists, move data into "title" and drop "text"
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='notes' AND column_name='text'
  ) THEN
    -- Move legacy data into "title" only where "title" is empty
    UPDATE public.notes
       SET title = COALESCE(title,'') ||
                   CASE WHEN (title IS NULL OR title='') AND text IS NOT NULL
                        THEN text ELSE '' END
     WHERE (title IS NULL OR title='');
    -- Drop legacy column
    ALTER TABLE public.notes DROP COLUMN text;
  END IF;
END $$;

-- Helpful index for list queries
CREATE INDEX IF NOT EXISTS idx_notes_created_at ON public.notes(created_at DESC);
SQL
fi

cat >/etc/systemd/system/rdapp.service <<'UNIT'
[Unit]
Description=Notes Demo App
After=network.target

[Service]
Type=simple
EnvironmentFile=/opt/app/current/.env
WorkingDirectory=/opt/app/current
ExecStart=/usr/bin/node /opt/app/current/server.js
Restart=always
RestartSec=3
User=root
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

echo "Enabling service..."
systemctl daemon-reload
systemctl enable --now rdapp.service || (sleep 2 && systemctl start rdapp.service)

echo "$(date -Is) user_data done"