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
## Optionally includes wiki links.
##
## This node expects to find its content in an ancestor Control similar to
## [IVSelectionData]. Any ancestor Control can be specified as content holder
## by setting [member content_control_match_pattern]. The content Control must
## have a dictionary with name [param selection_content] with a key matching
## this node's [param name]. The content Control may optionally have a
## dictionary named [param valid_tests] with (optionally) this node's name as
## key. See [IVSelectionData] for format details and example dictionaries.[br][br]
##
## This node needs to connect to an [IVSelectionManager]. At sim start it will
## attempt to find one by searching up the ancestry tree for a Control with
## property [param selection_manager].[br][br]
##
## [IVSelectionDataFoldable] instances can be nested or include other Controls
## as children with this scene's GridContainer child. If >1 Control children
## exist, they will be gathered into a VBoxContainer automatically at _ready().



## If true, row labels will be wiki links if [method IVWikiManager.has_page]
## evaluates as true. Note: this property does nothing if a WikiManager is not
## present.
@export var wiki_labels := false
## If true, row values will be wiki links if [method IVWikiManager.has_page]
## evaluates as true. Note: this property does nothing if a WikiManager is not
## present.
@export var wiki_values := false
## Set > 0.0 for periodic updates in seconds.
@export var update_interval := 0.0
@export var update_ignore_time_scale := true

## Set min label width in units of the font 'EN QUAD' size
@export var min_labels_en_width := 22.0 ## Width in units of the 'EN QUAD' character.
@export var min_values_en_width := 0.0 ## Width in units of the 'EN QUAD' character.

@export var content_control_match_pattern := "SelectionData"


var _valid_test: Callable
var _content: Array[Array]
var _selection_manager: IVSelectionManager
var _timer: Timer
var _added_rows := 0
var _dirty := false
var _en_width: float
var _content_control: Control
var _is_content_control_visible: bool


@onready var _grid: GridContainer = $Grid # may move to VBoxContainer after this
@onready var _wiki_manager: IVWikiManager = IVGlobal.program.get(&"WikiManager")
@onready var _enable_precisions := IVCoreSettings.enable_precisions




func _ready() -> void:
	if update_interval > 0.0:
		_timer = Timer.new()
		add_child(_timer)
		_timer.timeout.connect(_update_selection)
		_timer.wait_time = update_interval
		_timer.ignore_time_scale = update_ignore_time_scale
	IVGlobal.about_to_start_simulator.connect(_configure)
	if IVGlobal.state[&"is_started_or_about_to_start"]:
		_configure()
	IVGlobal.update_gui_requested.connect(_update_selection)
	_arrange_child_controls()
	IVGlobal.setting_changed.connect(_settings_listener)
	IVGlobal.about_to_free_procedural_nodes.connect(_clear_procedural)


func _arrange_child_controls() -> void:
	# if >1 child Controls, put them in a VBoxContainer
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


func _configure(_dummy := false) -> void:
	_reset_column_widths()
	_connect_content_control()
	_connect_selection_manager()


func _connect_content_control() -> void:
	if _content_control:
		return
	_content_control = find_parent(content_control_match_pattern) as Control
	assert(_content_control, "Expected an ancestor Control name matching pattern %s" %
			content_control_match_pattern)
	_content_control.visibility_changed.connect(_on_content_control_visibility_changed)
	_is_content_control_visible = _content_control.is_visible_in_tree()
	var selection_content: Dictionary[StringName, Array] = _content_control.get(&"selection_content")
	assert(selection_content.has(name), "Expected this node's name as key in 'selection_content'")
	_content = selection_content[name]
	if &"valid_tests" in _content_control:
		var valid_tests: Dictionary[StringName, Callable] = _content_control.get(&"valid_tests")
		if valid_tests.has(name):
			_valid_test = valid_tests[name]


func _connect_selection_manager() -> void:
	if _selection_manager:
		_selection_manager.selection_changed.disconnect(_update_selection)
	_selection_manager = IVSelectionManager.get_selection_manager(self)
	assert(_selection_manager, "Did not find valid 'selection_manager' above this node")
	_selection_manager.selection_changed.connect(_update_selection)


func _clear_procedural() -> void:
	if _selection_manager:
		_selection_manager.selection_changed.disconnect(_update_selection)
		_selection_manager = null


func _on_content_control_visibility_changed() -> void:
	_is_content_control_visible = _content_control.is_visible_in_tree()
	if _dirty and _is_content_control_visible:
		_update_selection()


func _update_selection(_dummy := false) -> void:
	# This FoldableContainer will be hidden if all content rows are null/""
	# (i.e., its title will be hidden). We need update even if folded so we can
	# determine visibility of the title. We can deffer update if this part of
	# the GUI tree is currently hidden.
	if !_is_content_control_visible:
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
		var label: Control = _grid.get_child(grid_row * 2)
		label.hide()
		var value: Control = _grid.get_child(grid_row * 2 + 1)
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
	
	if wiki_labels and _wiki_manager:
		var rtlabel: RichTextLabel
		if is_new_row:
			rtlabel = RichTextLabel.new()
			rtlabel.autowrap_mode = TextServer.AUTOWRAP_OFF
			rtlabel.scroll_active = false
			rtlabel.fit_content = true
			rtlabel.bbcode_enabled = true
			rtlabel.meta_clicked.connect(_on_meta_clicked)
			_grid.add_child(rtlabel)
		else:
			rtlabel = _grid.get_child(row * 2)
			rtlabel.show()
		if _wiki_manager.has_page(row_label):
			rtlabel.parse_bbcode('[url="%s"]%s[/url]' % [row_label, tr(row_label)])
		else:
			rtlabel.parse_bbcode(tr(row_label))
	else:
		var label: Label
		if is_new_row:
			label = Label.new()
			_grid.add_child(label)
		else:
			label = _grid.get_child(row * 2)
			label.show()
		label.text = row_label
	
	if wiki_values and _wiki_manager:
		var rtvalue: RichTextLabel
		if is_new_row:
			rtvalue = RichTextLabel.new()
			rtvalue.autowrap_mode = TextServer.AUTOWRAP_OFF
			rtvalue.scroll_active = false
			rtvalue.fit_content = true
			rtvalue.bbcode_enabled = true
			rtvalue.meta_clicked.connect(_on_meta_clicked)
			_grid.add_child(rtvalue)
		else:
			rtvalue = _grid.get_child(row * 2 + 1)
			rtvalue.show()
		if !value_key:
			rtvalue.parse_bbcode(value_text)
		elif _wiki_manager.has_page(value_key):
			rtvalue.parse_bbcode('[url="%s"]%s[/url]' % [value_text, tr(value_key)])
		else:
			rtvalue.parse_bbcode(tr(value_key))
	else:
		var value: Label
		if is_new_row:
			value = Label.new()
			_grid.add_child(value)
		else:
			value = _grid.get_child(row * 2 + 1)
			value.show()
		value.text = value_text
	
	if is_new_row and _added_rows == 1:
		_set_top_row_cell_widths()


func _reset_column_widths() -> void:
	_en_width = get_theme_font_size(&"normal", &"Label") * 0.5
	if _added_rows > 0:
		_set_top_row_cell_widths()


func _set_top_row_cell_widths() -> void:
	var label0: Control = _grid.get_child(0)
	label0.custom_minimum_size.x = _en_width * min_labels_en_width
	var value0: Control = _grid.get_child(1)
	value0.custom_minimum_size.x = _en_width * min_values_en_width


func _on_meta_clicked(meta: String) -> void:
	_wiki_manager.open_page(meta)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"gui_size":
		_reset_column_widths()
