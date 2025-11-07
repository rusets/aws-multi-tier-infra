import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import https from "node:https";

const sm = new SecretsManagerClient({});
const s3 = new S3Client({});

const GH_OWNER    = process.env.GH_OWNER;
const GH_REPO     = process.env.GH_REPO;
const GH_WORKFLOW = process.env.GH_WORKFLOW;
const GH_REF      = process.env.GH_REF || "refs/heads/main";
const GH_SECRET   = process.env.GH_SECRET_NAME;
const S3_BUCKET   = process.env.S3_BUCKET || "";
const S3_PREFIX   = process.env.S3_PREFIX || "";

function parseToken(secretString) {
  try {
    const obj = JSON.parse(secretString);
    if (obj.token) return obj.token;
  } catch {}
  return (secretString || "").trim();
}

function ghDispatch(token) {
  const payload = JSON.stringify({
    ref: GH_REF,
    inputs: { action: "apply", auto_approve: "true" }
  });

  const options = {
    hostname: "api.github.com",
    path: `/repos/${GH_OWNER}/${GH_REPO}/actions/workflows/${GH_WORKFLOW}/dispatches`,
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/vnd.github+json",
      "User-Agent": "lambda-wake",
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(payload)
    }
  };

  return new Promise((resolve) => {
    const req = https.request(options, (res) => {
      res.on("data", () => {});
      res.on("end", () => resolve(res.statusCode));
    });
    req.on("error", () => resolve(0));
    req.write(payload);
    req.end();
  });
}

export const handler = async () => {
  const immediate = {
    statusCode: 202,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "https://app.multi-tier.space",
      "Vary": "Origin"
    },
    body: JSON.stringify({ ok: true, accepted: true })
  };

  (async () => {
    try {
      const sec = await sm.send(new GetSecretValueCommand({ SecretId: GH_SECRET }));
      const token = parseToken(sec.SecretString || "");
      const code = await ghDispatch(token);

      if (S3_BUCKET) {
        const key = `${S3_PREFIX ? S3_PREFIX.replace(/\/?$/, "/") : ""}status.json`;
        const body = JSON.stringify({ last_wake: new Date().toISOString(), gh_dispatch: code });
        await s3.send(new PutObjectCommand({
          Bucket: S3_BUCKET,
          Key: key,
          Body: body,
          ContentType: "application/json",
          CacheControl: "no-store"
        }));
      }
    } catch (e) {
      console.error("wake error", e);
    }
  })();

  return immediate;
};