#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 ios-admin 工程的所有文本文件打包成一份 JSON，
供 GitHub 连接器的 push_files 一次性推送。

用法：
    python scripts/pack_for_push.py > /tmp/push_payload.json

输出格式：
    [{"path": "...", "content": "..."}, ...]

⚠️ 只收文本文件；Assets.xcassets/ 由 CI 的 make_icon.py 生成，不进仓库。
⚠️ 二进制文件走 push_files 会被损坏（content 是字符串），必须排除。
"""

import io
import json
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

# 不推送的路径片段
SKIP_DIRS = {
    ".git", "Assets.xcassets", "build", "__pycache__", ".xcodeproj", ".xcworkspace",
}
SKIP_FILES = {
    ".DS_Store",
}
# 按扩展名白名单（只收纯文本）
TEXT_EXT = {
    ".swift", ".yml", ".yaml", ".md", ".py", ".sh", ".plist", ".json", ".txt", ".gitignore",
}


def collect():
    items = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # 原地裁剪目录，避免走进去
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name in SKIP_FILES:
                continue
            ext = os.path.splitext(name)[1].lower()
            if ext not in TEXT_EXT and name != ".gitignore":
                continue
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, ROOT).replace("\\", "/")
            try:
                with io.open(full, "r", encoding="utf-8") as f:
                    content = f.read()
            except UnicodeDecodeError:
                print("跳过（非 UTF-8 文本）: %s" % rel, file=sys.stderr)
                continue
            items.append({"path": rel, "content": content})
    return sorted(items, key=lambda x: x["path"])


def main():
    items = collect()
    json.dump(items, sys.stdout, ensure_ascii=False)
    # 统计输出到 stderr（stdout 是纯 JSON）
    total = sum(len(i["content"]) for i in items)
    print("\n共 %d 个文件，%d 字节" % (len(items), total), file=sys.stderr)
    for i in items:
        print("  %-62s %6d" % (i["path"], len(i["content"])), file=sys.stderr)


if __name__ == "__main__":
    main()
