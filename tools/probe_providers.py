#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""挨个试 Hermes 里配好的模型，看哪个现在能用（不发密钥、不打印密钥）。"""
import json
import os
import re
import urllib.request

ENV = os.path.join(os.environ["LOCALAPPDATA"], "hermes", "profiles", "1", ".env")


def env(name):
    try:
        for line in open(ENV, encoding="utf-8", errors="ignore"):
            if line.startswith(name + "="):
                return line.split("=", 1)[1].strip().strip('"').strip("\r")
    except Exception:  # noqa: BLE001
        pass
    return ""


TARGETS = [
    ("梦幻5.6-TR", "https://mhapi.net/v1", "HERMES_CUSTOM_HACKSTART1_API_KEY", "gpt-5.6-terra"),
    ("梦幻5.6-SL", "https://mhapi.net/v1", "HERMES_CUSTOM_HACKSTART_API_KEY", "gpt-5.6-sol"),
    ("梦幻6-AS", "https://mhapi.net/v1", "HERMES_CUSTOM_CUSTOM_API_KEY", "gpt-6-astra"),
    ("米醋5.6-SL", "https://www.micuapi.ai/v1", "HERMES_CUSTOM_MICU1_API_KEY", "gpt-5.6-sol"),
    ("米醋6-AS", "https://www.micuapi.ai/v1", "HERMES_CUSTOM_MICU_API_KEY", "gpt-6-astra"),
    ("DS4-PRO", "https://openrouter.ai/api/v1", "HERMES_CUSTOM_OPENROUTER_API_KEY",
     "deepseek/deepseek-v4-pro-0813"),
    ("DS4.1-FLASH", "https://openrouter.ai/api/v1", "HERMES_CUSTOM_OPENROUTER1_API_KEY",
     "deepseek/deepseek-v4.1-flash"),
]

body_tpl = json.dumps({"model": None, "messages": [
    {"role": "user", "content": "回复两个字：可用"}], "max_tokens": 16}).encode()


def probe(name, base, keyenv, model):
    key = env(keyenv)
    if not key:
        return name, f"缺少环境变量 {keyenv}"
    body = json.loads(body_tpl)
    body["model"] = model
    req = urllib.request.Request(
        base.rstrip("/") + "/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            d = json.loads(r.read().decode("utf-8"))
        txt = d["choices"][0]["message"]["content"][:20]
        return name, f"✅ 可用 -> {txt!r}"
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read().decode("utf-8"))["error"]["message"]
        except Exception:  # noqa: BLE001
            msg = e.reason
        return name, f"❌ HTTP {e.code}: {str(msg)[:70]}"
    except Exception as e:  # noqa: BLE001
        return name, f"❌ {str(e)[:70]}"


if __name__ == "__main__":
    for t in TARGETS:
        n, res = probe(*t)
        print(f"{n:14} {res}", flush=True)
