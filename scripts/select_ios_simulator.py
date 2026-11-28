#!/usr/bin/env python3
"""Select a standard iPhone on the requested SDK runtime, never a newer variant."""
import argparse
import json
import re
import sys


def select_simulator(inventory, sdk_version):
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", sdk_version):
        raise ValueError("Invalid iOS SDK version")
    sdk = tuple(map(int, sdk_version.split(".")))
    if sdk < (18, 0):
        raise ValueError("PhotoP requires iOS >=18")
    choices = []
    for key, devices in inventory.get("devices", {}).items():
        match = re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-(\d+(?:-\d+)*)", key)
        if not match:
            continue
        version = tuple(map(int, match.group(1).split("-")))
        # Four-component engineering runtimes (e.g. 27.2.19.4) must not outrank
        # the normal 27.2 SDK runtime. A patch runtime is an explicit fallback.
        if version[:2] != sdk[:2] or len(version) not in (2, 3):
            continue
        for device in devices:
            name = device.get("name", "")
            if not device.get("isAvailable", True) or not re.match(r"^iPhone \d+(?:\s|$)", name):
                continue
            udid = device.get("udid")
            if not isinstance(udid, str) or not re.fullmatch(r"[0-9a-fA-F-]{36}", udid):
                continue
            regular_pro = bool(re.fullmatch(r"iPhone \d+ Pro", name))
            generation = int(re.search(r"\d+", name).group())
            score = (version == sdk, len(version) == 2, version, regular_pro, generation, name, udid)
            choices.append((score, version, udid, name))
    if not choices:
        raise ValueError(f"No available standard iPhone Simulator matching iOS SDK {sdk_version}")
    _, version, udid, name = max(choices)
    return ".".join(map(str, version)), udid, name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-version", required=True)
    args = parser.parse_args()
    try:
        version, udid, name = select_simulator(json.load(sys.stdin), args.sdk_version)
    except (ValueError, TypeError, KeyError) as error:
        parser.error(str(error))
    print(f"Selected {name} on iOS {version}", file=sys.stderr)
    print(version, udid)


if __name__ == "__main__":
    main()
