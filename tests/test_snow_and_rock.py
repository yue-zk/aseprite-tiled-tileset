"""Keep the checked-in snow/rock example in sync with its shared manifest."""

import shutil
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

from examples.snow_and_rock.build import MANIFEST, build, load_manifest
from scripts.tiled.wang import read_assignments

ASSETS = Path(__file__).resolve().parents[1] / "assets" / "snow-and-rock"


class SnowRockExampleTests(unittest.TestCase):
    def test_build_reproduces_the_shipped_tiled_files(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            shutil.copyfile(ASSETS / "tiles.png", output / "tiles.png")
            build(output, MANIFEST)
            for name in ("tiles.tsx", "showcase.tmx"):
                self.assertEqual((output / name).read_bytes(), (ASSETS / name).read_bytes())
            with self.assertRaises(FileExistsError):
                build(output, MANIFEST)

    def test_shipped_layout_exercises_same_layer_junction(self):
        width, height, columns, declared = load_manifest(MANIFEST)
        self.assertEqual(len(declared), 80)
        root = ET.parse(ASSETS / "tiles.tsx").getroot()
        self.assertEqual(read_assignments(root.find("wangsets/wangset")), declared)
        self.assertEqual(tuple(map(int, (root.get("tilewidth"), root.get("tileheight"), root.get("columns")))),
                         (width, height, columns))
        self.assertEqual(root.find("image").get("source"), "tiles.png")
        showcase = ET.parse(ASSETS / "showcase.tmx").getroot()
        self.assertEqual(showcase.find("tileset").get("source"), "tiles.tsx")
        painted, practice = (
            list(map(int, layer.find("data").text.split(","))) for layer in showcase.findall("layer")
        )
        self.assertEqual(len(painted), int(showcase.get("width")) * int(showcase.get("height")))
        self.assertEqual(practice, [0] * len(painted))
        self.assertTrue(any(gid and set(declared[gid - 1][1::2]) == {0, 1, 2} for gid in painted))
