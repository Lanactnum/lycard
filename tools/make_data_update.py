#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把「可热更的数据」打成一个 zip，供 App 侧 `DataUpdateService.installFromFile` 安装。

背景
----
App 已经有热更机制（`lib/services/data_update_service.dart`）：
优先读 `data_update/` 目录里的文件，读不到才回退内置资源。
白名单就这几个：

    cards_app.json / translations_zh.json / name_refs.json /
    keywords.json / banlist.json / search_keys.json.gz

但之前只能**手动**从文件管理器选 zip。本工具负责生成那个 zip，
再配合 GitHub Release 就是一个可下载的渠道。

产物
----
    dist/lycard-data-<version>.zip
        ├── data_version.json     版本号 / 说明 / 文件清单
        ├── cards_app.json
        ├── translations_zh.json
        ├── search_keys.json.gz
        └── ...（只放存在的）
    dist/lycard-data-<version>.zip.sha256

用法
----
    python tools/make_data_update.py                 # 版本号用「今天 + 卡数」
    python tools/make_data_update.py --version 2026.11.06
    python tools/make_data_update.py --notes "新增 LO-7xxx 共 358 张"
"""
import argparse
import hashlib
import json
import os
import sys
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "assets", "data")
DIST = os.path.join(ROOT, "dist")

# 和 DataUpdateService.logicalToAsset 的 key 一一对应
FILES = [
    "cards_app.json",
    "translations_zh.json",
    "name_refs.json",
    "keywords.json",
    "banlist.json",
    "search_keys.json.gz",
]


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", default="")
    ap.add_argument("--notes", default="")
    ap.add_argument("--out-dir", default=DIST)
    args = ap.parse_args()

    present = []
    for name in FILES:
        p = os.path.join(DATA, name)
        if os.path.exists(p) and os.path.getsize(p) > 0:
            present.append(name)
        else:
            print(f"  跳过（不存在）：{name}")

    if "cards_app.json" not in present:
        print("缺 cards_app.json，没法做数据更新包", file=sys.stderr)
        return 2

    cards = json.load(open(os.path.join(DATA, "cards_app.json"), encoding="utf-8"))
    version = args.version or time.strftime("%Y.%m.%d")
    notes = args.notes or f"{len(cards)} 张卡"

    manifest = {
        "version": version,
        "notes": notes,
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "card_count": len(cards),
        "files": {n: str(os.path.getsize(os.path.join(DATA, n))) for n in present},
        # 额外给一份 sha256：App 目前不校验，但人/脚本能验
        "sha256": {n: sha256_of(os.path.join(DATA, n)) for n in present},
    }

    os.makedirs(args.out_dir, exist_ok=True)
    out = os.path.join(args.out_dir, f"lycard-data-{version}.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        z.writestr("data_version.json",
                   json.dumps(manifest, ensure_ascii=False, indent=2))
        for n in present:
            z.write(os.path.join(DATA, n), n)

    size = os.path.getsize(out)
    digest = sha256_of(out)
    with open(out + ".sha256", "w", encoding="utf-8") as f:
        f.write(f"{digest}  {os.path.basename(out)}\n")

    print()
    print(f"版本      : {version}")
    print(f"说明      : {notes}")
    print(f"卡数      : {len(cards)}")
    print(f"文件      : {', '.join(present)}")
    print(f"产物      : {out}（{size/1048576:.1f} MB）")
    print(f"sha256    : {digest}")
    print()
    print("发布：")
    print(f'  gh release create data-{version} --repo Lanactnum/lycard-updates \\')
    print(f'    --title "数据更新 {version}" --notes "{notes}" \\')
    print(f"    {out} {out}.sha256")
    return 0


if __name__ == "__main__":
    sys.exit(main())
