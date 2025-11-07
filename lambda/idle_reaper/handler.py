import os, json, time, urllib.request, boto3

SSM = boto3.client("ssm")

def _github_dispatch(owner, repo, workflow, ref, token, action):
    payload = json.dumps({"ref": ref, "inputs": {"action": action, "auto_approve": "true"}}).encode("utf-8")
    req = urllib.request.Request(
        f"https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow}/dispatches",
        data=payload, method="POST",
        headers={
            "User-Agent":"idle-reaper",
            "Authorization":f"token {token}",
            "Accept":"application/vnd.github.v3+json",
            "Content-Type":"application/json"
        }
    )
    with urllib.request.urlopen(req, timeout=10):
        return True

def handler(event, context):
    param_name = os.environ.get("HEARTBEAT_PARAM", "/multi-tier/last_heartbeat")
    idle_min = int(os.environ.get("IDLE_MINUTES","20"))
    owner = os.environ["GH_OWNER"]; repo = os.environ["GH_REPO"]
    workflow = os.environ.get("GH_WORKFLOW","infra.yml"); ref = os.environ.get("GH_REF","refs/heads/main")
    region = os.environ.get("REGION","us-east-1"); secret_name = os.environ["GH_SECRET_NAME"]
    sm = boto3.client("secretsmanager", region_name=region)

    try:
        v = SSM.get_parameter(Name=param_name)["Parameter"]["Value"]
        last = int(v)
    except Exception:
        return {"skipped":"no-heartbeat"}

    if time.time() - last < idle_min*60:
        return {"status":"active"}

    try:
        sec = sm.get_secret_value(SecretId=secret_name)
        token = json.loads(sec.get("SecretString","{}")).get("token") or sec.get("SecretString")
        _github_dispatch(owner, repo, workflow, ref, token, "destroy")
        return {"destroy":"triggered"}
    except Exception as e:
        return {"error":str(e)}
