# selection_data_foldable.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2025 Charlie Whitfield
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
class_name IVSelectionDataFoldable
extends FoldableContainer

## GUI widget that displays formatted selection data in a foldable container.
## Optionally displays wiki links for row labels and/or values.
##
## This node expects to find content, "enable" properties, and an [IVSelectionManager]
## in ancestor node(s):[br][br]
##
## [code]selection_data_content: Dictionary[/code] (required). An ancestor node
## must have this property with a dictionary, and the dictionary must have a key
## matching this node's [member Node.name]. The dictionary value defines this
## foldable's content. See [IVSelectionData] for content format and examples.[br][br]
##
## [code]selection_data_valid_tests: Dictionary[/code] (optional). An ancestor
## node may have this property with a dictionary, which may have a key matching
## this node's [member Node.name]. If the dictionary and key exists, the value
## is expected to be a Callable that returns a "valid" result (bool) for this
## foldable. This foldable is valid by default if the dictionary or key does not
## exist. If not valid, the foldable and its title are hidden. See
## [IVSelectionData] for the Callable signature and examples.[br][br]
##
## [code]enable_selection_data_label_links: bool[/code]. If property exists in
## an ancestor and is true, row labels can be wiki page links. This also
## requires [IVWikiManager] to exist (it does not by default) and
## [method IVWikiManager.has_page] to evaluate true for the row label.[br][br]
##
## [code]enable_selection_data_value_links: bool[/code]. If property exists in
## an ancestor and is true, row values can be wiki page links. This also
## requires [IVWikiManager] to exist (it does not by default) and
## [method IVWikiManager.has_page] to evaluate true for the row value. The
## test only happens if row value is type StringName (not String!).[br][br]
##
## [code]selection_manager: IVSelectionManager[/code] (required). An ancestor
## node must have this property with an [IVSelectionManager].[br][br]
##
## [IVSelectionDataFoldable] instances can be nested or include other Controls
## as children with this scene's GridContainer child. If >1 Control children
## exist, they all will be gathered into a VBoxContainer automatically with
## this node's $DataGrid as first child.


## Minimum label width in en units (an "n" character or half the font size).
@export var min_labels_en_width := 22.0
## Minimum value width in en units (an "n" character or half the font size).
@export var min_values_en_width := 0.0
## Set greater than 0.0 for time interval updates in seconds.
@export var update_time_interval := 0.0
## Used only if [member update_time_interval] > 0.0. Sets [member Timer.ignore_time_scale].
@export var update_ignore_time_scale := true


var _selection_manager: IVSelectionManager
var _wiki_manager: IVWikiManager
var _use_label_links := false
var _use_value_links := false
var _enable_precisions := false
var _dirty := true
var _content: Array[Array]
var _valid_test: Callable
var _timer: Timer
var _added_rows := 0
var _en_width: float


@onready var _data_grid: GridContainer = $DataGrid # may move to VBoxContainer after this


func _enter_tree() -> void:
	get_parent_control().visibility_changed.connect(_on_parent_visibility_changed)


func _exit_tree() -> void:
	get_parent_control().visibility_changed.disconnect(_on_parent_visibility_changed)


func _ready() -> void:
	if update_time_interval > 0.0:
		_timer = Timer.new()
		add_child(_timer)
		_timer.timeout.connect(_update_selection)
		_timer.wait_time = update_time_interval
		_timer.ignore_time_scale = update_ignore_time_scale
	IVSettingsManager.changed.connect(_settings_listener)
	_arrange_child_controls()
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)
	IVWidgets.connect_selection_manager(self, &"_on_selection_manager_changed",
			[&"selection_changed", &"_update_selection"])


func _arrange_child_controls() -> void:
	# If >1 child Controls, put all of them in a VBoxContainer.
	var child_controls: Array[Control] = []
	for child in get_children():
		if child is Control:
			child_controls.append(child)
	if child_controls.size() < 2: # only $Grid
		return
	var vbox := VBoxContainer.new()
	add_child(vbox)
	for control in child_controls:
		remove_child(control)
		vbox.add_child(control)


func _configure_after_core_inited(_dummy := false) -> void:
	_wiki_manager = IVGlobal.program.get(&"WikiManager")
	if _wiki_manager:
		_use_label_links = IVUtils.get_tree_bool(self, &"enable_selection_data_label_links")
		_use_value_links = IVUtils.get_tree_bool(self, &"enable_selection_data_value_links")
	_enable_precisions = IVCoreSettings.enable_precisions
	_get_content()
	_reset_column_widths()


func _on_selection_manager_changed(selection_manager: IVSelectionManager) -> void:
	_selection_manager = selection_manager
	if _selection_manager:
		_update_selection()


func _get_content() -> void:
	var selection_data_content := IVUtils.get_tree_dictionary(self, &"selection_data_content")
	assert(selection_data_content.has(name),
			"Expected this node's name as key in ancestor Dictionary 'selection_data_content'")
	_content = selection_data_content[name]
	var selection_data_valid_tests := IVUtils.get_tree_dictionary(self, &"selection_data_valid_tests")
	if selection_data_valid_tests.has(name):
		_valid_test = selection_data_valid_tests[name]


func _on_parent_visibility_changed() -> void:
	if _dirty:
		_update_selection()


func _update_selection(_dummy := false) -> void:
	# This FoldableContainer will be hidden if all content rows are null or ""
	# (i.e., its title will be hidden). We need update even if folded so we can
	# determine visibility of the title. We can deffer update if this part of
	# the GUI tree is currently hidden.
	if !_selection_manager or !get_parent_control().is_visible_in_tree():
		_dirty = true
		return
	_dirty = false
	var selection := _selection_manager.get_selection()
	if !selection:
		hide()
		return
	if _valid_test and !_valid_test.call(selection):
		hide()
		return
	var grid_row := 0
	var content_row := 0
	var content_size := _content.size()
	while content_row < content_size:
		var row_content := _content[content_row]
		
		# hide callable?
		if row_content.size() > 3:
			var hide_callable: Callable = row_content[3]
			if hide_callable.call(selection):
				content_row += 1
				continue
		
		var value_path: String = row_content[1]
		var value: Variant = IVUtils.get_path_result(selection, value_path)
		if value == null or is_same(value, NAN):
			content_row += 1
			continue
		
		var value_text: String
		var value_key := &""
		if row_content.size() < 3:
			# No format callable. Convert it to string, whatever it is.
			value_text = str(value)
			if value is StringName:
				value_key = value
		elif value is float:
			# all format callables expect internal_precision
			var format: Callable = row_content[2]
			var internal_precision := -1
			if _enable_precisions:
				internal_precision = selection.get_float_precision(value_path)
			value_text = format.call(selection, value, internal_precision)
		else:
			var format: Callable = row_content[2]
			var formatted_value: Variant = format.call(selection, value)
			if formatted_value is Array:
				# Set full row row_content here, not below!
				var list_array: Array[String] = formatted_value
				_set_row(grid_row, list_array[0], list_array[1], &"")
				grid_row += 1
				content_row += 1
				continue
			elif formatted_value is StringName:
				value_text = formatted_value
				value_key = formatted_value
			else:
				value_text = str(formatted_value)
		
		if value_text == "":
			content_row += 1
			continue
		
		# if here, row_content[0] must have row label or row label callable
		var row_label: StringName
		if row_content[0] is Callable:
			var label_callable: Callable = row_content[0]
			row_label = label_callable.call(selection)
		else:
			row_label = row_content[0]
		_set_row(grid_row, row_label, value_text, value_key)
		grid_row += 1
		content_row += 1
	
	# hide this control (including title) if no applicable data
	if grid_row == 0:
		hide()
		return
	show()
	
	# hide unused rows
	while grid_row < _added_rows:
		var label: Control = _data_grid.get_child(grid_row * 2)
		label.hide()
		var value: Control = _data_grid.get_child(grid_row * 2 + 1)
		value.hide()
		grid_row += 1
	
	# restart timer if present
	if _timer:
		_timer.start()


func _set_row(row: int, row_label: StringName, value_text: String, value_key: StringName) -> void:
	# row_label may or may not be a translation and/or wiki key.
	# value_text is already translated.
	# value_key is the value key (if applicable) or &"".
	var is_new_row := false
	if row == _added_rows:
		is_new_row = true
		_added_rows += 1
	
	if _use_label_links:
		var link_label: IVLinkLabel
		if is_new_row:
			link_label = IVLinkLabel.create("")
			_data_grid.add_child(link_label)
		else:
			link_label = _data_grid.get_child(row * 2)
			link_label.show()
		if _wiki_manager.has_page(row_label):
			link_label.parse_bbcode('[url="%s"]%s[/url]' % [row_label, tr(row_label)])
		else:
			link_label.parse_bbcode(tr(row_label))
	else:
		var label: Label
		if is_new_row:
			label = Label.new()
			_data_grid.add_child(label)
		else:
			label = _data_grid.get_child(row * 2)
			label.show()
		label.text = row_label
	
	if _use_value_links:
		var link_value: IVLinkLabel
		if is_new_row:
			link_value = IVLinkLabel.create("")
			_data_grid.add_child(link_value)
		else:
			link_value = _data_grid.get_child(row * 2 + 1)
			link_value.show()
		if !value_key:
			link_value.parse_bbcode(value_text)
		elif _wiki_manager.has_page(value_key):
			link_value.parse_bbcode('[url="%s"]%s[/url]' % [value_text, tr(value_key)])
		else:
			link_value.parse_bbcode(tr(value_key))
	else:
		var value: Label
		if is_new_row:
			value = Label.new()
			_data_grid.add_child(value)
		else:
			value = _data_grid.get_child(row * 2 + 1)
			value.show()
		value.text = value_text
	
	if is_new_row and _added_rows == 1:
		_set_top_row_cell_widths()


func _reset_column_widths() -> void:
	_en_width = get_theme_font_size(&"normal", &"Label") * 0.5
	if _added_rows > 0:
		_set_top_row_cell_widths()


func _set_top_row_cell_widths() -> void:
	var label0: Control = _data_grid.get_child(0)
	label0.custom_minimum_size.x = _en_width * min_labels_en_width
	var value0: Control = _data_grid.get_child(1)
	value0.custom_minimum_size.x = _en_width * min_values_en_width


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"gui_size":
		_reset_column_widths.call_deferred() # after font size change
