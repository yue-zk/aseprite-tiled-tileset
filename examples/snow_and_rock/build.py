"""Build the example TSX and TMX from the same tile manifest that draw.lua uses."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path
from xml.etree import ElementTree as ET

from scripts.tiled.wang import compare_coverage, full_signatures, pack_slots, patch_assignments, read_assignments

CORNERS = ("top_left", "top_right", "bottom_right", "bottom_left")
SET_NAME = "雪地与岩地 · 同层接空白"
MANIFEST = Path(__file__).with_name("tiles.tsv")


def load_manifest(path: Path):
    grid, header, *rows = path.read_text(encoding="ascii").splitlines()
    marker, w, h, cols = grid.split("\t")
    width, height, columns = map(int, (w, h, cols))
    if marker != "grid" or min(width, height) < 2 or columns < 1:
        raise ValueError("invalid grid header")
    if header.split("\t") != ["id", *CORNERS]:
        raise ValueError("unexpected manifest columns")
    assignments = {}
    for index, line in enumerate(rows):
        tile_id, *corners = map(int, line.split("\t"))
        if tile_id != index or len(corners) != len(CORNERS) or not set(corners) <= {0, 1, 2}:
            raise ValueError(f"invalid tile row {index}: {line}")
        assignments[tile_id] = pack_slots("corner", dict(zip(CORNERS, corners)))
    report = compare_coverage("corner", full_signatures("corner", (0, 1, 2)), assignments)
    if report.missing or report.extra or report.variants:
        raise ValueError(f"expected unique full snow/rock coverage: {report}")
    return width, height, columns, assignments


def demo_rows():
    # Vertices, not tile IDs. Adjacent tiles therefore share their corner values.
    # Left: a rock cut through a snowfield. Right: a rock island with a snow bank.
    left = (
        "...............", ".....sss.......", "...ssssss......", "..sssssssss....",
        ".ssssrsssss....", ".sssrrrrssss...", ".sssrrrrrssss..", ".ssrrrrrrsssss.",
        ".ssrrrrrrrssss.", "..ssrrrrrsss...", "..ssrrrsssss...", "....rrssss.....",
        ".....rrss......", ".....r.........", "...............",
    )
    right = (
        "...............", "......rrr......", "....rrrrrr.....", "...rrrrrrrr....",
        "...rrrrsssrr...", "..rrrssssrrr...", "..rrss.srrr....", "..rrss..srr....",
        "...rrsssssrr...", "...rrrrssrrr...", "....rrrsrrr....", ".....rrrrr.....",
        ".......r.......", "...............", "...............",
    )
    key = {".": 0, "s": 1, "r": 2}
    return [[key[cell] for cell in a + "..." + b] for a, b in zip(left, right, strict=True)]


def save(tree, path: Path):
    ET.indent(tree, space="  ")
    with path.open("xb") as stream:
        ET.ElementTree(tree).write(stream, encoding="utf-8", xml_declaration=True)


def build(output: Path, manifest: Path):
    width, height, columns, assignments = load_manifest(manifest)
    image_width = width * columns
    count = ((len(assignments) + columns - 1) // columns) * columns
    image_height = height * (count // columns)
    with (output / "tiles.png").open("rb") as stream:
        header = stream.read(24)
    if (header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR"
            or len(header) != 24 or struct.unpack(">II", header[16:24]) != (image_width, image_height)):
        raise ValueError("PNG does not match the manifest grid; run draw.lua first")
    if any((output / name).exists() for name in ("tiles.tsx", "showcase.tmx")):
        raise FileExistsError("use a fresh output directory; no existing TSX or TMX is overwritten")

    by_signature = {signature: tile_id for tile_id, signature in assignments.items()}
    tileset = ET.Element("tileset", version="1.10", name="雪地与岩地", tilewidth=str(width),
                         tileheight=str(height), tilecount=str(count), columns=str(columns))
    ET.SubElement(tileset, "image", source="tiles.png", width=str(image_width), height=str(image_height))
    sets = ET.SubElement(tileset, "wangsets")
    wang = ET.SubElement(sets, "wangset", name=SET_NAME, type="corner", tile="-1")
    for value, name, color in ((1, "雪地", "#dbEEF0"), (2, "岩地", "#526777")):
        uniform = pack_slots("corner", dict.fromkeys(CORNERS, value))
        ET.SubElement(wang, "wangcolor", name=name, color=color, tile=str(by_signature[uniform]), probability="1")
    tileset = patch_assignments(tileset, SET_NAME, assignments)
    if read_assignments(tileset.find("wangsets/wangset")) != assignments:
        raise ValueError("TSX annotations differ from manifest")

    vertices = demo_rows()
    cols, rows = len(vertices[0]) - 1, len(vertices) - 1
    if any(len(row) != cols + 1 for row in vertices):
        raise ValueError("ragged showcase layout")
    map_root = ET.Element("map", version="1.10", orientation="orthogonal", renderorder="right-down",
                          width=str(cols), height=str(rows), tilewidth=str(width), tileheight=str(height),
                          infinite="0", nextlayerid="3", nextobjectid="1", backgroundcolor="#293847")
    ET.SubElement(map_root, "tileset", firstgid="1", source="tiles.tsx")
    cells = []
    for y in range(rows):
        row = []
        for x in range(cols):
            corners = (vertices[y][x], vertices[y][x + 1], vertices[y + 1][x + 1], vertices[y + 1][x])
            signature = pack_slots("corner", dict(zip(CORNERS, corners)))
            row.append(by_signature[signature] + 1 if any(corners) else 0)
        cells.append(row)
    for layer_id, name, data in ((1, "雪岸与岩屿 · 摆放示例", cells), (2, "空白练习层", [[0] * cols] * rows)):
        layer = ET.SubElement(map_root, "layer", id=str(layer_id), name=name, width=str(cols), height=str(rows))
        ET.SubElement(layer, "data", encoding="csv").text = "\n" + ",\n".join(",".join(map(str, r)) for r in data) + "\n"
    save(tileset, output / "tiles.tsx")
    save(map_root, output / "showcase.tmx")
    print(f"Wrote TSX and TMX with {len(assignments)} declared Wang signatures")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    args = parser.parse_args()
    build(args.output, args.manifest)


if __name__ == "__main__":
    main()
