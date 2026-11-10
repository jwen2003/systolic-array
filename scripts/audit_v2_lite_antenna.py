#!/usr/bin/env python3
"""Correlate KLayout antenna items with routed metal shapes in an OpenDB file.

Run this script with OpenROAD's Python interpreter.  KLayout report items, not
their nested value records, are the unit of violation counting.
"""

import argparse
import csv
import re
import xml.etree.ElementTree as ET

import odb
from openroad import Design, Tech


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--odb", required=True)
    parser.add_argument("--lyrdb", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--net", action="append", default=[])
    parser.add_argument("--net-geometry-output")
    return parser.parse_args()


def parse_value(text):
    match = re.match(r"\[#([^]]+)\] (?:float|text): '?([^']*)'?", text)
    return (match.group(1), match.group(2)) if match else (None, None)


def parse_polygon(text):
    coords = [tuple(map(float, pair.split(",")))
              for pair in re.search(r"\((.*)\)", text).group(1).split(";")]
    xs, ys = zip(*coords)
    return min(xs), min(ys), max(xs), max(ys)


def intersects(box, marker, dbu):
    x0, y0, x1, y1 = marker
    return not (box.xMax() < x0 * dbu or box.xMin() > x1 * dbu
                or box.yMax() < y0 * dbu or box.yMin() > y1 * dbu)


args = parse_args()
root = ET.parse(args.lyrdb).getroot()
items = []
for index, item in enumerate(root.findall("./items/item"), start=1):
    values = [node.text or "" for node in item.findall("./values/value")]
    marker = parse_polygon(values[0])
    fields = {}
    for value in values[1:]:
        key, parsed = parse_value(value)
        if key:
            fields[key] = parsed
    items.append((index, item.findtext("category"), marker, fields))

tech = Tech()
design = Design(tech)
design.readDb(args.odb)
block = design.getBlock()
dbu = block.getDbUnitsPerMicron()

rows = []
for index, category, marker, fields in items:
    matches = []
    for net in block.getNets():
        wire = net.getWire()
        if wire is None:
            continue
        itr = odb.dbWirePathItr()
        path = odb.dbWirePath()
        shape = odb.dbWirePathShape()
        itr.begin(wire)
        while itr.getNextPath(path):
            while itr.getNextShape(shape):
                geom = shape.shape
                layer = geom.getTechLayer() if geom.isSegment() else None
                if layer is None or layer.getName().lower() != "metal6":
                    continue
                if intersects(geom.getBox(), marker, dbu):
                    matches.append(net)
    unique = {net.getName(): net for net in matches}
    if not unique:
        unique = {"unknown": None}
    for net_name, net in sorted(unique.items()):
        rows.append({
            "marker": index,
            "category": category,
            "bbox_um": ";".join(map(str, marker)),
            "net": net_name,
            "bterms": "" if net is None else ";".join(
                sorted(term.getName() for term in net.getBTerms())),
            "iterms": "" if net is None else ";".join(sorted(
                f"{term.getInst().getName()}/{term.getMTerm().getName()}"
                for term in net.getITerms())),
            "ametal_um2": fields.get("ametal", "unavailable"),
            "agate_um2": fields.get("agate", "unavailable"),
            "adiodes_um2": fields.get("adiodes", "unavailable"),
            "ratio": fields.get("ratio", "unavailable"),
            "threshold": fields.get("max_ratio", "unavailable"),
        })

fieldnames = list(rows[0]) if rows else ["marker", "category"]
with open(args.output, "w", newline="", encoding="utf-8") as stream:
    writer = csv.DictWriter(stream, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)
print(f"KLayout DRC items: {len(items)}")
print(f"Wrote {len(rows)} correlated rows to {args.output}")

if args.net_geometry_output:
    geometry_rows = []
    for net_name in args.net:
        net = block.findNet(net_name)
        if net is None:
            raise SystemExit(f"Net not found: {net_name}")
        wire = net.getWire()
        itr = odb.dbWirePathItr()
        path = odb.dbWirePath()
        shape = odb.dbWirePathShape()
        itr.begin(wire)
        while itr.getNextPath(path):
            while itr.getNextShape(shape):
                geom = shape.shape
                if not geom.isSegment():
                    continue
                box = geom.getBox()
                geometry_rows.append({
                    "net": net_name,
                    "layer": geom.getTechLayer().getName(),
                    "x_min_um": box.xMin() / dbu,
                    "y_min_um": box.yMin() / dbu,
                    "x_max_um": box.xMax() / dbu,
                    "y_max_um": box.yMax() / dbu,
                    "iterms": ";".join(sorted(
                        f"{term.getInst().getName()}/{term.getMTerm().getName()}"
                        for term in net.getITerms())),
                    "instances": ";".join(sorted(
                        f"{term.getInst().getName()}:{term.getInst().getMaster().getName()}@"
                        f"{term.getInst().getBBox().xMin()/dbu},"
                        f"{term.getInst().getBBox().yMin()/dbu}"
                        for term in net.getITerms())),
                })
    with open(args.net_geometry_output, "w", newline="", encoding="utf-8") as stream:
        fieldnames = list(geometry_rows[0]) if geometry_rows else ["net", "layer"]
        writer = csv.DictWriter(stream, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(geometry_rows)
    print(f"Wrote {len(geometry_rows)} routed segments to {args.net_geometry_output}")
