#!/bin/bash
set -euo pipefail

LOG="/var/log/rdapp-userdata.log"
exec > >(tee -a "$LOG") 2>&1
echo "[$(hostname)] $(date -Is) user_data start"

REGION="${REGION}"
PARAM_PATH="${PARAM_PATH}"

SSM_ROOT="$PARAM_PATH"
if [[ -z "$SSM_ROOT" ]]; then
  SSM_ROOT="/multi-tier-demo"
fi
echo "Using SSM_ROOT=$SSM_ROOT"

APP_PORT="${APP_PORT}"
RDS_SECRET_ARN="${RDS_SECRET_ARN}"

export AWS_DEFAULT_REGION="$REGION"

echo "Installing base packages..."
dnf -y makecache >/dev/null || true
dnf -y install unzip jq awscli coreutils findutils git nodejs nodejs-npm postgresql15 >/dev/null

echo "Preparing /opt/app structure..."
install -d -m 0755 /opt/app/releases
install -d -m 0755 /opt/app/current

get_param() {
  local name="$1"
  aws ssm get-parameter --name "$name" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null || true
}

SSM_ROOT="$PARAM_PATH"
if [[ -z "$SSM_ROOT" ]]; then
  SSM_ROOT="/multi-tier-demo"
fi

echo "Reading SSM parameters..."
ASSETS_BUCKET="$(get_param "$SSM_ROOT/assets_bucket")"
if [[ -z "$ASSETS_BUCKET" ]]; then
  ASSETS_BUCKET="$(get_param "/multi-tier-demo/assets_bucket")"
fi

ARTIFACT_KEY="$(get_param "$SSM_ROOT/app/artifact_key")"
if [[ -z "$ARTIFACT_KEY" ]]; then
  ARTIFACT_KEY="artifacts/app-initial.zip"
fi

DB_HOST="$( get_param "$SSM_ROOT/db/host" || true )"
DB_USER="$( get_param "$SSM_ROOT/db/username" || true )"
DB_PASS="$( get_param "$SSM_ROOT/db/password" || true )"
DB_NAME="$( get_param "$SSM_ROOT/db/name" || true )"
[[ -z "$DB_NAME" ]] && DB_NAME="notes"

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

APP_DIR="/opt/app/current"
if [[ -d "$APP_DIR/app" && ! -f "$APP_DIR/package.json" ]]; then
  shopt -s dotglob
  mv "$APP_DIR/app"/* "$APP_DIR"/
  rmdir "$APP_DIR/app"
fi

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
DB_PASSWORD=$DB_PASS
DB_PASS=$DB_PASS
DB_NAME=$DB_NAME
ENVEOF
chmod 0640 /opt/app/current/.env

cat >/etc/systemd/system/rdapp.service <<'UNIT'
[Unit]
Description=Notes Demo App
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/opt/app/current/.env
WorkingDirectory=/opt/app/current
ExecStart=/usr/bin/node /opt/app/current/server.js
Restart=always
RestartSec=3
User=root
LimitNOFILE=65536
TimeoutStartSec=60

[Install]
WantedBy=multi-user.target
UNIT

echo "Enabling service..."
systemctl daemon-reload
systemctl enable --now rdapp.service || (sleep 2 && systemctl start rdapp.service)
systemctl status rdapp.service --no-pager || true

can_resolve_db=false
if [[ -n "$DB_HOST" ]] && getent ahostsv4 "$DB_HOST" >/dev/null 2>&1; then
  can_resolve_db=true
fi

if [[ "$can_resolve_db" == true ]]; then
  echo "DB is resolvable; running migrations..."
  if [[ -f /opt/app/current/knexfile.js ]]; then
    echo "Knex detected; running migrations..."
    DB_HOST="$DB_HOST" \
    DB_USER="$DB_USER" \
    DB_PASSWORD="$DB_PASS" \
    DB_NAME="$DB_NAME" \
    NODE_ENV=production \
    npx --yes knex migrate:latest --knexfile /opt/app/current/knexfile.js || echo "WARN: Knex migration failed; continuing."
  else
    echo "Knex not found; using SQL fallback..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 \
      -c "CREATE DATABASE \"$DB_NAME\"" 2>/dev/null || echo "DB $DB_NAME already exists"
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
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
else
  echo "WARN: DB_HOST empty or not resolvable; skipping migrations."
fi

echo "$(date -Is) user_data done"