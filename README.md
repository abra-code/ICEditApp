# ICEdit
![ICEdit Icon](Icon/ICEdit-macOS-128x128@2x.png)

A native macOS icon editor for Apple's `.icon` bundle format used by Icon Composer. ICEdit provides a graphical interface for creating and editing macOS app icons — managing layers, groups, fills, effects, and compositing — and can compile and install icons directly into app bundles.

**Requires macOS 14.6 (Sonoma) or later.**

---

## Overview

ICEdit edits `.icon` bundles: directories containing an `icon.json` manifest and associated artwork files. Each icon is a hierarchy of groups, each containing one or more layers. The background fill, layer fills, blend modes, scale, shift, glass, and other compositing properties are all editable within the app.

ICEdit is built on the [OMC](https://abracode.com) framework with an ActionUI declarative UI engine. All editing logic runs as Python scripts in `Contents/Resources/Scripts/`, communicating with the UI in real time through the OMC dialog control tool.

---

## Requirements

| Requirement | Notes |
|---|---|
| macOS 14.6+ | Sonoma minimum |
| Icon Composer | Optional — required for icon preview rendering. Install with Xcode or from [Apple website](https://developer.apple.com/icon-composer/). |
| SF Symbols | Optional - installs latest SF Symbols fonts. Download from [Apple website](https://developer.apple.com/sf-symbols/) |
| Xcode | Required for **Export** and **Install in App** — provides `actool` for compiling `.icon` to `Assets.car` and `.icns`. |

---

### Preview

The center panel shows a composed layers preview rendered by `ictool` (from Icon Composer.app). The preview refreshes after every change. If Icon Composer is not installed, the preview area is blank.

### Open in Icon Composer

The **Open in Icon Composer** button opens the current icon's on-disk path in Icon Composer.app. If there are unsaved changes, ICEdit offers to save first (or open the stale on-disk version).

---

## SF Symbols

The **Add Layer with SF Symbol** menu item opens a SF Symbols picker window.

- **Filter** — Type to search by symbol name in real time.
- **Symbol list** — Displays all available SF Symbols (~7,000+).
- **Weight picker** — Selects rendering weight (Ultralight through Black). Defaults to Heavy, which works well as an icon layer.
- **Preview** — Renders the selected symbol at the chosen weight as an SVG.
- **Add Layer button** — Adds the symbol as a new layer in the current icon using `icedit add_svg --auto-scale`.

The SVG is rendered by the bundled `glyphsvg` helper (`Contents/Helpers/glyphsvg/`).

---

## Material Symbols

The **Add Layer with Material Symbol** menu item opens a Google Material Symbols picker window.

- **Filter** — Type to search by symbol name, tags, or category in real time. Search is ranked: exact word matches in the symbol name outrank partial matches, which outrank tag-only matches.
- **Symbol list** — Displays all available Material Symbols (~3,000+, Rounded style).
- **Weight picker** — Selects rendering weight (Thin through Black). Defaults to Bold, which renders well as an icon layer.
- **Fill toggle** — Optionally render the symbol in its filled variant.
- **Preview** — Renders the selected symbol at the chosen weight/fill as an SVG.
- **Add Layer button** — Adds the symbol as a new layer in the current icon using `icedit add_svg --auto-scale`.

The SVG is rendered by the bundled `glyphsvg` helper using the Material Symbols Rounded variable font.  
Browse Material Symbols repertoire here:   
https://fonts.google.com/icons?selected=Material+Symbols+Rounded

### Development Setup (not needed for distributed app)

Material Symbols data (font, codepoints, search metadata) is not committed to the repository due to file size. `update_icedit.sh` fetches it into `Contents/Helpers/glyphsvg/material/` along with the rest of the helper payload (see [Development Build](#development-build)):

| File | Description |
|---|---|
| `MaterialSymbolsRounded.ttf` | Variable font used by `glyphsvg` for SVG rendering |
| `MaterialSymbolsRounded.codepoints` | Name-to-glyph map; source of truth for the symbol list |
| `material_symbols_metadata.json` | Tags, synonyms, and categories for richer search |

Source: [google/material-design-icons](https://github.com/google/material-design-icons/tree/master/variablefont). Which style is embedded is read from `lib_material.py`, so changing it there changes what the script downloads - but change **both** `STYLE` (which names the files) and `MATERIAL_STYLE_ARG` (which the picker passes to `glyphsvg`). The script refuses to run if the two disagree, since that combination downloads a font nothing asks for and deletes the one in use.

---

## Symbol Fonts

The **Add Layer with Symbol Font...** menu item opens a picker over the icon fonts embedded in the bundle. Where the SF Symbols and Material Symbols pickers are each tied to one font, this one chooses its font at run time.

- **Font picker** - Selects among the embedded glyph sets. The list is built from what is actually in the bundle, so it never offers a font that is not there.
- **Filter** - Ranked search, the same ranking the Material Symbols picker uses: the exactly typed name first, then whole-word matches in the name, then partial matches, then tag-only matches. A font that publishes no tags degrades to name matching.
- **Style picker** - Selects among that font's faces. Disabled when the font has only one.
- **Preview** and **Add Layer** behave as in the other pickers, using `icedit add_svg --auto-scale`.

Three fonts are embedded:

| Set | Icons | Faces | License |
|---|---|---|---|
| Pictogrammers [Material Design Icons](https://pictogrammers.com/library/mdi/) | 7,188 | `regular` | Pictogrammers Free License (Apache 2.0 terms) |
| Microsoft [Fluent System Icons](https://github.com/microsoft/fluentui-system-icons) | 2,819 outlined + 2,859 filled | `regular`, `filled` | MIT |
| [Phosphor Icons](https://phosphoricons.com) | 1,512 in each of five | `thin`, `light`, `regular`, `bold`, `fill` | MIT |

All three are static fonts with no variation axes, which is why this picker offers a face list where the Material Symbols picker offers a weight slider and a fill toggle. Fluent draws filled and outlined as separate glyphs rather than as a fill axis, so its two variants are faces sharing a single font file.

**If you want a heavier stroke, use Phosphor.** App icons generally read better with more weight than a UI icon font's default, and Phosphor is the embedded family that has any: MDI ships one weight, Fluent two styles at one weight. Phosphor's five are five separate fonts, listed light to heavy, so the Style picker reads as a weight ramp. All five share the same 1,512 names, so changing weight keeps your selection. (Phosphor publishes a sixth, `duotone`, which is not bundled: its two tones are two separate glyphs, and the codepoint upstream publishes is the faint tint layer rather than the icon.)

Note that both sets include brand and company logos. A permissive font license covers the artwork's copyright and grants nothing on third-party trademarks - which matters here, because an app icon is trademark use.

### Development Setup (not needed for distributed app)

The fonts and their codepoint maps are not committed, for the same size reason as Material Symbols. `update_icedit.sh` provisions them into `Contents/Helpers/glyphsvg/sets/<name>/`, one directory per set, each holding a `glyphset.conf` manifest naming its font and codepoint tables.

Unlike the Material stage, this one needs the glyphsvg checkout: both fonts need their upstream data converted before `glyphsvg` can read it, and those converters live in the glyphsvg repo as `sets/<name>/download.py`. The script runs them and copies the result rather than duplicating the conversion. Use `--skip-sets` to leave the sets alone, `--refresh-sets` to re-fetch. Adding a font is a new `sets/<name>/` in the glyphsvg repo plus its name in `SET_NAMES` - no new dialog, scripts or commands.

---

## Export

**File > Export...** compiles the current icon using `actool` and writes the output to a folder you choose.

A subdirectory named `{icon-name}-Exported` (e.g., `MyIcon-Exported`) is created inside the chosen folder, containing:

| File | Description |
|---|---|
| `Assets.car` | Compiled asset catalog for embedding in a macOS app target |
| `{icon-name}.icns` | ICNS file for use as `CFBundleIconFile` |
| `partial-Info.plist` | Generated by `actool` — contains `CFBundleIconFile` and `CFBundleIconName` entries ready to merge into an app's `Info.plist` |

Requires Xcode for actool.

---

## Install in App

**File > Install in App...** compiles and installs the icon directly into a `.app` bundle you select.

Steps performed:
1. Validates the selected path is a `.app` bundle with `Contents/Resources/` and `Info.plist`.
2. Reads `CFBundleIconFile` from the app's `Info.plist` to identify any existing icon.
3. If `Assets.car` or the existing `.icns` are already present, shows a confirmation before overwriting.
4. Compiles the `.icon` with `actool` (macOS platform, mac target-device, 14.6 minimum deployment).
5. Copies `Assets.car` and `{icon-name}.icns` into `Contents/Resources/`.
6. If the old icon had a different name, the old `.icns` is removed.
7. Updates `CFBundleIconFile` and `CFBundleIconName` in the app's `Info.plist`.
8. Touches the `.app` bundle to invalidate the system icon cache.

Requires Xcode for actool.

---

## The .icon Format

An `.icon` bundle is a directory:

```
MyIcon.icon/
├── icon.json       # Icon definition
└── Assets/        # Layer source files (SVG, PNG, etc.)
```

ICEdit uses the bundled `icedit` CLI (`Contents/Helpers/icedit/`) for all mutations to `icon.json`. Edits are made to a working copy in `/tmp/icedit_work_{UUID}/`; the original file is not modified until an explicit save.

---

## Bundled Helpers

| Helper | Location | Purpose |
|---|---|---|
| [icedit](https://github.com/abra-code/icedit) | `Contents/Helpers/icedit/icedit` | CLI tool for reading and mutating `.icon` bundles |
| [glyphsvg](https://github.com/abra-code/glyphsvg) | `Contents/Helpers/glyphsvg/glyphsvg` | Renders SF Symbols, Material Symbols and any embedded glyph set to SVG at a given weight, face and size |

---

## Development Build

A fresh checkout does not contain a runnable app. Two scripts fill it in:

| Script | Provides |
|---|---|
| AppletBuilder (from [OMC](https://abracode.com)) | The OMC engine: `Contents/MacOS`, `Contents/Frameworks/Abracode.framework`, `Contents/Library/Python` |
| `./update_icedit.sh` | Everything app-specific: `Contents/Helpers` and the Material Symbols resources |

`update_icedit.sh` expects the [icedit](https://github.com/abra-code/icedit) and [glyphsvg](https://github.com/abra-code/glyphsvg) repositories checked out beside this one, and offers to clone them if they are missing (interactive runs only - without a terminal it fails with instructions instead). It deploys the `icedit` CLI, builds `glyphsvg` from source (universal arm64 + x86_64), regenerates the SF Symbols map (`sfmap.plist` and the sorted `names.txt`), provisions the Material Symbols font and metadata, code-signs the bundle with `codesign_applet.sh`, and then runs each deployed helper to prove it works.

```bash
./update_icedit.sh                    # the usual full pass
./update_icedit.sh --refresh-material # also re-fetch the Material Symbols resources
./update_icedit.sh --help             # all options
```

The Material Symbols resources are fetched only when the deployed set is missing or unusable, since they are ~22 MB; `--refresh-material` forces a fresh download from Google. When a fetch is needed and the sibling `glyphsvg` checkout already holds all three files for the current style, they are copied from there instead - so a payload left truncated by an interrupted run repairs itself with no network access. `--refresh-material` always goes to Google and never uses that local copy.

Everything is verified *before* the bundle is signed, including rendering a real glyph through the deployed `glyphsvg`, so a broken payload never gets sealed. Only the signature check and a re-launch of the signed helpers happen afterwards.

The script refuses to overwrite files under `Contents/Helpers/icedit` that differ from the `icedit` repository, since the bundle copy has carried fixes that were never upstreamed. Upstream the change, or pass `--force-icedit` to discard it.

Note that a normal run rewrites git-tracked files: `Contents/Helpers/glyphsvg/names.txt` and `sfmap.plist` every time, and `Contents/Helpers/icedit/*` under `--force-icedit`. Expect them in `git status` afterwards.

`thin_icedit.sh` is separate and not run by `update_icedit.sh`. It thins the AppletBuilder-provided Python runtime rather than this script's payload, and it has its own two-phase `plan` / `apply` protocol with a committed plan file. The two do connect in one place: the plan is derived from ICEdit's own imports, and the analyzer treats `Contents/Helpers/icedit/icedit` as an entry point and reads the `icon_editor` package beside it. If an `icedit` update pulls in a module the old package did not use, re-run `./thin_icedit.sh plan` before the next `apply`.

The test suite in `Tests/` covers the deployed payload from the app's side - the SF Symbols and Material Symbols pickers both assert their data is installed. Run it with `appletbuilder test ICEdit.app`.

---

## Architecture

ICEdit is an OMC 5.0 applet. The OMC framework handles the app lifecycle, menu commands, file/folder dialogs, and window management. The UI is defined declaratively in `ICEdit.json`, `SFSymbols.json`, `MaterialSymbols.json` and `SymbolFonts.json` (ActionUI format). All business logic runs as Python 3 scripts in `Contents/Resources/Scripts/`, with shared utilities in `lib_icedit.py` and, for the symbol pickers, `lib_glyphsearch.py` (name ranking, shared by all of them) and `lib_symbolfonts.py` (glyph set discovery).

Per-window state (working copy path, selected layer, dirty flag, original hash) is stored in the system pasteboard keyed by the window UUID, allowing child dialogs (the symbol pickers) to share context with the parent document window.
