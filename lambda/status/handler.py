import os, json, ssl, urllib.request

TARGET_URL = os.environ.get("TARGET_URL", "https://multi-tier.space/")
REQUEST_TIMEOUT = float(os.environ.get("REQUEST_TIMEOUT", "2.5"))

def handler(event, context):
    try:
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(TARGET_URL, timeout=REQUEST_TIMEOUT, context=ctx) as r:
            if 200 <= r.status < 400:
                body = json.dumps({"state": "ready"})
                return {"statusCode": 200, "headers": {"Content-Type": "application/json","Cache-Control":"no-store"}, "body": body}
    except Exception:
        pass
    body = json.dumps({"state": "waking"})
    return {"statusCode": 200, "headers": {"Content-Type": "application/json","Cache-Control":"no-store"}, "body": body}
