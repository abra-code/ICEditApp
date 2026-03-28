#!/usr/bin/env python3

import os
import shutil
import subprocess
from typing import Any, Dict, List, Optional

from icon_editor.core import IconEditor


def find_icon_composer():
    """Find Icon Composer.app in common locations."""
    search_paths = [
        "/Applications/Icon Composer.app",
        "/Applications/Xcode.app/Contents/Applications/Icon Composer.app",
    ]
    try:
        r = subprocess.run(["xcode-select", "-p"], capture_output=True, text=True)
        if r.returncode == 0:
            dev_path = r.stdout.strip()
            if dev_path.endswith("/Developer"):
                xcode_contents = dev_path[: -len("/Developer")]
                search_paths.append(
                    os.path.join(xcode_contents, "Applications/Icon Composer.app")
                )
    except (OSError, FileNotFoundError):
        pass
    for path in search_paths:
        ictool = os.path.join(path, "Contents/Executables/ictool")
        if os.path.isfile(ictool):
            return ictool
    return None


ICTOOL_PATH = find_icon_composer()


def validate_icon(icon_path: str, output_dir: Optional[str] = None) -> Dict[str, Any]:
    """Validate icon by exporting PNGs with ictool. Returns validation results."""
    if not ICTOOL_PATH or not os.path.exists(ICTOOL_PATH):
        return {"valid": False, "error": "Icon Composer not installed", "exports": []}

    if output_dir is None:
        output_dir = "/tmp"
    os.makedirs(output_dir, exist_ok=True)

    platforms = ["macOS", "iOS"]
    renditions = [
        "Default",
        "Dark",
        "TintedLight",
        "TintedDark",
        "ClearLight",
        "ClearDark",
    ]
    sizes = [(1024, 1024)]

    results: Dict[str, Any] = {"valid": True, "exports": [], "errors": []}

    for platform in platforms:
        for rendition in renditions:
            for width, height in sizes:
                output_png = os.path.join(
                    output_dir, f"validate_{platform}_{rendition}_{width}x{height}.png"
                )
                try:
                    subprocess.run(
                        [
                            ICTOOL_PATH,
                            icon_path,
                            "--export-image",
                            "--output-file",
                            output_png,
                            "--platform",
                            platform,
                            "--rendition",
                            rendition,
                            "--width",
                            str(width),
                            "--height",
                            str(height),
                            "--scale",
                            "1",
                        ],
                        capture_output=True,
                        text=True,
                        check=True,
                    )
                    results["exports"].append(
                        {
                            "platform": platform,
                            "rendition": rendition,
                            "size": (width, height),
                            "output": output_png,
                        }
                    )
                except subprocess.CalledProcessError as e:
                    error_msg = f"{platform}/{rendition}/{width}x{height}: {e.stderr}"
                    results["errors"].append(error_msg)
                    results["valid"] = False

    return results


def generate_variants(icon_path: str, output_dir: Optional[str] = None) -> List[str]:
    """Generate icon variants with different supported platforms for visual inspection."""
    icon = IconEditor.load(icon_path)

    if output_dir is None:
        output_dir = os.path.dirname(icon_path) or "."
    output_dir = os.path.join(output_dir, "variants")
    os.makedirs(output_dir, exist_ok=True)

    variants: List[str] = []
    platforms = ["shared", "ios", "macos"]

    for platform in platforms:
        variant_dir = os.path.join(output_dir, f"{platform}.icon")
        if os.path.exists(variant_dir):
            shutil.rmtree(variant_dir)

        shutil.copytree(icon_path, variant_dir)

        variant_icon = IconEditor.load(variant_dir)
        variant_icon.set_supported_platforms(platform)
        variant_icon.save()
        variants.append(variant_dir)

    return variants
