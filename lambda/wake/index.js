import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import https from "node:https";

const ssm = new SSMClient({});
const s3  = new S3Client({});

const GH_OWNER   = process.env.GH_OWNER;
const GH_REPO    = process.env.GH_REPO;
const WF_ID      = process.env.GITHUB_WORKFLOW_ID;        
const GH_REF     = process.env.GH_REF || "main";          
const SSM_PARAM  = process.env.SSM_TOKEN_PARAM || "/gh/actions/token";
const S3_BUCKET  = process.env.S3_BUCKET || "";
const S3_PREFIX  = process.env.S3_PREFIX || "";

async function getToken() {
  const out = await ssm.send(new GetParameterCommand({ Name: SSM_PARAM, WithDecryption: true }));
  const val = out?.Parameter?.Value?.trim();
  if (!val) throw new Error("Empty token from SSM");
  return val;
}

function ghDispatch(token) {
  const payload = JSON.stringify({
    ref: GH_REF,
    inputs: { action: "apply", auto_approve: true }
  });

  const path = `/repos/${GH_OWNER}/${GH_REPO}/actions/workflows/${WF_ID}/dispatches`;

  const options = {
    hostname: "api.github.com",
    path,
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/vnd.github+json",
      "User-Agent": "lambda-wake",
      "Content-Type": "application/json",
      "Content-Length": Buffer.byteLength(payload)
    }
  };

  return new Promise((resolve) => {
    const req = https.request(options, (res) => {
      res.on("data", () => {});
      res.on("end", () => resolve(res.statusCode || 0));
    });
    req.on("error", () => resolve(0));
    req.write(payload);
    req.end();
  });
}

export const handler = async () => {
  try {
    const token = await getToken();
    const code  = await ghDispatch(token);

    if (S3_BUCKET) {
      const key  = `${S3_PREFIX ? S3_PREFIX.replace(/\/?$/, "/") : ""}status.json`;
      const body = JSON.stringify({ last_wake: new Date().toISOString(), gh_dispatch: code });
      await s3.send(new PutObjectCommand({
        Bucket: S3_BUCKET,
        Key: key,
        Body: body,
        ContentType: "application/json",
        CacheControl: "no-store"
      }));
    }

    return {
      statusCode: 202,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
        "Access-Control-Allow-Origin": "https://app.multi-tier.space",
        "Access-Control-Expose-Headers": "apigw-requestid",
        Vary: "Origin"
      },
      body: JSON.stringify({ ok: true, accepted: code === 204 })
    };
  } catch (e) {
    console.error("wake error", e);
    return {
      statusCode: 500,
      headers: { "Access-Control-Allow-Origin": "https://app.multi-tier.space" },
      body: JSON.stringify({ ok: false })
    };
  }
};