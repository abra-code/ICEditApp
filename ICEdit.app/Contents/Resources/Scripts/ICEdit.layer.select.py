#!/usr/bin/env python3
"""Handle layer selection - populate settings pane with selected layer's properties."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.layer.select.py ===")

icon_path = get_icon_path()
if not icon_path:
    sys.exit(0)

# Table columns: 1=indent/group type, 2=layer type, 3=name, 4=visibility
col1 = get_table_value(ID_LAYER_LIST, 1).strip()
col2 = get_table_value(ID_LAYER_LIST, 2).strip()
row_type = col1 or col2 or TYPE_BG
layer_name = get_table_value(ID_LAYER_LIST, 3).strip()
log(f"selected: type='{row_type}' name='{layer_name}'")

if not layer_name:
    pb_set(PB_SELECTED_LAYER, "")
    pb_set(PB_SELECTED_TYPE, "")
    show_view(ID_BG_PANE, False)
    show_view(ID_LAYER_PANE, False)
    show_view(ID_GROUP_PANE, False)
    sys.exit(0)

pb_set(PB_SELECTED_LAYER, layer_name)
pb_set(PB_SELECTED_TYPE, row_type)

icon_data = load_icon_json(icon_path)
if not icon_data:
    sys.exit(1)

# Disable remove button for Background and Group (not deletable)
enable_view(ID_BTN_REMOVE, row_type == TYPE_LAYER)

if row_type == TYPE_BG:
    show_bg_pane()

    # Populate background fill values
    bg_type, bg_c1, bg_c2 = parse_fill(icon_data.get("fill"))
    set_value(ID_BG_FILL, bg_type)
    set_value(ID_BG_COLOR1_PICKER, color_to_hex(bg_c1))
    set_value(ID_BG_COLOR2_PICKER, color_to_hex(bg_c2) if bg_c2 else "")
    show_view(ID_BG_COLOR1, bg_type in ("solid", "auto-gradient", "gradient"))
    show_view(ID_BG_COLOR2, bg_type == "gradient")
    set_value(ID_BG_COLOR1_LABEL, "Start" if bg_type == "gradient" else "Color")
    set_value(ID_BG_COLOR2_LABEL, "Stop")

elif row_type == TYPE_GROUP:
    gi = group_index_from_list(icon_data, layer_name)
    show_group_pane()

    group = get_group(icon_data, gi)
    if group:
        # Name
        group_name = group.get("name", "")
        set_value(ID_GROUP_NAME, group_name)

        # Color section — opacity
        set_value(ID_GROUP_OPACITY, str(group.get("opacity", 1.0)))

        # Blend mode
        set_value(ID_GROUP_BLEND, group.get("blend-mode", "normal"))

        # Blur
        set_value(ID_GROUP_BLUR, str(group.get("blur-material", 0.0)))

        # Lighting — Icon Composer defaults to "individual" when absent
        set_value(ID_GROUP_LIGHTING, group.get("lighting", "individual"))

        # Specular — Icon Composer defaults to true when absent
        set_value(ID_GROUP_SPECULAR, "true" if group.get("specular", True) else "false")

        # Translucency
        translucency = group.get("translucency", {})
        if translucency.get("enabled"):
            set_value(ID_GROUP_TRANSLUCENCY, str(translucency.get("value", 1.0)))
        else:
            set_value(ID_GROUP_TRANSLUCENCY, "1.0")

        # Shadow
        shadow = group.get("shadow", {})
        if shadow:
            set_value(ID_GROUP_SHADOW, shadow.get("kind", "none"))
            set_value(ID_GROUP_SHADOW_OPACITY, str(shadow.get("opacity", 0.5)))
        else:
            set_value(ID_GROUP_SHADOW, "none")
            set_value(ID_GROUP_SHADOW_OPACITY, "0.5")

        # Visibility (via hidden-specializations)
        hidden = False
        for spec in group.get("hidden-specializations", []):
            if spec.get("idiom") == "square":
                hidden = spec.get("value", False)
                break
        set_value(ID_GROUP_VISIBLE, "false" if hidden else "true")

        # Scale/Shift (via position-specializations)
        pos = {}
        for spec in group.get("position-specializations", []):
            if spec.get("idiom") == "square":
                pos = spec.get("value", {})
                break
        set_value(ID_GROUP_SCALE, str(pos.get("scale", 1.0)))
        translation = pos.get("translation-in-points", [0, 0])
        set_value(ID_GROUP_SHIFT_X, str(int(translation[0])) if len(translation) > 0 else "0")
        set_value(ID_GROUP_SHIFT_Y, str(int(translation[1])) if len(translation) > 1 else "0")

elif row_type == TYPE_LAYER:
    result = find_layer(icon_data, layer_name)
    if not result:
        show_view(ID_BG_PANE, False)
        show_view(ID_LAYER_PANE, False)
        show_view(ID_GROUP_PANE, False)
        sys.exit(0)

    group_idx, layer_idx, layer = result
    show_layer_pane()

    # Name
    set_value(ID_LAYER_NAME, layer.get("name", ""))

    # Fill — Icon Composer defaults to "automatic" when fill key is absent
    fill_type, c1, c2 = parse_fill(layer.get("fill"))
    if "fill" not in layer:
        fill_type = "automatic"
    set_value(ID_LAYER_FILL, fill_type)
    set_value(ID_LAYER_COLOR1_PICKER, color_to_hex(c1))
    set_value(ID_LAYER_COLOR2_PICKER, color_to_hex(c2) if c2 else "")
    show_view(ID_LAYER_COLOR1, fill_type in ("solid", "auto-gradient", "gradient"))
    show_view(ID_LAYER_COLOR2, fill_type == "gradient")
    set_value(ID_LAYER_COLOR1_LABEL, "Start" if fill_type == "gradient" else "Color")
    set_value(ID_LAYER_COLOR2_LABEL, "Stop")

    # Position — check both "position" and "position-specializations"
    pos = layer.get("position", {})
    if not pos:
        specs = layer.get("position-specializations", [])
        for spec in specs:
            if spec.get("idiom") == "square":
                pos = spec.get("value", {})
                break
        if not pos and specs:
            pos = specs[0].get("value", {})
    set_value(ID_LAYER_SCALE, str(pos.get("scale", 1.0)))
    translation = pos.get("translation-in-points", [0, 0])
    set_value(ID_LAYER_SHIFT_X, str(int(translation[0])) if len(translation) > 0 else "0")
    set_value(ID_LAYER_SHIFT_Y, str(int(translation[1])) if len(translation) > 1 else "0")

    # Visible
    hidden = layer.get("hidden", False)
    set_value(ID_LAYER_VISIBLE, "false" if hidden else "true")

    # Glass — Icon Composer defaults to true when absent
    glass = layer.get("glass", True)
    set_value(ID_LAYER_GLASS, "true" if glass else "false")

    # Blend mode
    blend = layer.get("blend-mode", "normal")
    set_value(ID_LAYER_BLEND, blend)

log("=== ICEdit.layer.select.py done ===")
