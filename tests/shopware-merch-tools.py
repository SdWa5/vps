"""Unit tests for the Python behind tools/shopware/images/ and tools/shopware/print-cost/.

Run by tests/run.sh in python:3.12-slim with numpy and Pillow, the versions the
shop-images image carries. rembg and OrcaSlicer are not needed.
"""
import importlib.util
import json
import pathlib
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent / "tools" / "shopware"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


shopimg = load(ROOT / "images" / "shopimg.py", "shopimg")
flatten = load(ROOT / "print-cost" / "flatten.py", "flatten")


def apply(coeffs, x, y):
    d = coeffs[6] * x + coeffs[7] * y + 1
    return (coeffs[0] * x + coeffs[1] * y + coeffs[2]) / d, (coeffs[3] * x + coeffs[4] * y + coeffs[5]) / d


class Geometry(unittest.TestCase):
    def test_box_scales_fractions_to_pixels(self):
        self.assertEqual(shopimg.box("0.1,0.25,0.5,1", 200, 400), (20, 100, 100, 400))

    def test_homography_maps_each_point_onto_its_partner(self):
        quad = [(10, 12), (90, 8), (95, 70), (5, 80)]
        rect = [(0, 0), (100, 0), (100, 75), (0, 75)]
        coeffs = shopimg.homography(rect, quad)  # quad -> rect
        for (qx, qy), (rx, ry) in zip(quad, rect):
            x, y = apply(coeffs, qx, qy)
            self.assertAlmostEqual(x, rx, places=6)
            self.assertAlmostEqual(y, ry, places=6)

    def test_upright_squares_a_keystoned_face(self):
        # A trapezoid narrower at the bottom, as a phone held above the subject
        # draws a rectangle. After the warp its edges have to be vertical.
        cut = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
        quad = [(40, 20), (160, 20), (140, 180), (60, 180)]
        ImageDraw.Draw(cut).polygon(quad, fill=(255, 255, 255, 255))
        spec = " ".join(f"{x / 200},{y / 200}" for x, y in quad)
        out = np.asarray(shopimg.upright(cut, spec, (0, 0), (200, 200)).getchannel("A")) > 128
        rows = [r for r in range(out.shape[0]) if out[r].any()]
        top, bottom = rows[len(rows) // 5], rows[-len(rows) // 5]
        left = [np.nonzero(out[r])[0][0] for r in (top, bottom)]
        right = [np.nonzero(out[r])[0][-1] for r in (top, bottom)]
        self.assertLessEqual(abs(left[0] - left[1]), 2)
        self.assertLessEqual(abs(right[0] - right[1]), 2)

    def test_patch_changes_only_the_polygon_and_takes_its_surroundings(self):
        img = Image.new("RGB", (100, 100), (50, 50, 50))
        ImageDraw.Draw(img).rectangle((40, 40, 60, 60), fill=(255, 0, 0))
        out = np.asarray(shopimg.patch(img, "0.38,0.38 0.62,0.38 0.62,0.62 0.38,0.62")).astype(int)
        self.assertTrue((out[:30] == 50).all())
        self.assertLess(abs(out[50, 50] - 50).max(), 15)

    def test_neutral_makes_the_subject_average_grey(self):
        img = Image.new("RGB", (10, 10), (80, 100, 140))
        mask = Image.new("L", (10, 10), 255)
        mean = np.asarray(shopimg.neutral(img, mask)).reshape(-1, 3).mean(axis=0)
        self.assertLess(mean.max() - mean.min(), 1.5)


class Flatten(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        root = pathlib.Path(self.dir.name)
        for kind, presets in {
            "machine": [{"name": "base", "nozzle": 0.4, "bed": 200}, {"name": "Printer", "inherits": "base", "bed": 420}],
            "process": [{"name": "fdm", "layer": 0.2, "infill": "15%"}, {"name": "Std", "inherits": "fdm", "layer": 0.2}],
        }.items():
            (root / "Vendor" / kind).mkdir(parents=True)
            for p in presets:
                (root / "Vendor" / kind / f"{p['name']}.json").write_text(json.dumps(p))
        self.root = root

    def tearDown(self):
        self.dir.cleanup()

    def test_a_child_overrides_and_keeps_everything_it_inherits(self):
        flat = flatten.flatten(flatten.index(self.root, "machine"), "machine", "Printer")
        self.assertEqual((flat["bed"], flat["nozzle"]), (420, 0.4))

    def test_a_machine_becomes_a_user_preset_on_top_of_the_system_one(self):
        flat = flatten.flatten(flatten.index(self.root, "machine"), "machine", "Printer")
        self.assertEqual((flat["name"], flat["inherits"], flat["from"]), (flatten.USER_MACHINE, "Printer", "User"))

    def test_a_process_is_compatible_with_both_machine_names(self):
        flat = flatten.flatten(flatten.index(self.root, "process"), "process", "Std", "Printer")
        self.assertEqual(flat["compatible_printers"], ["Printer", flatten.USER_MACHINE])
        self.assertEqual(flat["infill"], "15%")
        self.assertNotIn("inherits", flat)


if __name__ == "__main__":
    sys.exit(unittest.main())
