#!/usr/bin/env python3

import json
import logging
import os
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
from typing import Any, Dict, List, Optional, Tuple, Union

logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger(__name__)

# Web color names to extended-srgb values (from htmlcolorcodes.com)
# Conflicts with Apple/Crayons palettes are noted in comments
WEB_COLORS = {
    # Same name, same values:
    "black": "0.00000,0.00000,0.00000",  # #000000
    "licorice": "0.00000,0.00000,0.00000",  # #000000
    "white": "1.00000,1.00000,1.00000",  # #ffffff
    # Conflicts: Apple/Crayons use different values
    "blue": "0.00000,0.00000,1.00000",  # #0000ff (Apple=#0433ff)
    "red": "1.00000,0.00000,0.00000",  # #ff0000 (Apple=#ff2600)
    "green": "0.00000,0.50196,0.00000",  # #008000 (Apple=#00f900)
    "orange": "1.00000,0.64706,0.00000",  # #ff7f00 (Apple=#ff9300)
    "brown": "0.64706,0.16471,0.16471",  # #a52a2a (Apple=#aa7942)
    "cyan": "0.00000,1.00000,1.00000",  # #00ffff (Apple=#00fdff)
    "magenta": "1.00000,0.00000,1.00000",  # #ff00ff (Apple/Crayons=#ff40ff)
    "purple": "0.50196,0.00000,0.50196",  # #800080 (Apple=#942192)
    "yellow": "1.00000,1.00000,0.00000",  # #ffff00 (Apple=#fffb00)
    # Crayons palette also has different values for these names
    "honeydew": "0.94118,1.00000,0.94118",  # #f0fff0 (Crayons=#d4fb79)
    "lavender": "0.90196,0.90196,0.98039",  # #e6e6fa (Crayons=#d783ff)
    "snow": "1.00000,0.98039,0.98039",  # #fffafa (Crayons=#ffffff)
    "salmon": "0.98039,0.50196,0.44706",  # #fa8072 (Crayons=#ff7e79)
    "banana": "1.00000,0.98431,0.42745",  # #ffe135 (Crayons=#fffc79)
    "flora": "0.40784,0.97647,0.43137",  # #68fa6d (Crayons=#73fa79)
    "ice": "0.40784,0.99216,1.00000",  # #68fdff (Crayons=#73fdff)
    "orchid": "0.85490,0.43922,0.83922",  # #da70d6 (Crayons=#7a81ff)
    "bubblegum": "1.00000,0.47843,1.00000",  # #ffc1cc (Crayons=#ff85ff)
    "lead": "0.11765,0.11765,0.11765",  # #1e1e1e (Crayons=#212121)
    "mercury": "0.90980,0.90980,0.90980",  # #e8e8e8 (Crayons=#ebebeb)
    "tangerine": "1.00000,0.53333,0.00784",  # #ff8800 (Crayons=#ff9300)
    "lime": "0.00000,1.00000,0.00000",  # #00ff00 (Crayons=#8efa00)
    "sea_foam": "0.01176,0.97647,0.52941",  # #03f988 (Crayons=#00fa92)
    "aqua": "0.00000,1.00000,1.00000",  # #00ffff (Crayons=#0096ff)
    "grape": "0.53725,0.19216,1.00000",  # #8923ff (Crayons=#9437ff)
    "strawberry": "1.00000,0.16078,0.52941",  # #ff2987 (Crayons=#ff2f92)
    "tungsten": "0.22745,0.22745,0.22745",  # #3a3a3a (Crayons=#424242)
    "silver": "0.75294,0.75294,0.75294",  # #c0c0c0 (Crayons=#d6d6d6)
    "maraschino": "1.00000,0.12941,0.00392",  # #ff2100 (Crayons=#ff2600)
    "lemon": "1.00000,0.98039,0.01176",  # #fffa00 (Crayons=#fffb00)
    "spring": "0.01961,0.97255,0.00784",  # #05f800 (Crayons=#00f900)
    "turquoise": "0.25098,0.87843,0.81569",  # #40e0d0 (Crayons=#00fdff)
    "blueberry": "0.00000,0.18039,1.00000",  # #002dff (Crayons=#0433ff)
    "iron": "0.32941,0.32941,0.32549",  # #545452 (Crayons=#5e5e5e)
    "magnesium": "0.72157,0.72157,0.72157",  # #b8b8b8 (Crayons=#c0c0c0)
    "mocha": "0.53725,0.28235,0.00000",  # #894800 (Crayons=#945200)
    "fern": "0.27059,0.51765,0.00392",  # #458400 (Crayons=#4f8f00)
    "moss": "0.00392,0.51765,0.28235",  # #018447 (Crayons=#009051)
    "ocean": "0.00000,0.29020,0.53333",  # #004a88 (Crayons=#005493)
    "eggplant": "0.28627,0.10196,0.53333",  # #491a88 (Crayons=#531b93)
    "maroon": "0.50196,0.00000,0.00000",  # #800000 (Crayons=#941751)
    "steel": "0.43137,0.43137,0.43137",  # #6e6e6e (Crayons=#797979)
    "aluminum": "0.62745,0.62353,0.62745",  # #a09fa0 (Crayons=#a9a9a9)
    "cayenne": "0.53725,0.06667,0.00000",  # #891100 (Crayons=#941100)
    "asparagus": "0.53333,0.52157,0.00392",  # #888500 (Crayons=#929000)
    "clover": "0.00784,0.51765,0.00392",  # #028400 (Crayons=#008f00)
    "teal": "0.00000,0.50196,0.50196",  # #008080 (Crayons=#009193)
    "midnight": "0.00000,0.09412,0.53333",  # #001888 (Crayons=#011993)
    "plum": "0.86667,0.62745,0.86667",  # #dda0dd (Crayons=#942193)
    "tin": "0.52941,0.52549,0.52941",  # #878686 (Crayons=#919191)
    "nickel": "0.53333,0.52941,0.52941",  # #888786 (Crayons=#929292)
    # No conflicts - unique to web palette
    "aliceblue": "0.94118,0.97255,1.00000",  # #f0f8ff
    "antiquewhite": "0.98039,0.92157,0.84314",  # #faebd7
    "aquamarine": "0.49804,1.00000,0.83137",  # #7fffd4
    "azure": "0.94118,1.00000,1.00000",  # #f0ffff
    "beige": "0.96078,0.96078,0.86275",  # #f5f5dc
    "bisque": "1.00000,0.89412,0.76863",  # #ffe4c4
    "blanchedalmond": "1.00000,0.92157,0.80392",  # #ffebcd
    "blueviolet": "0.54118,0.16863,0.88627",  # #8a2be2
    "burlywood": "0.87059,0.72157,0.52941",  # #deb887
    "cadetblue": "0.37255,0.61961,0.62745",  # #5f9ea0
    "chartreuse": "0.49804,1.00000,0.00000",  # #7fff00
    "chocolate": "0.82353,0.41176,0.11765",  # #d2691e
    "coral": "1.00000,0.49804,0.31373",  # #ff7f50
    "cornflowerblue": "0.39216,0.58431,0.92941",  # #6495ed
    "cornsilk": "1.00000,0.97255,0.86275",  # #fff8dc
    "crimson": "0.86275,0.07843,0.23529",  # #dc143c
    "darkblue": "0.00000,0.00000,0.54510",  # #00008b
    "darkcyan": "0.00000,0.54510,0.54510",  # #008b8b
    "darkgoldenrod": "0.72157,0.52549,0.04314",  # #b8860b
    "darkgray": "0.66275,0.66275,0.66275",  # #a9a9a9
    "darkgreen": "0.00000,0.39216,0.00000",  # #006400
    "darkgrey": "0.66275,0.66275,0.66275",  # #a9a9a9
    "darkkhaki": "0.74118,0.71765,0.41961",  # #bdb76b
    "darkmagenta": "0.54510,0.00000,0.54510",  # #8b008b
    "darkolivegreen": "0.33333,0.41961,0.18431",  # #556b2f
    "darkorange": "1.00000,0.54902,0.00000",  # #ff8c00
    "darkorchid": "0.60000,0.19608,0.80000",  # #9932cc
    "darkred": "0.54510,0.00000,0.00000",  # #8b0000
    "darksalmon": "0.91373,0.58824,0.47843",  # #e9967a
    "darkseagreen": "0.56078,0.73725,0.56078",  # #8fbc8f
    "darkslateblue": "0.28235,0.23922,0.54510",  # #483d8b
    "darkslategray": "0.18431,0.30980,0.30980",  # #2f4f4f
    "darkslategrey": "0.18431,0.30980,0.30980",  # #2f4f4f
    "darkturquoise": "0.00000,0.80784,0.81961",  # #00ced1
    "darkviolet": "0.58039,0.00000,0.82745",  # #9400d3
    "deeppink": "1.00000,0.07843,0.57647",  # #ff1493
    "deepskyblue": "0.00000,0.74902,1.00000",  # #00bfff
    "dimgray": "0.41176,0.41176,0.41176",  # #696969
    "dimgrey": "0.41176,0.41176,0.41176",  # #696969
    "dodgerblue": "0.11765,0.56471,1.00000",  # #1e90ff
    "firebrick": "0.69804,0.13333,0.13333",  # #b22222
    "floralwhite": "1.00000,0.98039,0.94118",  # #fffaf0
    "forestgreen": "0.13333,0.54510,0.13333",  # #228b22
    "fuchsia": "1.00000,0.00000,1.00000",  # #ff00ff
    "gainsboro": "0.86275,0.86275,0.86275",  # #dcdcdc
    "ghostwhite": "0.97255,0.97255,1.00000",  # #f8f8ff
    "gold": "1.00000,0.84314,0.00000",  # #ffd700
    "goldenrod": "0.85490,0.64706,0.12549",  # #daa520
    "gray": "0.50196,0.50196,0.50196",  # #808080
    "greenyellow": "0.67843,1.00000,0.18431",  # #adff2f
    "grey": "0.50196,0.50196,0.50196",  # #808080
    "hotpink": "1.00000,0.41176,0.70588",  # #ff69b4
    "indianred": "0.80392,0.36078,0.36078",  # #cd5c5c
    "indigo": "0.29412,0.00000,0.50980",  # #4b0082
    "ivory": "1.00000,1.00000,0.94118",  # #fffff0
    "khaki": "0.94118,0.90196,0.54902",  # #f0e68c
    "lavenderblush": "1.00000,0.94118,0.96078",  # #fff0f5
    "lawngreen": "0.48627,0.98824,0.00000",  # #7cfc00
    "lemonchiffon": "1.00000,0.98039,0.80392",  # #fffacd
    "lightblue": "0.67843,0.84706,0.90196",  # #add8e6
    "lightcoral": "0.94118,0.50196,0.50196",  # #f08080
    "lightcyan": "0.87843,1.00000,1.00000",  # #e0ffff
    "lightgoldenrodyellow": "0.98039,0.98039,0.82353",  # #fafad2
    "lightgray": "0.82745,0.82745,0.82745",  # #d3d3d3
    "lightgreen": "0.56471,0.93333,0.56471",  # #90ee90
    "lightgrey": "0.82745,0.82745,0.82745",  # #d3d3d3
    "lightpink": "1.00000,0.71373,0.75686",  # #ffb6c1
    "lightsalmon": "1.00000,0.62745,0.47843",  # #ffa07a
    "lightseagreen": "0.12549,0.69804,0.66667",  # #20b2aa
    "lightskyblue": "0.52941,0.80784,0.98039",  # #87cefa
    "lightslategray": "0.46667,0.53333,0.60000",  # #778899
    "lightslategrey": "0.46667,0.53333,0.60000",  # #778899
    "lightsteelblue": "0.69020,0.76863,0.87059",  # #b0c4de
    "lightyellow": "1.00000,1.00000,0.87843",  # #ffffe0
    "limegreen": "0.19608,0.80392,0.19608",  # #32cd32
    "linen": "0.98039,0.94118,0.90196",  # #faf0e6
    "mediumaquamarine": "0.40000,0.80392,0.66667",  # #66cdaa
    "mediumblue": "0.00000,0.00000,0.80392",  # #0000cd
    "mediumorchid": "0.72941,0.33333,0.82745",  # #ba55d3
    "mediumpurple": "0.57647,0.43922,0.85882",  # #9370db
    "mediumseagreen": "0.23529,0.70196,0.44314",  # #3cb371
    "mediumslateblue": "0.48235,0.40784,0.93333",  # #7b68ee
    "mediumspringgreen": "0.00000,0.98039,0.60392",  # #00fa9a
    "mediumturquoise": "0.28235,0.81961,0.80000",  # #48d1cc
    "mediumvioletred": "0.78039,0.08235,0.52157",  # #c71585
    "mintcream": "0.96078,1.00000,0.98039",  # #f5fffa
    "mistyrose": "1.00000,0.89412,0.88235",  # #ffe4e1
    "moccasin": "1.00000,0.89412,0.70980",  # #ffe4b5
    "navajowhite": "1.00000,0.87059,0.67843",  # #ffdead
    "navy": "0.00000,0.00000,0.50196",  # #000080
    "oldlace": "0.99216,0.96078,0.90196",  # #fdf5e6
    "olive": "0.50196,0.50196,0.00000",  # #808000
    "olivedrab": "0.41961,0.55686,0.13725",  # #6b8e23
    "orangered": "1.00000,0.27059,0.00000",  # #ff4500
    "palegoldenrod": "0.93333,0.90980,0.66667",  # #eee8aa
    "palegreen": "0.59608,0.98431,0.59608",  # #98fb98
    "paleturquoise": "0.68627,0.93333,0.93333",  # #afeeee
    "palevioletred": "0.85882,0.43922,0.57647",  # #db7093
    "papayawhip": "1.00000,0.93725,0.83529",  # #ffefd5
    "peachpuff": "1.00000,0.85490,0.72549",  # #ffdab9
    "peru": "0.80392,0.52157,0.24706",  # #cd853f
    "pink": "1.00000,0.75294,0.79608",  # #ffc0cb
    "powderblue": "0.69020,0.87843,0.90196",  # #b0e0e6
    "rebeccapurple": "0.40000,0.20000,0.60000",  # #663399
    "rosybrown": "0.73725,0.56078,0.56078",  # #bc8f8f
    "royalblue": "0.25490,0.41176,0.88235",  # #4169e1
    "saddlebrown": "0.54510,0.27059,0.07451",  # #8b4513
    "sandybrown": "0.95686,0.64314,0.37647",  # #f4a460
    "seagreen": "0.18039,0.54510,0.34118",  # #2e8b57
    "seashell": "1.00000,0.96078,0.93333",  # #fff5ee
    "sienna": "0.62745,0.32157,0.17647",  # #a0522d
    "skyblue": "0.52941,0.80784,0.92157",  # #87ceeb
    "slateblue": "0.41569,0.35294,0.80382",  # #6a5acd
    "slategray": "0.43922,0.50196,0.56471",  # #708090
    "slategrey": "0.43922,0.50196,0.56471",  # #708090
    "springgreen": "0.00000,1.00000,0.49804",  # #00ff7f
    "steelblue": "0.27451,0.50980,0.70588",  # #4682b4
    "tan": "0.82353,0.70588,0.54902",  # #d2b48c
    "thistle": "0.84706,0.74902,0.84706",  # #d8bfd8
    "tomato": "1.00000,0.38824,0.27843",  # #ff6347
    "violet": "0.93333,0.50980,0.93333",  # #ee82ee
    "wheat": "0.96078,0.87059,0.70196",  # #f5deb3
    "whitesmoke": "0.96078,0.96078,0.96078",  # #f5f5f5
    "yellowgreen": "0.60392,0.80392,0.19608",  # #9acd32
}

APPLE_COLORS = {
    "black": "0.00000,0.00000,0.00000",  # #000000
    "white": "1.00000,1.00000,1.00000",  # #ffffff
    "red": "1.00000,0.149019608,0.00000",  # #ff2600
    "green": "0.00000,0.976470588,0.00000",  # #00f900
    "blue": "0.015686275,0.20000,1.00000",  # #0433ff
    "cyan": "0.00000,0.992156863,1.00000",  # #00fdff
    "magenta": "1.00000,0.250980392,1.00000",  # #ff40ff
    "yellow": "1.00000,0.984313725,0.00000",  # #fffb00
    "orange": "1.00000,0.576470588,0.00000",  # #ff9300
    "purple": "0.580392157,0.129411765,0.57254902",  # #942192
    "brown": "0.666666667,0.474509804,0.258823529",  # #aa7942
}

CRAYONS_COLORS = {
    # Grayscale (dark to light)
    "licorice": "0.00000,0.00000,0.00000",  # #000000
    "lead": "0.12941,0.12941,0.12941",  # #212121
    "tungsten": "0.25882,0.25882,0.25882",  # #424242
    "iron": "0.36863,0.36863,0.36863",  # #5e5e5e
    "steel": "0.47451,0.47451,0.47451",  # #797979
    "tin": "0.56863,0.56863,0.56863",  # #919191
    "nickel": "0.57255,0.57255,0.57255",  # #929292
    "aluminum": "0.66275,0.66275,0.66275",  # #a9a9a9
    "magnesium": "0.75294,0.75294,0.75294",  # #c0c0c0
    "silver": "0.83922,0.83922,0.83922",  # #d6d6d6
    "mercury": "0.92157,0.92157,0.92157",  # #ebebeb
    "snow": "1.00000,1.00000,1.00000",  # #ffffff
    # Browns (dark to light)
    "cayenne": "0.58039,0.06667,0.00000",  # #941100
    "mocha": "0.58039,0.32157,0.00000",  # #945200
    "asparagus": "0.57255,0.56471,0.00000",  # #929000
    "fern": "0.30980,0.56078,0.00000",  # #4f8f00
    "clover": "0.00000,0.56078,0.00000",  # #008f00
    "moss": "0.00000,0.56078,0.27843",  # #009051
    "teal": "0.00000,0.52549,0.53333",  # #009193
    "ocean": "0.00000,0.29020,0.53333",  # #005493
    "midnight": "0.00392,0.09804,0.57647",  # #011993
    "eggplant": "0.32549,0.10588,0.57647",  # #531b93
    "plum": "0.58039,0.12941,0.57647",  # #942193
    "maroon": "0.58039,0.09020,0.31765",  # #941751
    # Reds
    "maraschino": "1.00000,0.14902,0.00000",  # #ff2600
    "tangerine": "1.00000,0.57647,0.00000",  # #ff9300
    "lemon": "1.00000,0.98431,0.00000",  # #fffb00
    "lime": "0.55686,0.98039,0.00000",  # #8efa00
    "spring": "0.00000,0.9764706,0.00000",  # #00f900
    "sea_foam": "0.00000,0.98039,0.57255",  # #00fa92
    "turquoise": "0.00000,0.99216,1.00000",  # #00fdff
    "aqua": "0.00000,0.58824,1.00000",  # #0096ff
    "blueberry": "0.01569,0.20000,1.00000",  # #0433ff
    "grape": "0.58039,0.21569,1.00000",  # #9437ff
    "magenta": "1.00000,0.25098,1.00000",  # #ff40ff
    "strawberry": "1.00000,0.18431,0.57255",  # #ff2f92
    # Pinks
    "salmon": "1.00000,0.49412,0.47451",  # #ff7e79
    "cantaloupe": "1.00000,0.83137,0.47451",  # #ffd479
    "banana": "1.00000,0.98824,0.47451",  # #fffc79
    "honeydew": "0.83137,0.98431,0.47451",  # #d4fb79
    "flora": "0.45098,0.98039,0.47451",  # #73fa79
    "spindrift": "0.45098,0.98824,0.83922",  # #73fcd6
    "ice": "0.45098,0.99216,1.00000",  # #73fdff
    "sky": "0.46275,0.83922,1.00000",  # #76d6ff
    "orchid": "0.47843,0.50588,1.00000",  # #7a81ff
    "lavender": "0.84314,0.51373,1.00000",  # #d783ff
    "bubblegum": "1.00000,0.52157,1.00000",  # #ff85ff
    "carnation": "1.00000,0.54118,0.84706",  # #ff8ad8
}

VALID_BLEND_MODES = {
    "darken",
    "multiply",
    "plus-darker",
    "lighten",
    "screen",
    "plus-lighter",
    "overlay",
    "soft-light",
    "hard-light",
}
VALID_SHADOW_KINDS = {"none", "neutral", "layer-color"}


def _format_rgb(r: float, g: float, b: float, a: float = 1.0) -> str:
    return f"extended-srgb:{r:.5f},{g:.5f},{b:.5f},{a:.5f}"


def resolve_color(color_str: str) -> str:
    """Resolve color to valid format for Icon Composer."""
    original = color_str
    color_str = color_str.strip().lower()

    if any(color_str.startswith(p) for p in ("extended-srgb:", "extended-gray:", "display-p3:", "srgb:")):
        return color_str

    prefix = None
    if (
        color_str.startswith("apple.")
        or color_str.startswith("crayons.")
        or color_str.startswith("web.")
    ):
        prefix = color_str.split(".")[0]
        color_str = color_str[len(prefix) + 1 :]

    if prefix == "web":
        if color_str in WEB_COLORS:
            return _format_rgb(*_parse_extended_srgb(WEB_COLORS[color_str]))
        logger.warning("Web color '%s' not found, defaulting to black.", color_str)
        return _format_rgb(0, 0, 0)

    if prefix == "apple":
        if color_str in APPLE_COLORS:
            return _format_rgb(*_parse_extended_srgb(APPLE_COLORS[color_str]))
        logger.warning("Apple color '%s' not found, defaulting to black.", color_str)
        return _format_rgb(0, 0, 0)

    if prefix == "crayons":
        if color_str in CRAYONS_COLORS:
            return _format_rgb(*_parse_extended_srgb(CRAYONS_COLORS[color_str]))
        logger.warning("Crayons color '%s' not found, defaulting to black.", color_str)
        return _format_rgb(0, 0, 0)

    if color_str in APPLE_COLORS:
        if color_str in WEB_COLORS and APPLE_COLORS[color_str] != WEB_COLORS[color_str]:
            logger.warning(
                "Color '%s' is ambiguous. Using Apple color (%s) instead of web color (%s). "
                "Use 'apple.%s', 'web.%s', or 'crayons.%s' to disambiguate.",
                color_str,
                APPLE_COLORS[color_str],
                WEB_COLORS[color_str],
                color_str,
                color_str,
                color_str,
            )
        return _format_rgb(*_parse_extended_srgb(APPLE_COLORS[color_str]))

    if color_str in CRAYONS_COLORS:
        if (
            color_str in WEB_COLORS
            and CRAYONS_COLORS[color_str] != WEB_COLORS[color_str]
        ):
            logger.warning(
                "Color '%s' is ambiguous. Using Crayons color (%s) instead of web color (%s). "
                "Use 'apple.%s', 'web.%s', or 'crayons.%s' to disambiguate.",
                color_str,
                CRAYONS_COLORS[color_str],
                WEB_COLORS[color_str],
                color_str,
                color_str,
                color_str,
            )
        return _format_rgb(*_parse_extended_srgb(CRAYONS_COLORS[color_str]))

    if color_str in WEB_COLORS:
        return _format_rgb(*_parse_extended_srgb(WEB_COLORS[color_str]))

    hex_match = re.match(
        r"#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})?", color_str, re.I
    )
    if hex_match:
        r = int(hex_match.group(1), 16)
        g = int(hex_match.group(2), 16)
        b = int(hex_match.group(3), 16)
        a = int(hex_match.group(4), 16) if hex_match.group(4) else 255
        return _format_rgb(r / 255, g / 255, b / 255, a / 255)

    short_hex_match = re.match(r"#([0-9a-f]{3})([0-9a-f])?", color_str, re.I)
    if short_hex_match:
        digit_r = short_hex_match.group(1)[0] * 2
        digit_g = short_hex_match.group(1)[1] * 2
        digit_b = short_hex_match.group(1)[2] * 2
        r = int(digit_r, 16) / 255.0
        g = int(digit_g, 16) / 255.0
        b = int(digit_b, 16) / 255.0
        if short_hex_match.group(2):
            a = int(short_hex_match.group(2) * 2, 16) / 255.0
        else:
            a = 1.0
        return _format_rgb(r, g, b, a)

    rgba_match = re.match(
        r"rgba?\(\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)(?:\s*,\s*(\d*\.?\d+))?\s*\)",
        color_str,
    )
    if rgba_match:
        r = float(rgba_match.group(1))
        g = float(rgba_match.group(2))
        b = float(rgba_match.group(3))
        has_alpha = rgba_match.group(4) is not None
        a = float(rgba_match.group(4)) if has_alpha else 1.0
        if has_alpha and a > 1:
            pass
        else:
            if r > 1 or g > 1 or b > 1:
                r /= 255
                g /= 255
                b /= 255
            return _format_rgb(r, g, b, a)

    hsl_match = re.match(
        r"hsla?\(\s*(\d*\.?\d+)\s*,\s*(\d*\.?\d+)%?\s*,\s*(\d*\.?\d+)%?(?:\s*,\s*(\d*\.?\d+))?\s*\)",
        color_str,
    )
    if hsl_match:
        h = float(hsl_match.group(1))
        s = float(hsl_match.group(2)) / 100.0
        l = float(hsl_match.group(3)) / 100.0
        a = float(hsl_match.group(4)) if hsl_match.group(4) else 1.0

        def hsl_to_rgb(h, s, l):
            if s == 0:
                return l, l, l
            q = l * (1 + s) if l < 0.5 else l + s - l * s
            p = 2 * l - q
            h /= 360.0
            return (
                _hue_to_rgb(p, q, h + 1 / 3),
                _hue_to_rgb(p, q, h),
                _hue_to_rgb(p, q, h - 1 / 3),
            )

        r, g, b = hsl_to_rgb(h, s, l)
        return _format_rgb(r, g, b, a)

    logger.warning("Invalid color format '%s', defaulting to black.", color_str)
    return _format_rgb(0, 0, 0)


def _parse_extended_srgb(values: str) -> Tuple[float, float, float]:
    """Parse comma-separated extended-srgb values (without alpha)."""
    parts = values.split(",")
    return (float(parts[0]), float(parts[1]), float(parts[2]))


def _hue_to_rgb(p: float, q: float, t: float) -> float:
    if t < 0:
        t += 1
    if t > 1:
        t -= 1
    if t < 1 / 6:
        return p + (q - p) * 6 * t
    if t < 1 / 2:
        return q
    if t < 2 / 3:
        return p + (q - p) * (2 / 3 - t) * 6
    return p


def _validate_scale(scale: float) -> float:
    if scale <= 0:
        raise ValueError(f"Scale must be positive, got {scale}")
    return scale


def _validate_translucency(value: float) -> float:
    if not 0 <= value <= 1:
        raise ValueError(f"Translucency must be 0-1, got {value}")
    return value


def _validate_blend_mode(blend_mode: str) -> str:
    if blend_mode not in VALID_BLEND_MODES:
        raise ValueError(
            f"Invalid blend mode '{blend_mode}'. Valid: {VALID_BLEND_MODES}"
        )
    return blend_mode


def _validate_shadow_kind(kind: str) -> str:
    if kind not in VALID_SHADOW_KINDS:
        raise ValueError(f"Invalid shadow kind '{kind}'. Valid: {VALID_SHADOW_KINDS}")
    return kind


def _validate_shadow_opacity(opacity: float) -> float:
    if not 0 <= opacity <= 1:
        raise ValueError(f"Shadow opacity must be 0-1, got {opacity}")
    return opacity


class IconEditor:
    def __init__(self):
        self.icon_dir: Optional[str] = None
        self.icon_json_path: Optional[str] = None
        self.assets_dir: Optional[str] = None
        self.icon_data: Dict[str, Any] = {
            "fill": {"automatic-gradient": "extended-gray:1.00000,1.00000"},
            "groups": [],
            "supported-platforms": {"squares": "shared"},
        }

    @classmethod
    def create_new(cls, icon_path: str, background_color: str) -> "IconEditor":
        instance = cls()
        instance.icon_dir = icon_path
        instance.icon_json_path = os.path.join(icon_path, "icon.json")
        instance.assets_dir = os.path.join(icon_path, "Assets")
        instance.icon_data["fill"] = {
            "automatic-gradient": resolve_color(background_color)
        }
        os.makedirs(instance.assets_dir, exist_ok=True)
        instance.save()
        return instance

    @classmethod
    def load(cls, icon_path: str) -> "IconEditor":
        if not os.path.isdir(icon_path):
            raise FileNotFoundError(f"Icon directory not found: {icon_path}")
        json_path = os.path.join(icon_path, "icon.json")
        if not os.path.exists(json_path):
            raise FileNotFoundError(f"icon.json not found in: {icon_path}")

        instance = cls()
        instance.icon_dir = icon_path
        instance.icon_json_path = json_path
        instance.assets_dir = os.path.join(icon_path, "Assets")
        with open(json_path, "r") as f:
            instance.icon_data = json.load(f)
        return instance

    AUTO_SCALE_TARGET = 768

    @staticmethod
    def _get_svg_dimensions(svg_path: str) -> Tuple[float, float]:
        """Return (width, height) of an SVG from width/height attrs or viewBox."""
        try:
            tree = ET.parse(svg_path)
            root = tree.getroot()
            ns = ""
            if root.tag.startswith("{"):
                ns = root.tag.split("}")[0] + "}"
            tag = root.tag.replace(ns, "")
            if tag != "svg":
                return (0, 0)
            w = root.get("width", "")
            h = root.get("height", "")
            if w and h:
                try:
                    return (float(w.replace("px", "")), float(h.replace("px", "")))
                except ValueError:
                    pass
            vb = root.get("viewBox", "")
            if vb:
                parts = vb.replace(",", " ").split()
                if len(parts) == 4:
                    try:
                        return (float(parts[2]), float(parts[3]))
                    except ValueError:
                        pass
        except ET.ParseError:
            pass
        return (0, 0)

    @staticmethod
    def _get_image_dimensions(image_path: str) -> Tuple[int, int]:
        """Return (width, height) of a raster image using sips."""
        try:
            result = subprocess.run(
                ["sips", "-g", "pixelWidth", "-g", "pixelHeight", image_path],
                capture_output=True, text=True,
            )
            if result.returncode == 0:
                w = h = 0
                for line in result.stdout.splitlines():
                    if "pixelWidth" in line:
                        w = int(line.split(":")[-1].strip())
                    elif "pixelHeight" in line:
                        h = int(line.split(":")[-1].strip())
                return (w, h)
        except Exception:
            pass
        return (0, 0)

    @classmethod
    def _compute_auto_scale(cls, width: float, height: float) -> float:
        """Compute scale factor so longest dimension maps to AUTO_SCALE_TARGET."""
        longest = max(width, height)
        if longest <= 0:
            return cls.AUTO_SCALE_TARGET / 1024.0
        return cls.AUTO_SCALE_TARGET / longest

    def _unique_layer_name(self, base_name: str, asset_ext: str = "") -> str:
        """Return a layer name unique across all groups and asset files.
        If base_name is taken, tries base_name.1, base_name.2, etc.
        asset_ext (e.g. '.svg', '.png') is checked against existing files in Assets/."""
        existing_names = set()
        for group in self.icon_data.get("groups", []):
            for layer in group.get("layers", []):
                existing_names.add(layer.get("name", ""))
        existing_assets = set()
        if self.assets_dir and os.path.isdir(self.assets_dir):
            existing_assets = set(os.listdir(self.assets_dir))

        def _is_available(name: str) -> bool:
            if name in existing_names:
                return False
            if asset_ext and f"{name}{asset_ext}" in existing_assets:
                return False
            return True

        if _is_available(base_name):
            return base_name
        n = 1
        while not _is_available(f"{base_name}.{n}"):
            n += 1
        return f"{base_name}.{n}"

    def add_svg_layer(
        self,
        svg_path: str,
        layer_name: Optional[str] = None,
        color: Optional[str] = None,
        glass: bool = True,
        blend_mode: Optional[str] = None,
        auto_scale: bool = False,
        group: Union[int, str] = 1,
    ):
        if not os.path.exists(svg_path):
            raise FileNotFoundError(f"SVG file not found: {svg_path}")
        if blend_mode:
            _validate_blend_mode(blend_mode)
        if not self.assets_dir:
            raise RuntimeError(
                "Icon not initialized. Use create_new() or load() first."
            )

        if not layer_name:
            base = os.path.splitext(os.path.basename(svg_path))[0]
            layer_name = self._unique_layer_name(base, ".svg")
        else:
            layer_name = self._unique_layer_name(layer_name, ".svg")

        asset_name = f"{layer_name}.svg"
        asset_path = os.path.join(self.assets_dir, asset_name)
        shutil.copy(svg_path, asset_path)

        if not self.icon_data["groups"]:
            self.icon_data["groups"].append({"layers": []})

        if auto_scale:
            w, h = self._get_svg_dimensions(svg_path)
            scale = self._compute_auto_scale(w, h)
        else:
            scale = 1.0

        layer: Dict[str, Any] = {
            "name": layer_name,
            "image-name": asset_name,
            "position": {"scale": scale, "translation-in-points": [0, 0]},
            "glass": glass,
        }
        if color:
            layer["fill"] = {"automatic-gradient": resolve_color(color)}
        if blend_mode:
            layer["blend-mode"] = blend_mode

        target_group = self._get_group(group)
        if target_group is None:
            target_group = self.icon_data["groups"][0]
        target_group["layers"].insert(0, layer)
        self.save()
        return layer_name

    # Image formats that Icon Composer embeds as-is (no conversion needed)
    _NATIVE_IMAGE_EXTS = {".png", ".jpg", ".jpeg"}

    def add_image_layer(
        self,
        image_path: str,
        layer_name: Optional[str] = None,
        glass: bool = True,
        blend_mode: Optional[str] = None,
        auto_scale: bool = False,
        group: Union[int, str] = 1,
    ):
        """Add a raster image layer. PNG and JPEG are embedded as-is;
        other formats are converted to PNG using sips."""
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Image file not found: {image_path}")
        if blend_mode:
            _validate_blend_mode(blend_mode)
        if not self.assets_dir:
            raise RuntimeError(
                "Icon not initialized. Use create_new() or load() first."
            )

        src_ext = os.path.splitext(image_path)[1].lower()
        if src_ext in self._NATIVE_IMAGE_EXTS:
            asset_ext = ".jpg" if src_ext == ".jpeg" else src_ext
        else:
            asset_ext = ".png"

        if not layer_name:
            base = os.path.splitext(os.path.basename(image_path))[0]
            layer_name = self._unique_layer_name(base, asset_ext)
        else:
            layer_name = self._unique_layer_name(layer_name, asset_ext)

        if src_ext in self._NATIVE_IMAGE_EXTS:
            asset_name = f"{layer_name}{asset_ext}"
            asset_path = os.path.join(self.assets_dir, asset_name)
            shutil.copy(image_path, asset_path)
        else:
            # Convert to PNG using sips
            asset_name = f"{layer_name}.png"
            asset_path = os.path.join(self.assets_dir, asset_name)
            result = subprocess.run(
                ["sips", "-s", "format", "png", image_path, "--out", asset_path],
                capture_output=True, text=True,
            )
            if result.returncode != 0:
                raise RuntimeError(
                    f"sips conversion failed: {result.stderr.strip()}"
                )

        if not self.icon_data["groups"]:
            self.icon_data["groups"].append({"layers": []})

        layer: Dict[str, Any] = {
            "name": layer_name,
            "image-name": asset_name,
            "glass": glass,
        }
        if auto_scale:
            w, h = self._get_image_dimensions(image_path)
            scale = self._compute_auto_scale(w, h)
            layer["position"] = {"scale": scale, "translation-in-points": [0, 0]}
        if blend_mode:
            layer["blend-mode"] = blend_mode

        target_group = self._get_group(group)
        if target_group is None:
            target_group = self.icon_data["groups"][0]
        target_group["layers"].insert(0, layer)
        self.save()
        return layer_name

    def scale_shift_layer(
        self, layer_ref: Union[int, str], scale: float, shift_x: int, shift_y: int,
        group: Union[int, str] = 1,
    ):
        _validate_scale(scale)
        layer = self._get_layer(layer_ref, group)
        if layer is not None:
            if "position" not in layer:
                layer["position"] = {"scale": 1.0, "translation-in-points": [0, 0]}
            layer["position"]["scale"] = scale
            layer["position"]["translation-in-points"] = [shift_x, shift_y]
        self.save()

    def set_layer_hidden(self, layer_ref: Union[int, str], hidden: bool,
                         group: Union[int, str] = 1):
        """Set layer visibility. hidden=True hides the layer."""
        layer = self._get_layer(layer_ref, group)
        if layer is not None:
            if hidden:
                layer["hidden"] = True
            elif "hidden" in layer:
                del layer["hidden"]
        self.save()

    def set_glass(self, layer_ref: Union[int, str], glass: bool,
                  group: Union[int, str] = 1):
        """Set or unset glass effect on a layer."""
        layer = self._get_layer(layer_ref, group)
        if layer is not None:
            layer["glass"] = glass
        self.save()

    def set_blend_mode(self, layer_ref: Union[int, str], blend_mode: str,
                      group: Union[int, str] = 1):
        """Set blend mode on a layer. Use 'normal' to remove."""
        if blend_mode != "normal":
            _validate_blend_mode(blend_mode)
        layer = self._get_layer(layer_ref, group)
        if layer is not None:
            if blend_mode == "normal":
                layer.pop("blend-mode", None)
            else:
                layer["blend-mode"] = blend_mode
        self.save()

    def rename_layer(self, layer_ref: Union[int, str], new_name: str,
                     group: Union[int, str] = 1):
        """Rename a layer. The underlying asset file is left unchanged."""
        layer = self._get_layer(layer_ref, group)
        if layer is not None and layer.get("name") != new_name:
            layer["name"] = new_name
            self.save()

    def change_fill(
        self,
        layer_ref: Union[int, str],
        fill_type: str,
        color1: Optional[str] = None,
        color2: Optional[str] = None,
        group: Union[int, str] = 1,
    ):
        if fill_type in ("solid", "auto-gradient") and not color1:
            raise ValueError(f"color1 is required for fill_type '{fill_type}'")
        if fill_type == "gradient" and (not color1 or not color2):
            raise ValueError(
                "color1 and color2 are required for fill_type 'gradient'"
            )

        layer = self._get_layer(layer_ref, group)
        if layer is not None:
            if fill_type in ("none", "automatic"):
                layer["fill"] = fill_type
            elif fill_type == "solid":
                layer["fill"] = {"solid": resolve_color(color1)}  # type: ignore[arg-type]
            elif fill_type == "auto-gradient":
                layer["fill"] = {"automatic-gradient": resolve_color(color1)}  # type: ignore[arg-type]
            elif fill_type == "gradient":
                layer["fill"] = {
                    "linear-gradient": [
                        resolve_color(color1),  # type: ignore[arg-type]
                        resolve_color(color2),  # type: ignore[arg-type]
                    ],
                    "orientation": {
                        "start": {"x": 0.5, "y": 0},
                        "stop": {"x": 0.5, "y": 1},
                    },
                }
        self.save()

    def change_background_fill(
        self,
        fill_type: str,
        color1: Optional[str] = None,
        color2: Optional[str] = None,
    ):
        if fill_type in ("none", "automatic"):
            self.icon_data["fill"] = fill_type
            self.save()
            return

        if fill_type in ("solid", "auto-gradient") and not color1:
            raise ValueError(f"color1 is required for fill_type '{fill_type}'")
        if fill_type == "gradient" and (not color1 or not color2):
            raise ValueError(
                "color1 and color2 are required for fill_type 'gradient'"
            )

        if fill_type == "solid":
            self.icon_data["fill"] = {"solid": resolve_color(color1)}  # type: ignore[arg-type]
        elif fill_type == "auto-gradient":
            self.icon_data["fill"] = {"automatic-gradient": resolve_color(color1)}  # type: ignore[arg-type]
        elif fill_type == "gradient":
            self.icon_data["fill"] = {
                "linear-gradient": [
                    resolve_color(color1),  # type: ignore[arg-type]
                    resolve_color(color2),  # type: ignore[arg-type]
                ],
                "orientation": {
                    "start": {"x": 0.5, "y": 0},
                    "stop": {"x": 0.5, "y": 1},
                },
            }
        self.save()

    def _get_group(self, group_ref) -> Optional[Dict[str, Any]]:
        """Get a group by index (int, 1-based) or name (str).
        Name lookup fails with ValueError if multiple groups share the same name."""
        groups = self.icon_data.get("groups", [])
        if isinstance(group_ref, int):
            idx = group_ref - 1  # 1-based to 0-based
            if 0 <= idx < len(groups):
                return groups[idx]
            return None
        # String name lookup
        matches = [g for g in groups if g.get("name") == group_ref]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            raise ValueError(
                f"Ambiguous group name '{group_ref}': {len(matches)} groups share this name. Use index instead."
            )
        # For unnamed groups, try empty string match against groups with no name key
        if group_ref == "":
            unnamed = [g for g in groups if "name" not in g or g["name"] == ""]
            if len(unnamed) == 1:
                return unnamed[0]
            if len(unnamed) > 1:
                raise ValueError(
                    f"Ambiguous: {len(unnamed)} unnamed groups. Use index instead."
                )
        return None

    def _get_layer(self, layer_ref: Union[int, str], group_ref: Union[int, str] = 1) -> Optional[Dict[str, Any]]:
        """Get a layer by index (int, 1-based within group) or name (str).
        group_ref identifies which group to search (1-based index or name).
        Name lookup fails with ValueError if multiple layers share the same name within the group."""
        target_group = self._get_group(group_ref)
        if target_group is None:
            return None
        layers = target_group.get("layers", [])
        if isinstance(layer_ref, int):
            idx = layer_ref - 1  # 1-based to 0-based
            if 0 <= idx < len(layers):
                return layers[idx]
            return None
        # String name lookup within the group
        matches = [l for l in layers if l.get("name") == layer_ref]
        if len(matches) == 1:
            return matches[0]
        if len(matches) > 1:
            raise ValueError(
                f"Ambiguous layer name '{layer_ref}': {len(matches)} layers share this name in the group. Use index instead."
            )
        return None

    def change_translucency(self, group: Union[int, str], translucency: float):
        _validate_translucency(translucency)
        target = self._get_group(group)
        if target is not None:
            if translucency >= 1.0:
                target.pop("translucency", None)
            else:
                target["translucency"] = {"enabled": True, "value": translucency}
        self.save()

    def set_shadow(self, group: Union[int, str], kind: str, opacity: float):
        _validate_shadow_kind(kind)
        _validate_shadow_opacity(opacity)
        target = self._get_group(group)
        if target is not None:
            target["shadow"] = {"kind": kind, "opacity": opacity}
        self.save()

    def set_group_opacity(self, group: Union[int, str], opacity: float):
        """Set group opacity (Color section). Range 0.0-1.0."""
        if not 0 <= opacity <= 1:
            raise ValueError(f"Opacity must be 0.0-1.0, got {opacity}")
        target = self._get_group(group)
        if target is not None:
            if opacity >= 1.0:
                target.pop("opacity", None)
            else:
                target["opacity"] = opacity
        self.save()

    def set_group_blend_mode(self, group: Union[int, str], blend_mode: str):
        """Set blend mode on a group."""
        target = self._get_group(group)
        if target is not None:
            if blend_mode == "normal":
                target.pop("blend-mode", None)
            else:
                target["blend-mode"] = blend_mode
        self.save()

    def set_group_blur(self, group: Union[int, str], blur: float):
        """Set blur-material on a group. Range 0.0-1.0."""
        if not 0 <= blur <= 1:
            raise ValueError(f"Blur must be 0.0-1.0, got {blur}")
        target = self._get_group(group)
        if target is not None:
            target["blur-material"] = blur
        self.save()

    def set_group_lighting(self, group: Union[int, str], lighting: str):
        """Set lighting mode on a group: 'combined' or 'individual'."""
        if lighting not in ("combined", "individual"):
            raise ValueError(f"Lighting must be 'combined' or 'individual', got '{lighting}'")
        target = self._get_group(group)
        if target is not None:
            target["lighting"] = lighting
        self.save()

    def set_group_specular(self, group: Union[int, str], specular: bool):
        """Set specular on a group."""
        target = self._get_group(group)
        if target is not None:
            target["specular"] = specular
        self.save()

    def rename_group(self, group: Union[int, str], new_name: str):
        """Rename a group."""
        target = self._get_group(group)
        if target is not None:
            target["name"] = new_name
        self.save()

    def scale_shift_group(self, group: Union[int, str], scale: float, shift_x: int, shift_y: int):
        """Set position (scale + translation) on a group via position-specializations."""
        if scale <= 0:
            raise ValueError(f"Scale must be positive, got {scale}")
        target = self._get_group(group)
        if target is not None:
            pos_value = {
                "scale": scale,
                "translation-in-points": [shift_x, shift_y],
            }
            specs = target.get("position-specializations", [])
            found = False
            for spec in specs:
                if spec.get("idiom") == "square":
                    spec["value"] = pos_value
                    found = True
                    break
            if not found:
                specs.append({"idiom": "square", "value": pos_value})
            target["position-specializations"] = specs
        self.save()

    def set_group_hidden(self, group: Union[int, str], hidden: bool):
        """Set group visibility via hidden-specializations (square idiom)."""
        target = self._get_group(group)
        if target is not None:
            specs = target.get("hidden-specializations", [])
            found = False
            for spec in specs:
                if spec.get("idiom") == "square":
                    spec["value"] = hidden
                    found = True
                    break
            if not found:
                specs.append({"idiom": "square", "value": hidden})
            target["hidden-specializations"] = specs
        self.save()

    def get_groups(self) -> List[Dict[str, Any]]:
        return self.icon_data.get("groups", [])

    def get_layers(self, group: Union[int, str] = 1) -> List[Dict[str, Any]]:
        target = self._get_group(group)
        if target is not None:
            return target.get("layers", [])
        return []

    def remove_layer(self, layer_ref: Union[int, str], group: Union[int, str] = 1):
        target_group = self._get_group(group)
        if target_group is None:
            return
        layer = self._get_layer(layer_ref, group)
        if layer is None:
            return
        image_name = layer.get("image-name")
        if image_name and self.icon_json_path:
            asset_path = os.path.join(
                os.path.dirname(self.icon_json_path), "Assets", image_name
            )
            if os.path.isfile(asset_path):
                os.remove(asset_path)
        target_group["layers"] = [l for l in target_group["layers"] if l is not layer]
        self.save()

    def reorder_layer(self, layer_ref: Union[int, str], new_index: int, group: Union[int, str] = 1):
        target_group = self._get_group(group)
        if target_group is None:
            return
        layer = self._get_layer(layer_ref, group)
        if layer is None:
            return
        layers = target_group["layers"]
        layers.remove(layer)
        layers.insert(max(0, min(new_index, len(layers))), layer)
        self.save()

    def save(self) -> None:
        if self.icon_json_path:
            with open(self.icon_json_path, "w") as f:
                json.dump(self.icon_data, f, indent=2)

    def set_supported_platforms(
        self, squares: str, circles: Optional[str] = None
    ) -> None:
        valid_single = {"shared"}
        valid_array = {"iOS", "macOS", "watchOS"}

        supported = {}

        if squares in valid_single:
            supported["squares"] = squares
        elif "," in squares:
            platforms = [p.strip() for p in squares.split(",")]
            supported["squares"] = platforms
        elif squares in valid_array:
            supported["squares"] = [squares]
        else:
            raise ValueError(
                f"Invalid platform '{squares}'. Valid: shared, iOS, macOS, watchOS, or comma-separated like 'iOS,macOS'"
            )

        if circles:
            if "," in circles:
                supported["circles"] = [c.strip() for c in circles.split(",")]
            elif circles in valid_array:
                supported["circles"] = [circles]

        self.icon_data["supported-platforms"] = supported

    def get_supported_platforms(self) -> str:
        squares = self.icon_data.get("supported-platforms", {}).get("squares", "shared")
        if isinstance(squares, list):
            return ",".join(squares)
        return squares
