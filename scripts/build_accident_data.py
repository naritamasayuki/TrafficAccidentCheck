#!/usr/bin/env python3
"""
警察庁「交通事故統計情報のオープンデータ」(本票 honhyo_YYYY.csv) を
アプリ同梱用のコンパクトなバイナリ (accidents.bin) に変換するスクリプト。

使い方:
    # 年を指定して自動ダウンロード＆変換（ネットワーク必要）
    python3 scripts/build_accident_data.py --years 2024 2025

    # 手元の CSV を変換
    python3 scripts/build_accident_data.py --csv data_raw/honhyo_2024.csv data_raw/honhyo_2025.csv

    # 都道府県を絞り込む（コードは警察庁コードブック参照。例: 30=東京, 45=神奈川）
    python3 scripts/build_accident_data.py --years 2025 --pref 30 45

出典: 警察庁 交通事故統計情報のオープンデータ
https://www.npa.go.jp/publications/statistics/koutsuu/opendata/index_opendata.html

バイナリ形式 (リトルエンディアン):
    Header (16 bytes):
        magic   4s  b"TACD"
        version u32 = 1
        count   u32
        reserved u32
    Record (32 bytes) × count:
        lat_e6   i32   緯度 × 1e6 (世界測地系 10進)
        lon_e6   i32   経度 × 1e6
        year     u16
        month    u8
        day      u8
        hour     u8
        minute   u8
        severity u8   1=死亡事故 2=負傷事故
        deaths   u8
        injuries u8
        weather  u8
        daynight u8
        surface  u8
        road     u8   道路形状
        signal   u8
        type     u8   事故類型
        weekday  u8
        holiday  u8
        party_a  u8   当事者種別(A)
        party_b  u8   当事者種別(B)
        age_a    u8
        age_b    u8
        pref     u8   都道府県コード
        injury_a u8   人身損傷程度(A)
        injury_b u8   人身損傷程度(B)
"""
import argparse
import csv
import io
import os
import struct
import sys
import urllib.request

BASE_URL = "https://www.npa.go.jp/publications/statistics/koutsuu/opendata/{y}/honhyo_{y}.csv"
RECORD = struct.Struct("<iiHBBBBBBBBBBBBBBBBBBBBBB")
HEADER = struct.Struct("<4sIII")
assert RECORD.size == 32, RECORD.size

# CSV ヘッダー名（全角スペースの数が年により揺れるため正規化して照合）
COLUMNS = {
    "pref": "都道府県コード",
    "content": "事故内容",
    "deaths": "死者数",
    "injuries": "負傷者数",
    "year": "発生日時年",
    "month": "発生日時月",
    "day": "発生日時日",
    "hour": "発生日時時",
    "minute": "発生日時分",
    "daynight": "昼夜",
    "weather": "天候",
    "surface": "路面状態",
    "road": "道路形状",
    "signal": "信号機",
    "type": "事故類型",
    "age_a": "年齢（当事者A）",
    "age_b": "年齢（当事者B）",
    "party_a": "当事者種別（当事者A）",
    "party_b": "当事者種別（当事者B）",
    "injury_a": "人身損傷程度（当事者A）",
    "injury_b": "人身損傷程度（当事者B）",
    "lat": "地点緯度（北緯）",
    "lon": "地点経度（東経）",
    "weekday": "曜日(発生年月日)",
    "holiday": "祝日(発生年月日)",
}


def normalize(name: str) -> str:
    return name.replace("\u3000", "").replace(" ", "").replace("\ufeff", "").strip()


def dms_to_deg(value: str, deg_digits: int):
    """'430607590' -> 43 + 06/60 + 07.590/3600"""
    v = value.strip()
    if not v.isdigit() or int(v) == 0:
        return None
    v = v.zfill(deg_digits + 7)
    d = int(v[:deg_digits])
    m = int(v[deg_digits:deg_digits + 2])
    s = int(v[deg_digits + 2:]) / 1000.0
    if m >= 60 or s >= 60:
        return None
    return d + m / 60.0 + s / 3600.0


def to_int(value: str, default=0, cap=255) -> int:
    try:
        return max(0, min(cap, int(value.strip())))
    except (ValueError, AttributeError):
        return default


def read_csv_bytes(data: bytes):
    for enc in ("cp932", "utf-8-sig"):
        try:
            text = data.decode(enc)
            break
        except UnicodeDecodeError:
            continue
    else:
        raise ValueError("unknown encoding")
    return csv.reader(io.StringIO(text))


def convert(rows, pref_filter, out_records, stats):
    header = next(rows)
    idx_by_norm = {normalize(h): i for i, h in enumerate(header)}
    idx = {}
    for key, col in COLUMNS.items():
        n = normalize(col)
        if n not in idx_by_norm:
            raise KeyError(f"列が見つかりません: {col}")
        idx[key] = idx_by_norm[n]

    for row in rows:
        if len(row) < len(header):
            continue

        def g(k: str) -> str:
            return row[idx[k]]

        pref = to_int(g("pref"))
        if pref_filter and pref not in pref_filter:
            continue
        lat = dms_to_deg(g("lat"), 2)
        lon = dms_to_deg(g("lon"), 3)
        if lat is None or lon is None or not (20 <= lat <= 46 and 122 <= lon <= 154):
            stats["skipped"] += 1
            continue
        out_records.append(RECORD.pack(
            int(round(lat * 1e6)), int(round(lon * 1e6)),
            to_int(g("year"), cap=65535), to_int(g("month")), to_int(g("day")),
            to_int(g("hour")), to_int(g("minute")),
            to_int(g("content")), to_int(g("deaths")), to_int(g("injuries")),
            to_int(g("weather")), to_int(g("daynight")), to_int(g("surface")),
            to_int(g("road")), to_int(g("signal")), to_int(g("type")),
            to_int(g("weekday")), to_int(g("holiday")),
            to_int(g("party_a")), to_int(g("party_b")),
            to_int(g("age_a")), to_int(g("age_b")),
            pref, to_int(g("injury_a")), to_int(g("injury_b")),
        ))
        stats["ok"] += 1


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default_out = os.path.join(here, "..", "TrafficAccidentCheck", "Resources", "accidents.bin")

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--years", nargs="*", type=int, default=[], help="ダウンロードする年 (例: 2024 2025)")
    ap.add_argument("--csv", nargs="*", default=[], help="変換するローカル CSV")
    ap.add_argument("--pref", nargs="*", type=int, default=[], help="都道府県コードで絞り込み")
    ap.add_argument("--out", default=default_out, help="出力先")
    args = ap.parse_args()

    if not args.years and not args.csv:
        ap.error("--years か --csv を指定してください")

    records, stats = [], {"ok": 0, "skipped": 0}
    pref_filter = set(args.pref)

    for path in args.csv:
        print(f"読み込み: {path}", file=sys.stderr)
        with open(path, "rb") as f:
            convert(read_csv_bytes(f.read()), pref_filter, records, stats)

    for y in args.years:
        url = BASE_URL.format(y=y)
        print(f"ダウンロード: {url}", file=sys.stderr)
        with urllib.request.urlopen(url) as res:
            convert(read_csv_bytes(res.read()), pref_filter, records, stats)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with open(args.out, "wb") as f:
        f.write(HEADER.pack(b"TACD", 1, len(records), 0))
        for r in records:
            f.write(r)

    size_mb = os.path.getsize(args.out) / 1024 / 1024
    print(f"完了: {stats['ok']} 件 (座標不正でスキップ {stats['skipped']} 件) -> {args.out} ({size_mb:.1f} MB)",
          file=sys.stderr)


if __name__ == "__main__":
    main()
