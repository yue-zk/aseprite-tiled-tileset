"""Behavior tests for the reusable Python Wang helpers."""

import unittest
from itertools import islice
from pathlib import Path
from xml.etree import ElementTree as ET

from scripts.tiled.wang import (
    SLOTS,
    compare_coverage,
    format_wangid,
    full_signatures,
    pack_slots,
    parse_wangid,
    patch_assignments,
    read_assignments,
    slot_names,
    unpack_slots,
)


def corner(tr=0, br=0, bl=0, tl=0):
    return (0, tr, 0, br, 0, bl, 0, tl)


ATLAS = """<tileset version="1.10" tilecount="4" columns="2">
  <properties><property name="project-note" value="keep" /></properties>
  <image source="art/source.png" width="32" height="32" />
  <tile id="0"><properties><property name="note" value="preserve" /></properties>
    <animation><frame tileid="1" duration="120" /></animation>
  </tile>
  <wangsets>
    <wangset name="Surface" type="corner" tile="0"><!-- untouched -->
      <wangcolor name="A" color="#11aa22" tile="0" probability="0.5" />
      <wangcolor name="B" color="#2233bb" tile="1" probability="1" />
      <wangtile tileid="0" wangid="0,1,0,1,0,1,0,1" custom="preserve" />
      <wangtile tileid="1" wangid="0,1,0,1,0,0,0,0" />
    </wangset>
    <wangset name="Road" type="edge" tile="2">
      <wangcolor name="A" color="#eeeeee" tile="2" probability="1" />
      <wangtile tileid="2" wangid="1,0,1,0,0,0,0,0" />
    </wangset>
  </wangsets>
</tileset>"""


def parse_xml(data):
    parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True, insert_pis=True))
    return ET.fromstring(data, parser=parser)


class SlotCodecTests(unittest.TestCase):
    def test_asymmetric_slot_order(self):
        signatures = {
            "corner": (0, 1, 0, 2, 0, 3, 0, 4),
            "edge": (1, 0, 2, 0, 3, 0, 4, 0),
            "mixed": (1, 2, 3, 4, 5, 6, 7, 8),
        }
        for kind, raw in signatures.items():
            with self.subTest(kind=kind):
                names = tuple(name for name, value in zip(SLOTS, raw) if value)
                self.assertEqual(slot_names(kind), names)
                named = dict(zip(names, range(1, len(names) + 1)))
                self.assertEqual(pack_slots(kind, named), raw)
                self.assertEqual(unpack_slots(kind, raw), named)
                text = ",".join(map(str, raw))
                self.assertEqual(format_wangid(kind, raw), text)
                self.assertEqual(parse_wangid(kind, text.replace(",", ", ")), raw)

    def test_rejects_wrong_slot_names_lengths_values_and_types(self):
        for fn, args in (
            (slot_names, ("paint",)),
            (pack_slots, ("corner", {"top_left": 1, "bottomleft": 0})),
            (parse_wangid, ("corner", "1,0,0,0,0,0,0,0")),
            (parse_wangid, ("mixed", "0,0,0,0,0,0,0")),
            (parse_wangid, ("mixed", "0,0,0,0,0,0,-1,0")),
            (parse_wangid, ("mixed", "0,0,0,0,0,0,no,0")),
            (format_wangid, ("corner", corner(256))),
            (format_wangid, ("corner", corner(True))),
            (format_wangid, ("corner", corner(1.0))),
        ):
            with self.subTest(fn=fn.__name__, args=args), self.assertRaises(ValueError):
                fn(*args)

    def test_empty_slots_round_trip_but_do_not_belong_to_a_tile(self):
        self.assertEqual(format_wangid("edge", (0,) * 8), "0,0,0,0,0,0,0,0")
        with self.assertRaisesRegex(ValueError, "all-zero"):
            compare_coverage("edge", [], {0: (0,) * 8})
        with self.assertRaisesRegex(ValueError, "unknown"):
            compare_coverage("invalid", [], {})


class CoverageTests(unittest.TestCase):
    def test_limited_requirements_distinguish_missing_extras_and_variants(self):
        pure, join, unrelated = corner(1, 1, 1, 1), corner(1, 1), corner(2, 2, 2, 2)
        actual = {12: pure, 3: unrelated, 8: pure}
        results = compare_coverage("corner", [pure, join], actual)
        self.assertEqual(results.missing, (join,))
        self.assertEqual(results.extra, (unrelated,))
        self.assertEqual(results.variants, ((pure, (8, 12)),))

    def test_full_product_is_explicit_and_lazy(self):
        self.assertEqual(len(list(full_signatures("corner", [0, 1, 2, 3]))), 255)
        self.assertEqual(len(list(full_signatures("edge", [1, 2, 2]))), 16)
        self.assertEqual(len(list(full_signatures("mixed", [0, 1]))), 255)
        self.assertTrue(all(any(signature) for signature in full_signatures("mixed", [0, 1])))
        self.assertEqual(next(islice(full_signatures("mixed", range(100)), 1)), (0, 0, 0, 0, 0, 0, 0, 1))
        with self.assertRaisesRegex(ValueError, "at least one"):
            list(full_signatures("corner", []))

    def test_public_sample_has_255_unique_nonempty_slots(self):
        root = Path(__file__).resolve().parents[1]
        tsx = ET.parse(root / "assets" / "grass-and-dirt" / "tiles.tsx").getroot()
        wangset = tsx.find("wangsets/wangset")
        self.assertIsNotNone(wangset)
        actual = read_assignments(wangset)
        self.assertEqual(len(actual), 255)
        report = compare_coverage("corner", full_signatures("corner", [0, 1, 2, 3]), actual)
        self.assertEqual((report.missing, report.extra, report.variants), ((), (), ()))


class PatchTests(unittest.TestCase):
    def setUp(self):
        self.tileset = parse_xml(ATLAS)

    def test_patch_keeps_input_and_other_nodes(self):
        before = ET.tostring(self.tileset)
        replacement, addition = corner(2, 1), corner(1, 0, 2, 0)
        edited = patch_assignments(self.tileset, "Surface", {3: addition, 0: replacement, 1: None})
        self.assertEqual(ET.tostring(self.tileset), before)
        surface, road = edited.findall("wangsets/wangset")
        old_surface, old_road = self.tileset.findall("wangsets/wangset")
        self.assertEqual(read_assignments(surface), {0: replacement, 3: addition})
        self.assertEqual(surface.attrib, old_surface.attrib)
        self.assertEqual(surface.find("wangtile").get("custom"), "preserve")
        self.assertIs(surface[0].tag, ET.Comment)
        for path in ("tile", "image", "properties"):
            self.assertEqual(ET.tostring(edited.find(path)), ET.tostring(self.tileset.find(path)))
        self.assertEqual(ET.tostring(road), ET.tostring(old_road))
        self.assertEqual([ET.tostring(n) for n in surface.findall("wangcolor")],
                         [ET.tostring(n) for n in old_surface.findall("wangcolor")])

    def test_invalid_edits_leave_the_original_unchanged(self):
        before = ET.tostring(self.tileset)
        for set_name, patch, error in (
            ("missing", {0: corner(1)}, "exactly one"),
            ("Surface", {4: corner(1)}, "does not exist"),
            ("Surface", {3: corner(1), 0: corner(3)}, "has 2 colors"),
            ("Surface", {0: (0,) * 8}, "all-zero"),
            ("Surface", {2: None}, "cannot remove"),
            ("Surface", {False: corner(1)}, "tile id"),
        ):
            with self.subTest(patch=patch), self.assertRaisesRegex(ValueError, error):
                patch_assignments(self.tileset, set_name, patch)
            self.assertEqual(ET.tostring(self.tileset), before)

    def test_sparse_collection_uses_local_ids_not_tilecount(self):
        self.tileset.remove(self.tileset.find("image"))
        self.tileset.set("columns", "0")
        self.tileset.set("tilecount", "3")
        ET.SubElement(self.tileset, "tile", id="1")
        ET.SubElement(self.tileset, "tile", id="19")
        edited = patch_assignments(self.tileset, "Surface", {19: corner(1, 2)})
        self.assertIn(19, read_assignments(edited.find("wangsets/wangset")))
        with self.assertRaisesRegex(ValueError, "does not exist"):
            patch_assignments(self.tileset, "Surface", {2: corner(1)})

    def test_duplicate_local_id_is_conflict_but_duplicate_signature_is_not(self):
        edited = patch_assignments(self.tileset, "Surface", {3: corner(1, 1, 1, 1)})
        surface = edited.find("wangsets/wangset")
        self.assertEqual(read_assignments(surface)[0], read_assignments(surface)[3])
        ET.SubElement(surface, "wangtile", tileid="3", wangid="0,1,0,1,0,1,0,1")
        with self.assertRaisesRegex(ValueError, "assigned more than once"):
            read_assignments(surface)

    def test_ambiguous_set_name_is_rejected(self):
        self.tileset.findall("wangsets/wangset")[1].set("name", "Surface")
        with self.assertRaisesRegex(ValueError, "found 2"):
            patch_assignments(self.tileset, "Surface", {0: corner(1)})


if __name__ == "__main__":
    unittest.main()
