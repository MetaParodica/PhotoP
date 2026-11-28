import unittest
from select_ios_simulator import select_simulator


def phone(name, number=1, available=True):
    return {"name": name, "udid": f"00000000-0000-0000-0000-{number:012d}", "isAvailable": available}


def runtime(version):
    return "com.apple.CoreSimulator.SimRuntime.iOS-" + version


class SimulatorSelectionTests(unittest.TestCase):
    def test_standard_sdk_pro_wins_over_duo_engineering_runtime(self):
        data = {"devices": {
            runtime("27-2"): [phone("iPhone 18 Pro", 1), phone("iPhone 18 Pro Max", 2)],
            runtime("27-2-19-4"): [phone("iPhone Duo", 99)],
        }}
        version, udid, name = select_simulator(data, "27.2")
        self.assertEqual((version, name), ("27.2", "iPhone 18 Pro"))
        self.assertTrue(udid.endswith("000000000001"))

    def test_matches_requested_sdk_not_highest_installed_version(self):
        data = {"devices": {runtime("26-2"): [phone("iPhone 17 Pro")], runtime("27-2"): [phone("iPhone 18 Pro", 2)]}}
        self.assertEqual(select_simulator(data, "26.2")[0], "26.2")

    def test_exact_runtime_preferred_before_patch_fallback(self):
        data = {"devices": {runtime("27-2"): [phone("iPhone 17")], runtime("27-2-1"): [phone("iPhone 18 Pro", 2)]}}
        self.assertEqual(select_simulator(data, "27.2")[0], "27.2")

    def test_patch_runtime_allowed_if_no_exact_runtime(self):
        data = {"devices": {runtime("27-2-1"): [phone("iPhone 18 Pro")]}}
        self.assertEqual(select_simulator(data, "27.2")[0], "27.2.1")

    def test_unavailable_and_non_iphone_devices_are_not_selected(self):
        data = {"devices": {runtime("27-2"): [phone("iPhone 18 Pro", available=False), phone("iPad Pro", 2)]}}
        with self.assertRaises(ValueError):
            select_simulator(data, "27.2")

    def test_engineering_only_does_not_silently_validate_different_device(self):
        with self.assertRaises(ValueError):
            select_simulator({"devices": {runtime("27-2-19-4"): [phone("iPhone Duo")]}}, "27.2")

    def test_minimum_version_and_invalid_sdk_are_rejected(self):
        for version in ("17.6", "27", "27.2;command"):
            with self.assertRaises(ValueError):
                select_simulator({"devices": {}}, version)


if __name__ == "__main__":
    unittest.main()
