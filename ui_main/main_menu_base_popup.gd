# main_menu_base_popup.gd
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
class_name IVMainMenuBasePopup
extends PopupPanel

## An empty main menu base popup (without buttons) that opens/closes on
## "ui_cancel" action event and "main menu" IVGlobal signals.
##
## All child Controls added to this popup will be added automatically to a
## VBoxContainer IF AND ONLY IF there is >1 child Control. So developer can
## construct the menu by simply adding menu buttons (option 1) or can have
## more control by adding a single top MarginContainer or VBoxContainer or
## whatever (option 2). For option 1, margins and other style effects can be
## acheived by editing this node's theme override style box.[br][br]
##
## You can find many useful "main menu" buttons in
## directory ui_widgets including [IVFullScreenButton], [IVOptionsButton],
## [IVHotkeysButton], [IVExitButton], [IVQuitButton] and [IVResumeButton].
## Plugin [url=https://github.com/ivoyager/ivoyager_save]I, Voyager - Save[/url]
## has additional save/load related buttons.


## If true (defaut), the menu popup can be opened only after sim start, after
## the splash screen has been hidden. (It's expected that a game splash screen
## will have its own menu.)
@export var sim_started_only := true
## If true (default), the popup will center itself.
@export var center := true
## If true (default), the simulator will stop while the menu is open.
@export var stop_sim := true
## If true (default), prevents the popup from closing when the user clicks
## outside of the menu. They must press escape ("ui_cancel" action) or a
## "Resume" button to close.
@export var require_explicit_close := true
## If true (default), keep popup at minimum size to fit content. This fixes the
## menu size if the user changes setting "gui_size" from a large value to a
## smaller value.
@export var minimal_size := true


var _is_explicit_close := false


func _ready() -> void:
	hide() # Godot 4.5 editor keeps setting visibility == true !!!
	IVGlobal.open_main_menu_requested.connect(open)
	IVGlobal.close_main_menu_requested.connect(close)
	IVGlobal.close_all_admin_popups_requested.connect(close)
	IVGlobal.resume_requested.connect(close)
	IVStateManager.about_to_quit.connect(close)
	popup_hide.connect(_on_popup_hide)
	
	# Add to VBoxContainer IF AND ONLY IF >1 Control child...
	var control_children: Array[Control]
	for child in get_children():
		var control := child as Control
		if control:
			control_children.append(control)
	assert(control_children, "Expected main menu content; add at least 1 Control child")
	var control_child := control_children[0]
	if control_children.size() > 1:
		var vbox := VBoxContainer.new()
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		#vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		#vbox.set_anchors_preset(Control.PRESET_CENTER)
		add_child(vbox)
		for control in control_children:
			remove_child(control)
			vbox.add_child(control)
		control_child = vbox
	
	# Resizing fix...
	if minimal_size:
		control_child.minimum_size_changed.connect(_resize)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		close()
		set_input_as_handled()


func open() -> void:
	if visible:
		return
	if sim_started_only and not IVStateManager.started_or_about_to_start:
		return
	if stop_sim:
		IVStateManager.require_stop(self)
	_is_explicit_close = false
	if center:
		popup_centered()
	else:
		popup()


func close() -> void:
	_is_explicit_close = true
	hide()


func _on_popup_hide() -> void:
	if require_explicit_close and !_is_explicit_close:
		show.call_deferred()
		return
	_is_explicit_close = false
	if stop_sim:
		IVStateManager.allow_run(self)


func _resize() -> void:
	size = Vector2i.ZERO
	if center and visible:
		popup_centered() # hack fix to center on first open
