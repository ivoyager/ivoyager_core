# huds_hbox.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2019-2026 Charlie Whitfield
# I, Voyager is a registered trademark of Charlie Whitfield in the US
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
class_name IVHUDsHBox
extends HBoxContainer

## An HBoxContainer widget containing a row of HUDs widgets for a class of
## [IVBody] or [IVSmallBodiesGroup]
##
## Specify either [member body_flags] or [member sbg_aliases], not both.[br][br]
##
## The row is an optional left-aligned [Label] followed by a right-aligned control
## block. The block holds visibility checkboxes (names/symbols/orbits for a body,
## or symbols/orbits for an SBG) then an [IVSymbolPickerButton] and a shared
## [IVHUDsColorPickerButton] (one color for symbol, name and orbit).

const SCENE := "res://addons/ivoyager_core/ui_widgets/huds_hbox.tscn"

## Row label text. If not set, skip label.
@export var label_text := &""
## Use [IVLinkLabel] instead of a [Label] using the specified [member
## label_text] as text and this value as the wiki page title key. If set, two other
## conditions must be met to have link lables: 1) [IVWikiManager] must
## be present (not default!). 2) [member require_links_enabled] is set to
## false OR an ancestor node has property "enable_huds_hbox_links" == true.
@export var link_label_key := &""
## If true (default), require ancestor property "enable_huds_hbox_links" == true
## to use IVLinkLabel. See [member link_label_key].
@export var require_links_enabled := true
## Specify a class of body by [enum IVBody.BodyFlags]. In most cases this should
## be one of the exclusive flags defined in data table "visual_groups.tsv"
## field "body_flags" (only these have default colors and visibilities).
## If not 0, [member sbg_aliases] must be empty.
@export var body_flags := 0
## Specify a class of small bodies by listing aliases matching
## [member IVSmallBodiesGroup.sbg_alias] (e.g., ["JT4", "JT5"] for both Trojan
## groups). If not empty, [member body_flags] must be 0.
@export var sbg_aliases: Array[StringName] = []
## Add an orbit-visibility [IVHUDsCheckBox]. Set false for bodies with no orbit
## (e.g., the Sun).
@export var orbits := true


var _enable_links := false


## Creates a new [IVHUDsHBox] instance using specified parameters.
@warning_ignore("shadowed_variable")
static func create(
		label_text := &"",
		link_label_key := &"",
		require_links_enabled := true,
		body_flags := 0,
		sbg_aliases: Array[StringName] = [],
		orbits := true
		) -> IVHUDsHBox:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	var hbox: IVHUDsHBox = (load(SCENE) as PackedScene).instantiate()
	hbox.label_text = label_text
	hbox.link_label_key = link_label_key
	hbox.require_links_enabled = require_links_enabled
	hbox.body_flags = body_flags
	hbox.sbg_aliases = sbg_aliases
	hbox.orbits = orbits
	return hbox


func _ready() -> void:
	assert((!body_flags) != (!sbg_aliases), "Set either 'body_flags' or 'sbg_aliases', not both")
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _configure_after_core_inited() -> void:

	if IVGlobal.program.has(&"WikiManager"):
		_enable_links = (!require_links_enabled or
				IVTree.get_ancestor_bool(self, &"enable_huds_hbox_links"))

	# label
	if label_text:
		if _enable_links and link_label_key:
			var bbcode := "[url=%s]%s[/url]" % [link_label_key, tr(label_text)]
			var link_label := IVLinkLabel.create(bbcode)
			add_child(link_label)
		else:
			var label := Label.new()
			label.text = label_text
			add_child(label)

	# control block (right): visibility checkboxes, then symbol & color pickers
	var control_block := HBoxContainer.new()
	control_block.size_flags_horizontal = SIZE_EXPAND_FILL
	control_block.alignment = ALIGNMENT_END
	control_block.custom_minimum_size = Vector2(155, 0)
	if body_flags:
		_add_checkbox(control_block, IVHUDsCheckBox.HUDsType.NAMES, "HINT_SHOW_NAME")
	_add_checkbox(control_block, IVHUDsCheckBox.HUDsType.SYMBOLS, "HINT_SHOW_SYMBOL")
	if orbits:
		_add_checkbox(control_block, IVHUDsCheckBox.HUDsType.ORBITS, "HINT_SHOW_ORBIT")
	else:
		_add_checkbox_spacer(control_block) # reserve orbit slot to keep rows aligned
	var symbol_picker := IVSymbolPickerButton.create(body_flags, sbg_aliases)
	symbol_picker.tooltip_text = "HINT_SYMBOL_PICKER"
	control_block.add_child(symbol_picker)
	var color_picker := IVHUDsColorPickerButton.create(body_flags, sbg_aliases)
	color_picker.tooltip_text = "HINT_COLOR_PICKER"
	control_block.add_child(color_picker)
	add_child(control_block)


func _add_checkbox(container: HBoxContainer, hud_type: IVHUDsCheckBox.HUDsType, hint: String) -> void:
	var checkbox := IVHUDsCheckBox.create(hud_type, body_flags, sbg_aliases)
	checkbox.tooltip_text = hint
	container.add_child(checkbox)


func _add_checkbox_spacer(container: HBoxContainer) -> void:
	# A row without an orbit checkbox (e.g., the Sun) still reserves that slot so its
	# other checkboxes stay aligned with sibling rows. An inert, invisible CheckBox
	# matches the checkbox width exactly under any theme or GUI scale.
	var spacer := CheckBox.new()
	spacer.modulate = Color(1, 1, 1, 0)
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	spacer.focus_mode = FOCUS_NONE
	container.add_child(spacer)
