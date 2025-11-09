import os, json, time, urllib.request, urllib.error, boto3, random

ssm = boto3.client("ssm")
autoscaling = boto3.client("autoscaling")

GUARD_PARAM = "/multi-tier-demo/destroy_dispatched_epoch"
GUARD_COOLDOWN_SEC = int(os.environ.get("DISPATCH_COOLDOWN_SEC", str(30 * 60)))
GH_RETRIES = 3

def _recent_destroy_dispatched() -> bool:
    try:
        v = ssm.get_parameter(Name=GUARD_PARAM, WithDecryption=True)["Parameter"]["Value"]
        recent = (int(time.time()) - int(v)) < GUARD_COOLDOWN_SEC
        if recent:
            print(json.dumps({"skip": "destroy_already_dispatched_recently", "age_sec": int(time.time()) - int(v)}))
        return recent
    except Exception:
        return False

def _mark_destroy_dispatched():
    ssm.put_parameter(
        Name=GUARD_PARAM,
        Type="String",
        Overwrite=True,
        Value=str(int(time.time()))
    )

def _github_dispatch(owner, repo, workflow, ref, token, action):
    url = f"https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow}/dispatches"
    payload = json.dumps({"ref": ref, "inputs": {"action": action, "auto_approve": "true"}}).encode("utf-8")
    for attempt in range(1, GH_RETRIES + 1):
        req = urllib.request.Request(url, data=payload, method="POST")
        req.add_header("Accept", "application/vnd.github+json")
        req.add_header("Authorization", f"Bearer {token}")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", errors="ignore")
            print(json.dumps({"stage": "github_dispatch_http_error", "code": e.code, "body": body, "attempt": attempt}))
            if e.code in (401, 403, 422):
                raise
        except Exception as e:
            print(json.dumps({"stage": "github_dispatch_network_error", "error": str(e), "attempt": attempt}))
        time.sleep(min(15, 2 ** attempt) + random.random())
    raise RuntimeError("github_dispatch_failed_after_retries")

def handler(event, context):
    param_name = os.environ.get("HEARTBEAT_PARAM", "/multi-tier-demo/last_wake")
    idle_min = int(os.environ.get("IDLE_MINUTES", "20"))
    owner = os.environ["GH_OWNER"]
    repo = os.environ["GH_REPO"]
    workflow = os.environ.get("GH_WORKFLOW", "infra.yml")
    ref = os.environ.get("GH_REF", "main")
    region = os.environ.get("REGION", "us-east-1")
    asg_name = os.environ.get("ASG_NAME", "")
    secret_name = os.environ["GH_SECRET_NAME"]

    try:
        armed_value = ssm.get_parameter(Name="/multi-tier-demo/reaper_armed", WithDecryption=True)["Parameter"]["Value"].strip().lower()
        if armed_value not in ("on", "true", "1", "yes"):
            print(json.dumps({"skip": "reaper_not_armed"}))
            return {"ok": True, "action": "noop_not_armed"}
    except Exception:
        print(json.dumps({"skip": "reaper_not_armed"}))
        return {"ok": True, "action": "noop_not_armed"}

    try:
        last = int(ssm.get_parameter(Name=param_name, WithDecryption=True)["Parameter"]["Value"])
    except Exception as e:
        print(json.dumps({"stage": "read_last_wake_failed", "error": str(e)}))
        return {"skipped": "no-last-wake"}

    now = int(time.time())
    idle_sec = now - last
    should_destroy = idle_sec >= idle_min * 60

    print(json.dumps({
        "now": now, "last_wake": last, "idle_sec": idle_sec,
        "idle_min": idle_min, "should_destroy": should_destroy
    }))

    if not should_destroy:
        return {"status": "active", "idle_sec": idle_sec}

    if _recent_destroy_dispatched():
        return {"ok": True, "action": "noop_recent_dispatch"}

    try:
        token = ssm.get_parameter(Name=secret_name, WithDecryption=True)["Parameter"]["Value"]
    except Exception as e:
        print(json.dumps({"stage": "read_token_failed", "error": str(e), "secret_name": secret_name}))
        return {"error": "no-github-token"}

    try:
        if asg_name:
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                MinSize=0,
                DesiredCapacity=0
            )
            print(json.dumps({"asg_scaled_to_zero": True, "asg_name": asg_name, "region": region}))
    except Exception as e:
        print(json.dumps({"stage": "asg_update_failed", "error": str(e), "asg_name": asg_name}))

    try:
        status = _github_dispatch(owner, repo, workflow, ref, token, "destroy")
        print(json.dumps({"github_dispatch_status": status}))
        _mark_destroy_dispatched()
        return {"destroy": "triggered", "github_status": status}
    except urllib.error.HTTPError as e:
        return {"error": f"github_dispatch_http_{e.code}"}
    except Exception as e:
        print(json.dumps({"stage": "github_dispatch_failed_final", "error": str(e)}))
        return {"error": "github_dispatch_failed"}