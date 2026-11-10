#!/usr/bin/env python3
# 煙霧測試：對三個模型送 function calling 請求，確認 provider.ignore 之後工具呼叫仍正常。
# 只印 finish_reason 與 tool_calls 名稱，不輸出任何金鑰。
import json
import subprocess
import urllib.request

PROXY = "http://127.0.0.1:4000"
MODELS = [
    "z-ai/glm-5.3",
    "z-ai/glm-5.3-flash",
    "deepseek/deepseek-v4.1-flash-1017",
]

TOOL = [
    {
        "type": "function",
        "function": {
            "name": "get_weather",
            "description": "Get the current weather for a city",
            "parameters": {
                "type": "object",
                "properties": {"city": {"type": "string"}},
                "required": ["city"],
            },
        },
    }
]


def master_key() -> str:
    out = subprocess.run(
        ["docker", "exec", "litellm-proxy", "env"], capture_output=True, text=True
    ).stdout
    for line in out.splitlines():
        if line.startswith("LITELLM_MASTER_KEY="):
            return line.split("=", 1)[1].strip()
    return ""


def main() -> int:
    key = master_key()
    if not key:
        print("ERROR: 取不到 master key")
        return 1
    print("MASTER_KEY: " + key[:6] + "...")
    for model in MODELS:
        body = {
            "model": model,
            "messages": [
                {"role": "user", "content": "What is the weather in Tokyo? Use the tool."}
            ],
            "tools": TOOL,
            "tool_choice": "auto",
            "max_tokens": 128,
        }
        req = urllib.request.Request(
            PROXY + "/v1/chat/completions",
            data=json.dumps(body).encode(),
            headers={
                "Authorization": "Bearer " + key,
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = json.load(resp)
        except Exception as exc:
            detail = exc.read().decode()[:400] if hasattr(exc, "read") else ""
            print("%-34s FAIL %s %s" % (model, exc, detail))
            continue
        choice = (data.get("choices") or [{}])[0]
        message = choice.get("message") or {}
        calls = message.get("tool_calls") or []
        names = [c.get("function", {}).get("name") for c in calls]
        print(
            "%-34s finish=%-12s tool_calls=%d %s"
            % (model, choice.get("finish_reason"), len(calls), names)
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
