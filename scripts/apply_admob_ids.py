#!/usr/bin/env python3
"""
Google AdMob の「アプリ ID (ca-app-pub-...~...)」および
「バナー広告ユニット ID (ca-app-pub-.../...)」を検証し、
Config/Secrets.xcconfig に安全に書き込むヘルパースクリプト。
"""
import os
import re
import subprocess
import sys

APP_ID_RE = re.compile(r"ca-app-pub-\d{16}~\d{10}")
UNIT_ID_RE = re.compile(r"ca-app-pub-\d{16}/\d{10}")


def update_secrets(app_id: str, unit_id: str, secrets_path: str) -> None:
    lines = []
    if os.path.exists(secrets_path):
        with open(secrets_path, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    else:
        lines = [
            "// 自動生成された Secrets.xcconfig（Git 管理対象外）",
            "GOOGLE_MAPS_API_KEY = YOUR_API_KEY_HERE",
        ]

    has_app = False
    has_unit = False
    new_lines = []
    for line in lines:
        if line.strip().startswith("ADMOB_APP_ID"):
            if app_id:
                new_lines.append(f"ADMOB_APP_ID = {app_id}")
                has_app = True
            else:
                new_lines.append(line)
                has_app = True
        elif line.strip().startswith("ADMOB_BANNER_UNIT_ID"):
            if unit_id:
                new_lines.append(f"ADMOB_BANNER_UNIT_ID = {unit_id}")
                has_unit = True
            else:
                new_lines.append(line)
                has_unit = True
        else:
            new_lines.append(line)

    if not has_app and app_id:
        new_lines.append(f"ADMOB_APP_ID = {app_id}")
    if not has_unit and unit_id:
        new_lines.append(f"ADMOB_BANNER_UNIT_ID = {unit_id}")

    with open(secrets_path, "w", encoding="utf-8") as f:
        f.write("\n".join(new_lines) + "\n")


def main() -> int:
    here = os.path.dirname(os.path.abspath(__file__))
    secrets_path = os.path.join(here, "..", "Config", "Secrets.xcconfig")

    text = " ".join(sys.argv[1:])
    if not text:
        try:
            text = subprocess.check_output(["pbpaste"], text=True)
        except Exception:
            text = ""

    app_match = APP_ID_RE.search(text)
    unit_match = UNIT_ID_RE.search(text)

    app_id = app_match.group(0) if app_match else ""
    unit_id = unit_match.group(0) if unit_match else ""

    if not app_id and not unit_id:
        print("有効な AdMob ID (ca-app-pub-...) が見つかりませんでした。", file=sys.stderr)
        return 1

    update_secrets(app_id, unit_id, secrets_path)
    print(f"Secrets.xcconfig を更新しました: AppID={app_id or '変更なし'}, UnitID={unit_id or '変更なし'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
