#!/usr/bin/env python3
"""Apply settings changes to the icon and re-render preview."""

import os
import sys

sys.path.insert(0, os.path.join(os.environ.get("OMC_APP_BUNDLE_PATH", ""),
                                "Contents/Resources/Scripts"))
from lib_icedit import *

log("=== ICEdit.settings.apply.py ===")

icon_path = get_icon_path()
if not icon_path:
    sys.exit(0)

icon_data = load_icon_json(icon_path)
if not icon_data:
    sys.exit(1)

changed = False
layer_name = get_selected_layer()
is_bg = is_bg_selected()
is_group = is_group_selected()
log(f"layer_name={layer_name}, is_bg={is_bg}, is_group={is_group}")

# --- Background fill ---
if is_bg:
    bg_fill_type = get_env_value(ID_BG_FILL)
    bg_color1 = get_env_value(ID_BG_COLOR1_PICKER)
    bg_color2 = get_env_value(ID_BG_COLOR2_PICKER)
    log(f"BG ColorPicker values: fill={bg_fill_type}, color1='{bg_color1}', color2='{bg_color2}'")

    old_type, old_c1, old_c2 = parse_fill(icon_data.get("fill"))

    needs_update = False
    if bg_fill_type in ("none", "automatic"):
        needs_update = (old_type != bg_fill_type)
    elif bg_fill_type in ("solid", "auto-gradient") and bg_color1:
        needs_update = (bg_fill_type != old_type or bg_color1 != color_to_hex(old_c1))
    elif bg_fill_type == "gradient" and bg_color1 and bg_color2:
        needs_update = (bg_fill_type != old_type
                        or bg_color1 != color_to_hex(old_c1)
                        or bg_color2 != color_to_hex(old_c2 or ""))

    if needs_update:
        cmd = [icon_path, "Background", bg_fill_type]
        if bg_fill_type in ("solid", "auto-gradient"):
            cmd.append(bg_color1)
        elif bg_fill_type == "gradient":
            cmd.extend([bg_color1, "--color2", bg_color2])
        run_icedit("change_fill", *cmd)
        changed = True

    show_view(ID_BG_COLOR1, bg_fill_type in ("solid", "auto-gradient", "gradient"))
    show_view(ID_BG_COLOR2, bg_fill_type == "gradient")
    set_value(ID_BG_COLOR1_LABEL, "Start" if bg_fill_type == "gradient" else "Color")
    set_value(ID_BG_COLOR2_LABEL, "Stop")

# --- Layer settings ---
if layer_name and not is_bg and not is_group:
    result = find_layer(icon_data, layer_name)
    if result:
        group_idx, layer_idx, layer = result
        # Convert to 1-based for icedit CLI
        gi = group_idx + 1
        li = layer_idx + 1

        # Name (rename)
        new_layer_name = get_env_value(ID_LAYER_NAME)
        old_layer_name = layer.get("name", "")
        if new_layer_name and new_layer_name != old_layer_name:
            run_icedit("rename_layer", icon_path, str(li), new_layer_name,
                       "--group", str(gi))
            changed = True
            # Update pasteboard and refresh list
            pb_set(PB_SELECTED_LAYER, new_layer_name)
            icon_data = load_icon_json(icon_path)
            populate_layer_list(icon_data)
            # Re-find layer with new name for remaining settings
            result = find_layer(icon_data, new_layer_name)
            if result:
                group_idx, layer_idx, layer = result
                gi = group_idx + 1
                li = layer_idx + 1

        # Fill
        layer_fill_type = get_env_value(ID_LAYER_FILL)
        layer_color1 = get_env_value(ID_LAYER_COLOR1_PICKER)
        layer_color2 = get_env_value(ID_LAYER_COLOR2_PICKER)
        log(f"Layer ColorPicker values: fill={layer_fill_type}, color1='{layer_color1}', color2='{layer_color2}'")

        old_type, old_c1, old_c2 = parse_fill(layer.get("fill"))
        if "fill" not in layer:
            old_type = "automatic"

        fill_changed = False
        if layer_fill_type in ("none", "automatic"):
            fill_changed = (old_type != layer_fill_type)
        elif layer_fill_type in ("solid", "auto-gradient") and layer_color1:
            fill_changed = (layer_fill_type != old_type or layer_color1 != color_to_hex(old_c1))
        elif layer_fill_type == "gradient" and layer_color1 and layer_color2:
            fill_changed = (layer_fill_type != old_type
                            or layer_color1 != color_to_hex(old_c1)
                            or layer_color2 != color_to_hex(old_c2 or ""))

        if fill_changed:
            cmd = [icon_path, str(li), layer_fill_type, "--group", str(gi)]
            if layer_fill_type in ("solid", "auto-gradient"):
                cmd.insert(3, layer_color1)
            elif layer_fill_type == "gradient":
                cmd.insert(3, layer_color1)
                cmd.extend(["--color2", layer_color2])
            run_icedit("change_fill", *cmd)
            changed = True

        show_view(ID_LAYER_COLOR1, layer_fill_type in ("solid", "auto-gradient", "gradient"))
        show_view(ID_LAYER_COLOR2, layer_fill_type == "gradient")
        set_value(ID_LAYER_COLOR1_LABEL, "Start" if layer_fill_type == "gradient" else "Color")
        set_value(ID_LAYER_COLOR2_LABEL, "Stop")

        # Scale and shift
        try:
            scale = float(get_env_value(ID_LAYER_SCALE) or "1.0")
            scale = max(0.01, scale)
        except ValueError:
            scale = 1.0
        try:
            shift_x = int(float(get_env_value(ID_LAYER_SHIFT_X) or "0"))
        except ValueError:
            shift_x = 0
        try:
            shift_y = int(float(get_env_value(ID_LAYER_SHIFT_Y) or "0"))
        except ValueError:
            shift_y = 0

        pos = layer.get("position", {})
        if "position-specializations" in layer:
            specs = layer["position-specializations"]
            for spec in specs:
                if spec.get("idiom") == "square":
                    pos = spec.get("value", {})
                    break
            else:
                if specs:
                    pos = specs[0].get("value", {})

        old_scale = pos.get("scale", 1.0)
        old_translation = pos.get("translation-in-points", [0, 0])
        if scale != old_scale or [shift_x, shift_y] != old_translation:
            run_icedit("scale_shift", icon_path, str(li), scale, shift_x, shift_y,
                       "--group", str(gi))
            changed = True

        # Visible
        visible_val = get_env_value(ID_LAYER_VISIBLE)
        hidden = visible_val.lower() not in ("true", "1", "yes")
        if hidden != layer.get("hidden", False):
            run_icedit("hide", icon_path, str(li), "true" if hidden else "false",
                       "--group", str(gi))
            changed = True

        # Glass
        glass_val = get_env_value(ID_LAYER_GLASS)
        log(f"Glass: env='{glass_val}' layer.glass={layer.get('glass', False)}")
        glass = glass_val.lower() in ("true", "1", "yes")
        if glass != layer.get("glass", True):
            run_icedit("set_glass", icon_path, str(li), "true" if glass else "false",
                       "--group", str(gi))
            changed = True

        # Blend mode
        blend = get_env_value(ID_LAYER_BLEND) or "normal"
        old_blend = layer.get("blend-mode", "normal")
        if blend != old_blend:
            run_icedit("set_blend", icon_path, str(li), blend, "--group", str(gi))
            changed = True

# --- Group settings ---
if is_group:
    gi = group_index_from_list(icon_data, layer_name)
    group = get_group(icon_data, gi)

    if group:
        # Name (rename)
        new_name = get_env_value(ID_GROUP_NAME)
        old_name = group.get("name", "")
        if new_name != old_name:
            run_icedit("rename_group", icon_path, gi, new_name)
            changed = True
            # Update the layer list to reflect new name
            icon_data = load_icon_json(icon_path)
            populate_layer_list(icon_data)
            # Update pasteboard with new display name
            pb_set(PB_SELECTED_LAYER, new_name or "Group")

        # Opacity (Color section)
        try:
            opacity = float(get_env_value(ID_GROUP_OPACITY) or "1.0")
            opacity = max(0.0, min(1.0, opacity))
        except ValueError:
            opacity = 1.0
        if opacity != group.get("opacity", 1.0):
            run_icedit("set_group_opacity", icon_path, gi, opacity)
            changed = True

        # Blend mode
        blend = get_env_value(ID_GROUP_BLEND) or "normal"
        old_blend = group.get("blend-mode", "normal")
        if blend != old_blend:
            run_icedit("set_group_blend", icon_path, gi, blend)
            changed = True

        # Blur
        try:
            blur = float(get_env_value(ID_GROUP_BLUR) or "0.0")
            blur = max(0.0, min(1.0, blur))
        except ValueError:
            blur = 0.0
        if blur != group.get("blur-material", 0.0):
            run_icedit("set_group_blur", icon_path, gi, blur)
            changed = True

        # Lighting — default is "individual" when absent
        lighting = get_env_value(ID_GROUP_LIGHTING) or "individual"
        old_lighting = group.get("lighting", "individual")
        if lighting != old_lighting:
            run_icedit("set_group_lighting", icon_path, gi, lighting)
            changed = True

        # Specular
        specular_val = get_env_value(ID_GROUP_SPECULAR)
        specular = specular_val.lower() in ("true", "1", "yes")
        if specular != group.get("specular", True):
            run_icedit("set_group_specular", icon_path, gi,
                       "true" if specular else "false")
            changed = True

        # Translucency
        try:
            translucency_val = float(get_env_value(ID_GROUP_TRANSLUCENCY) or "1.0")
            translucency_val = max(0.0, min(1.0, translucency_val))
        except ValueError:
            translucency_val = 1.0

        current_translucency = group.get("translucency", {})
        current_value = current_translucency.get("value", 1.0) if current_translucency.get("enabled") else 1.0

        if translucency_val != current_value:
            run_icedit("change_translucency", icon_path, gi, translucency_val)
            changed = True

        # Shadow
        shadow_kind = get_env_value(ID_GROUP_SHADOW)
        try:
            shadow_opacity = float(get_env_value(ID_GROUP_SHADOW_OPACITY) or "0.5")
            shadow_opacity = max(0.0, min(1.0, shadow_opacity))
        except ValueError:
            shadow_opacity = 0.5
        log(f"Shadow values: kind={shadow_kind}, opacity={shadow_opacity}")

        old_shadow = group.get("shadow", {})
        new_shadow = {"kind": shadow_kind, "opacity": shadow_opacity}

        if new_shadow != old_shadow:
            run_icedit("set_shadow", icon_path, gi, shadow_kind, shadow_opacity)
            changed = True

        # Visibility (group uses hidden-specializations)
        visible_val = get_env_value(ID_GROUP_VISIBLE)
        hidden = visible_val.lower() not in ("true", "1", "yes")
        old_hidden = False
        for spec in group.get("hidden-specializations", []):
            if spec.get("idiom") == "square":
                old_hidden = spec.get("value", False)
                break
        if hidden != old_hidden:
            run_icedit("hide_group", icon_path, gi, "true" if hidden else "false")
            changed = True

        # Scale/Shift (group uses position-specializations)
        try:
            g_scale = float(get_env_value(ID_GROUP_SCALE) or "1.0")
            g_scale = max(0.01, g_scale)
        except ValueError:
            g_scale = 1.0
        try:
            g_shift_x = int(float(get_env_value(ID_GROUP_SHIFT_X) or "0"))
        except ValueError:
            g_shift_x = 0
        try:
            g_shift_y = int(float(get_env_value(ID_GROUP_SHIFT_Y) or "0"))
        except ValueError:
            g_shift_y = 0

        old_pos = {}
        for spec in group.get("position-specializations", []):
            if spec.get("idiom") == "square":
                old_pos = spec.get("value", {})
                break
        old_g_scale = old_pos.get("scale", 1.0)
        old_g_translation = old_pos.get("translation-in-points", [0, 0])

        if g_scale != old_g_scale or [g_shift_x, g_shift_y] != old_g_translation:
            run_icedit("scale_shift_group", icon_path, gi, g_scale, g_shift_x, g_shift_y)
            changed = True

# Re-render if anything changed
if changed:
    mark_dirty()
    result = render_preview(icon_path)
    if result:
        set_status("Settings applied")
    # render_preview already sets status on failure
