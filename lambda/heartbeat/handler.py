import os, time, json, boto3, urllib.request, ssl

S3  = boto3.client("s3")
SSM = boto3.client("ssm")

BUCKET = os.environ["S3_BUCKET"]
PREFIX = os.environ.get("S3_PREFIX","")
TARGET = os.environ.get("TARGET_URL", "https://multi-tier.space/")
PARAM  = os.environ.get("HEARTBEAT_PARAM", "/multi-tier/last_heartbeat")
TIMEOUT = float(os.environ.get("REQUEST_TIMEOUT","2.5"))

def handler(event, context):
    ready = False
    try:
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(TARGET, timeout=TIMEOUT, context=ctx) as r:
            ready = (200 <= r.status < 400)
    except Exception:
        ready = False
    status = {"state": "ready" if ready else "waking", "ts": int(time.time())}
    key = f"{PREFIX}status.json" if PREFIX else "status.json"
    S3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(status).encode("utf-8"),
                  ContentType="application/json", ServerSideEncryption="AES256")
    if ready:
        SSM.put_parameter(Name=PARAM, Value=str(int(time.time())), Type="String", Overwrite=True)
    return status
