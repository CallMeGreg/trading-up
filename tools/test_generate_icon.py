import base64
import math
import unittest
import xml.etree.ElementTree as ET

import generate_icon

SVG = "{http://www.w3.org/2000/svg}"


class IconCompositionTests(unittest.TestCase):
    def setUp(self):
        self.emblems = [f"set-{i}".encode("ascii") for i in range(1, 6)]
        self.svg = ET.fromstring(generate_icon.icon_svg(self.emblems))

    def test_full_bleed_square_without_wordmark(self):
        self.assertEqual(self.svg.attrib["width"], "1024")
        self.assertEqual(self.svg.attrib["height"], "1024")
        self.assertEqual(self.svg.attrib["viewBox"], "0 0 256 256")
        backdrop = self.svg.find(f"{SVG}rect")
        self.assertEqual(backdrop.attrib["width"], "256")
        self.assertEqual(backdrop.attrib["height"], "256")
        self.assertNotIn("rx", backdrop.attrib)
        self.assertNotIn("ry", backdrop.attrib)
        self.assertEqual(self.svg.findall(f".//{SVG}text"), [])

    def test_five_worlds_are_in_order_on_the_orbit(self):
        images = self.svg.findall(f".//{SVG}image")
        self.assertEqual(len(images), 5)
        for i, (image, emblem) in enumerate(zip(images, self.emblems)):
            with self.subTest(set=i+1):
                data = image.attrib["href"].removeprefix("data:image/png;base64,")
                self.assertEqual(base64.b64decode(data), emblem)
                width = float(image.attrib["width"])
                height = float(image.attrib["height"])
                self.assertEqual(width, 66)
                self.assertEqual(height, 66)
                x = float(image.attrib["x"]) + width / 2
                y = float(image.attrib["y"]) + height / 2
                angle = math.radians(-90 + i * 72)
                self.assertAlmostEqual(x, 128 + math.cos(angle) * 72)
                self.assertAlmostEqual(y, 128 + math.sin(angle) * 72)
                self.assertGreater(x - width / 2, 0)
                self.assertGreater(y - height / 2, 0)
                self.assertLess(x + width / 2, 256)
                self.assertLess(y + height / 2, 256)

    def test_all_worlds_are_required(self):
        for count in (0, 4, 6):
            with self.subTest(count=count):
                with self.assertRaisesRegex(ValueError, "exactly five"):
                    generate_icon.icon_svg([b"set"] * count)

    def test_website_uses_the_same_generated_icon(self):
        app_icon = generate_icon.ROOT / "TradingUp/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
        self.assertEqual(app_icon.read_bytes(), (generate_icon.ROOT / "site/icon.png").read_bytes())


if __name__ == "__main__":
    unittest.main()
