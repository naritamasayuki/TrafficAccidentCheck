#!/usr/bin/env python3
"""警察庁コードブック(xlsx)の指定シートを標準ライブラリのみでテキスト出力する開発用スクリプト。"""
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
      "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships"}


def main(path, wanted):
    z = zipfile.ZipFile(path)
    ss = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root.findall("m:si", NS):
            ss.append("".join(t.text or "" for t in si.iter("{%s}t" % NS["m"])))
    wb = ET.fromstring(z.read("xl/workbook.xml"))
    rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
    relmap = {r.get("Id"): r.get("Target") for r in rels}
    for sh in wb.find("m:sheets", NS):
        name = sh.get("name")
        if wanted and not any(w in name for w in wanted):
            continue
        target = relmap[sh.get("{%s}id" % NS["r"])]
        target = target.lstrip("/")
        if not target.startswith("xl/"):
            target = "xl/" + target
        root = ET.fromstring(z.read(target))
        print("=====", name)
        for row in root.iter("{%s}row" % NS["m"]):
            vals = []
            for c in row.findall("m:c", NS):
                v = c.find("m:v", NS)
                if v is None:
                    is_ = c.find("m:is", NS)
                    if is_ is not None:
                        vals.append("".join(t.text or "" for t in is_.iter("{%s}t" % NS["m"])))
                    continue
                val = v.text or ""
                if c.get("t") == "s":
                    val = ss[int(val)]
                vals.append(re.sub(r"\s+", " ", val))
            if vals:
                print(" | ".join(vals))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2:])
