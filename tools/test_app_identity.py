"""Guard production/test identities and matching build behavior (macOS, stdlib only)."""

import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "TradingUp.xcodeproj"
VARIANTS = (
    ("TradingUp", "", "com.callmegreg.tradingup", "Trading Up"),
    ("TradingUpTest", "-Test", "com.callmegreg.tradingup.test", "Trading Up Test"),
)
TEST_APP_CONDITION = "TRADING_UP_TEST_APP"


class AppIdentityConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        result = subprocess.run(
            ["plutil", "-convert", "json", "-o", "-", str(PROJECT / "project.pbxproj")],
            check=True, capture_output=True, text=True,
        )
        cls.project = json.loads(result.stdout)
        cls.objects = cls.project["objects"]

    def configurations(self, target_name=None):
        owner = self.objects[self.project["rootObject"]] if target_name is None else next(
            obj for obj in self.objects.values()
            if obj["isa"] == "PBXNativeTarget" and obj["name"] == target_name
        )
        config_list = self.objects[owner["buildConfigurationList"]]
        return {
            self.objects[key]["name"]: self.objects[key]["buildSettings"]
            for key in config_list["buildConfigurations"]
        }

    def test_app_identities_and_version_pairs(self):
        configs = self.configurations("TradingUp")
        for scheme, suffix, bundle_id, display_name in VARIANTS:
            with self.subTest(scheme=scheme):
                debug, release = (configs[f"{mode}{suffix}"] for mode in ("Debug", "Release"))
                for settings in (debug, release):
                    self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], bundle_id)
                    self.assertEqual(settings["INFOPLIST_KEY_CFBundleDisplayName"], display_name)
                    self.assertEqual(settings["CODE_SIGN_STYLE"], "Automatic")
                    self.assertEqual(settings["PRODUCT_NAME"], "$(TARGET_NAME)")
                    self.assertEqual(settings["GENERATE_INFOPLIST_FILE"], "YES")
                    self.assertEqual(settings["INFOPLIST_KEY_ITSAppUsesNonExemptEncryption"], "NO")
                    self.assertGreater(int(settings["CURRENT_PROJECT_VERSION"]), 0)
                for key in ("CURRENT_PROJECT_VERSION", "MARKETING_VERSION"):
                    self.assertEqual(debug[key], release[key], f"{scheme}: {key}")

    def test_test_app_keeps_production_build_behavior(self):
        identity_keys = {
            "PRODUCT_BUNDLE_IDENTIFIER", "INFOPLIST_KEY_CFBundleDisplayName",
        }
        for target in (None, "TradingUp", "TradingUpTests", "TradingUpUITests"):
            configs = self.configurations(target)
            self.assertEqual(set(configs), {"Debug", "Release", "Debug-Test", "Release-Test"})
            for mode in ("Debug", "Release"):
                with self.subTest(target=target, mode=mode):
                    production, test = (configs[name] for name in (mode, f"{mode}-Test"))
                    if target == "TradingUp":
                        test = dict(test)
                        self.assertEqual(test.pop("SWIFT_ACTIVE_COMPILATION_CONDITIONS"),
                                         f"$(inherited) {TEST_APP_CONDITION}")
                    self.assertEqual(
                        {key: value for key, value in production.items() if key not in identity_keys},
                        {key: value for key, value in test.items() if key not in identity_keys},
                    )

    def test_production_and_test_share_one_version_and_build_number(self):
        configs = self.configurations("TradingUp")
        for key in ("CURRENT_PROJECT_VERSION", "MARKETING_VERSION"):
            with self.subTest(setting=key):
                values = {name: settings[key] for name, settings in configs.items()}
                self.assertEqual(len(set(values.values())), 1,
                                 f"All app configurations must share {key}: {values}")

    def test_automatic_unlock_condition_is_exclusive_to_test_app_configurations(self):
        for target in (None, "TradingUp", "TradingUpTests", "TradingUpUITests"):
            for name, settings in self.configurations(target).items():
                with self.subTest(target=target, configuration=name):
                    conditions = settings.get("SWIFT_ACTIVE_COMPILATION_CONDITIONS", "").split()
                    expected = target == "TradingUp" and name in {"Debug-Test", "Release-Test"}
                    self.assertEqual(TEST_APP_CONDITION in conditions, expected)
                    self.assertNotIn(
                        TEST_APP_CONDITION,
                        str({key: value for key, value in settings.items()
                             if key != "SWIFT_ACTIVE_COMPILATION_CONDITIONS"}),
                        "The unlock condition must not be injected through another build setting.",
                    )

    def test_compiled_unlock_policy_requires_both_test_condition_and_exact_identity(self):
        with tempfile.TemporaryDirectory(prefix="tu_test_build_access_") as directory:
            main = Path(directory) / "main.swift"
            executable = Path(directory) / "test_build_access"
            main.write_text("""
let expected = CommandLine.arguments[1] == "true"
precondition(TestBuildAccess.allowsAutomaticUnlock(
    bundleIdentifier: "com.callmegreg.tradingup.test") == expected)
let rejectedIDs: [String?] = [
    nil, "", "com.callmegreg.tradingup", "com.callmegreg.tradingup.tests",
    "com.callmegreg.tradingup.test.tests", "com.callmegreg.tradingup.test.extra",
    "com.callmegreg.tradingup.Test", "another.app.test",
]
for bundleID in rejectedIDs {
    precondition(!TestBuildAccess.allowsAutomaticUnlock(bundleIdentifier: bundleID),
                 "Unexpected automatic unlock for \\(bundleID ?? "nil")")
}
""")
            for debug in (False, True):
                for test_app in (False, True):
                    with self.subTest(debug=debug, test_app=test_app):
                        flags = ["-Onone" if debug else "-O"]
                        if debug:
                            flags += ["-D", "DEBUG"]
                        if test_app:
                            flags += ["-D", TEST_APP_CONDITION]
                        compiled = subprocess.run(
                            ["xcrun", "swiftc", *flags,
                             str(ROOT / "TradingUp/Store/TestBuildAccess.swift"), str(main),
                             "-o", str(executable)],
                            capture_output=True, text=True,
                        )
                        self.assertEqual(compiled.returncode, 0, compiled.stderr)
                        result = subprocess.run(
                            [str(executable), "true" if test_app else "false"],
                            capture_output=True, text=True,
                        )
                        self.assertEqual(result.returncode, 0, result.stderr)

    def test_test_bundles_and_hosts_follow_the_app(self):
        for target, ending in (("TradingUpTests", "tests"), ("TradingUpUITests", "uitests")):
            configs = self.configurations(target)
            for scheme, suffix, bundle_id, _ in VARIANTS:
                for mode in ("Debug", "Release"):
                    with self.subTest(target=target, scheme=scheme, mode=mode):
                        settings = configs[f"{mode}{suffix}"]
                        self.assertEqual(settings["PRODUCT_BUNDLE_IDENTIFIER"], f"{bundle_id}.{ending}")
                        if ending == "tests":
                            self.assertEqual(settings["TEST_HOST"],
                                             "$(BUILT_PRODUCTS_DIR)/TradingUp.app/TradingUp")
                        else:
                            self.assertEqual(settings["TEST_TARGET_NAME"], "TradingUp")

    def test_schemes_never_switch_environment_between_actions(self):
        modes = {
            "LaunchAction": "Debug", "TestAction": "Debug", "AnalyzeAction": "Debug",
            "ProfileAction": "Release", "ArchiveAction": "Release",
        }
        for scheme, suffix, _, _ in VARIANTS:
            root = ET.parse(PROJECT / "xcshareddata/xcschemes" / f"{scheme}.xcscheme").getroot()
            for action, mode in modes.items():
                with self.subTest(scheme=scheme, action=action):
                    self.assertEqual(root.find(action).get("buildConfiguration"), f"{mode}{suffix}")
            app_entry = next(
                entry for entry in root.findall("BuildAction/BuildActionEntries/BuildActionEntry")
                if entry.find("BuildableReference").get("BlueprintName") == "TradingUp"
            )
            self.assertEqual(app_entry.get("buildForArchiving"), "YES")
            if suffix:
                storekit = root.find("LaunchAction/StoreKitConfigurationFileReference")
                self.assertEqual(storekit.get("identifier"), "../../TradingUp/TradingUpTest.storekit")
                self.assertEqual(
                    (PROJECT / "xcshareddata" / storekit.get("identifier")).resolve(),
                    ROOT / "TradingUp/TradingUpTest.storekit",
                )

    def test_screenshot_scheme_stays_production(self):
        root = ET.parse(PROJECT / "xcshareddata/xcschemes/TradingUpScreenshots.xcscheme").getroot()
        for action in ("LaunchAction", "TestAction", "AnalyzeAction"):
            self.assertEqual(root.find(action).get("buildConfiguration"), "Debug")
        for entry in root.findall("BuildAction/BuildActionEntries/BuildActionEntry"):
            self.assertEqual(entry.get("buildForArchiving"), "NO")

    def test_storekit_catalogs_use_separate_equivalent_products(self):
        products = []
        for scheme, _, bundle_id, _ in VARIANTS:
            catalog = json.loads((ROOT / "TradingUp" / f"{scheme}.storekit").read_text())
            self.assertEqual(len(catalog["products"]), 1)
            product = catalog["products"][0]
            self.assertEqual(product["productID"], f"{bundle_id}.fullunlock")
            self.assertEqual(product["type"], "NonConsumable")
            products.append({key: value for key, value in product.items()
                             if key not in {"productID", "internalID"}})
            if scheme == "TradingUpTest":
                self.assertEqual(catalog["settings"]["_applicationInternalID"], "")
        self.assertEqual(products[0], products[1])


if __name__ == "__main__":
    unittest.main()
