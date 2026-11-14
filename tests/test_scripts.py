#!/usr/bin/env python3
"""
データ変換スクリプト (build_accident_data.py) および
SNS速報収集スクリプト (fetch_sns_accidents.py) のユニットテスト。
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))

import build_accident_data  # noqa: E402
import fetch_sns_accidents  # noqa: E402
import apply_admob_ids  # noqa: E402


class TestBuildAccidentData(unittest.TestCase):
    """警察庁オープンデータ変換ロジックの単体テスト。"""

    def test_dms_to_deg_valid(self):
        # 43度06分07.590秒 -> 約 43.1021083 度
        lat = build_accident_data.dms_to_deg("430607590", 2)
        self.assertIsNotNone(lat)
        self.assertAlmostEqual(lat, 43 + 6 / 60 + 7.590 / 3600, places=6)

        # 141度21分09.644秒 -> 約 141.3526788 度
        lon = build_accident_data.dms_to_deg("1412109644", 3)
        self.assertIsNotNone(lon)
        self.assertAlmostEqual(lon, 141 + 21 / 60 + 9.644 / 3600, places=6)

    def test_dms_to_deg_invalid(self):
        # 0 や非数値、60分以上の異常値は None を返すこと
        self.assertIsNone(build_accident_data.dms_to_deg("000000000", 2))
        self.assertIsNone(build_accident_data.dms_to_deg("abc", 2))
        self.assertIsNone(build_accident_data.dms_to_deg("359900000", 2))

    def test_normalize_header(self):
        self.assertEqual(build_accident_data.normalize("発生日時\u3000\u3000年"), "発生日時年")
        self.assertEqual(build_accident_data.normalize(" 地点 緯度（北緯） "), "地点緯度（北緯）")

    def test_to_int_bounds(self):
        self.assertEqual(build_accident_data.to_int("03"), 3)
        self.assertEqual(build_accident_data.to_int("999", cap=255), 255)
        self.assertEqual(build_accident_data.to_int("invalid", default=7), 7)


class TestFetchSNSAccidents(unittest.TestCase):
    """SNS速報フィルタリングおよび地名抽出ロジックの単体テスト。"""

    def test_is_traffic_accident_text(self):
        self.assertTrue(fetch_sns_accidents.is_traffic_accident_text("東京都新宿区の交差点で追突事故が発生"))
        self.assertFalse(fetch_sns_accidents.is_traffic_accident_text("昨日の番組は放送事故だった"))
        self.assertFalse(fetch_sns_accidents.is_traffic_accident_text(""))

    def test_extract_location_candidates(self):
        places = fetch_sns_accidents.extract_location_candidates(
            "神奈川県横浜市港北区の環状2号線付近で乗用車の衝突事故が発生しています"
        )
        self.assertTrue(any("神奈川県横浜市" in p for p in places))

    def test_infer_category(self):
        self.assertEqual(fetch_sns_accidents.infer_category("横断歩道で歩行者がはねられる事故"), "人対車両（未確認）")
        self.assertEqual(fetch_sns_accidents.infer_category("ガードレールに衝突する単独事故"), "車両単独（未確認）")
        self.assertEqual(fetch_sns_accidents.infer_category("交差点で乗用車同士が出会い頭に衝突"), "車両相互・その他（未確認）")

    def test_fallback_seed_reports_structure(self):
        seeds = fetch_sns_accidents.get_fallback_seed_reports()
        self.assertGreaterEqual(len(seeds), 5)
        for item in seeds:
            self.assertTrue(item["isUnverified"])
            self.assertIn("SNS", item["sourceName"])
            self.assertTrue(20.0 <= item["latitude"] <= 46.0)
            self.assertTrue(122.0 <= item["longitude"] <= 154.0)

    def test_admob_id_regex_patterns(self):
        sample = "App: ca-app-pub-1234567890123456~0987654321 Unit: ca-app-pub-1234567890123456/1122334455"
        app_match = apply_admob_ids.APP_ID_RE.search(sample)
        unit_match = apply_admob_ids.UNIT_ID_RE.search(sample)
        self.assertIsNotNone(app_match)
        self.assertIsNotNone(unit_match)
        self.assertEqual(app_match.group(0), "ca-app-pub-1234567890123456~0987654321")
        self.assertEqual(unit_match.group(0), "ca-app-pub-1234567890123456/1122334455")


if __name__ == "__main__":
    unittest.main()
