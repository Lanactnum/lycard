#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""列出 Hermes 配置里的 provider（不打印任何密钥）。"""
import os
import sys

try:
    import yaml
except ImportError:
    sys.exit("需要 pyyaml：用 hermes 的 venv python 跑")

cfg = os.path.join(os.environ["LOCALAPPDATA"], "hermes", "profiles", "1", "config.yaml")
d = yaml.safe_load(open(cfg, encoding="utf-8"))

prov = d.get("providers") or {}
print(f"providers 数量：{len(prov)}\n")
for k, v in prov.items():
    if not isinstance(v, dict):
        continue
    name = v.get("name") or v.get("label") or v.get("display_name") or ""
    key = v.get("api_key") or ""
    env = v.get("api_key_env") or v.get("key_env") or ""
    has = "内嵌密钥" if key else (f"env:{env}" if env else "无")
    print(f"  id={k}")
    print(f"     name     = {name}")
    print(f"     model    = {v.get('model')}")
    print(f"     base_url = {v.get('base_url')}")
    print(f"     key      = {has}")
