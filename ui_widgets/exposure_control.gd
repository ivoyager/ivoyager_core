# exposure_control.gd
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
class_name IVExposureControl
extends HBoxContainer

## HBoxContainer widget for reading and overriding the physical camera's
## exposure.
##
## Displays the auto exposure that [IVExposureManager] meters each frame, in EV
## relative to the authored sky look. Unchecking "Auto" replaces the readout
## with a SpinBox seeded from the current auto value, snapped to the nearest
## 1/3 stop; a second SpinBox adjusts in 1/3 stops on top of whichever of the
## two is in force.[br][br]
##
## Requires [IVExposureManager], which exists only where
## [member IVCoreSettings.enable_physical_light] is true. The controls are
## disabled - and by default the whole widget is hidden - whenever physical
## light is not active.


## Lowest settable manual exposure. Metering bottoms out near -38 EV with the
## sun's own disc as the subject, so this only stops a runaway drag.
const MANUAL_MIN_EV := -48.0
## Lowest settable exposure adjustment.
const ADJUSTMENT_MIN_EV := -6.0
## Range anchors its step snapping on min_value, and 1/3 is not representable, so
## every usable min lands zero at -1e-14 - which SpinBox renders as "-0.0". Past
## Range's rescale threshold (step * 1e14) it snaps around zero instead, which is
## exact; _clamp_to_min() then applies the floor the min_value would have.
const UNANCHORED_MIN := -1e15

## If true (default), hide the widget entirely while physical light is
## inactive, rather than showing it with its controls disabled.
@export var hide_when_nonphysical_light := true
## Step size for manual EV and for the additive adjustment SpinBox.
@export var ev_step := 0.2

var _exposure_manager: IVExposureManager
var _physical_active := false

@onready var _auto_ckbx: CheckBox = $AutoCkbx
@onready var _auto_label: Label = $AutoLabel
@onready var _manual_spinbox: SpinBox = $ManualSpinBox
@onready var _adjustment_spinbox: SpinBox = $AdjustmentSpinBox



func _ready() -> void:
	set_process(false)
	_manual_spinbox.step = ev_step
	_adjustment_spinbox.step = ev_step
	_manual_spinbox.min_value = UNANCHORED_MIN
	_adjustment_spinbox.min_value = UNANCHORED_MIN
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	# IVExposureManager.physical_active is the whole gate: it folds in the core
	# setting, the user setting, the dynamic_lights requirement and a photometry
	# failure, and the manager defers it a frame on purpose (see its _process).
	# That node runs at priority -1, so this reads the current frame's value.
	if _physical_active != IVExposureManager.physical_active:
		_physical_active = !_physical_active
		_update_physical_active()
	if _physical_active and _exposure_manager.auto:
		_auto_label.text = "%.1f" % IVExposureManager.auto_exposure_ev


func _configure_after_core_inited() -> void:
	_exposure_manager = IVGlobal.program.get(&"ExposureManager")
	if !_exposure_manager: # IVCoreSettings.enable_physical_light == false
		_update_physical_active()
		return
	_auto_ckbx.toggled.connect(_on_auto_toggled)
	_manual_spinbox.value_changed.connect(_on_manual_value_changed)
	_adjustment_spinbox.value_changed.connect(_on_adjustment_value_changed)
	_auto_ckbx.set_pressed_no_signal(_exposure_manager.auto)
	_manual_spinbox.set_value_no_signal(_exposure_manager.manual_exposure_ev)
	_adjustment_spinbox.set_value_no_signal(_exposure_manager.exposure_adjustment_ev)
	_update_auto_display()
	_update_physical_active()
	set_process(true)


func _update_physical_active() -> void:
	if hide_when_nonphysical_light:
		visible = _physical_active
	_auto_ckbx.disabled = !_physical_active
	_manual_spinbox.editable = _physical_active
	_adjustment_spinbox.editable = _physical_active


func _update_auto_display() -> void:
	_auto_label.visible = _exposure_manager.auto
	_manual_spinbox.visible = !_exposure_manager.auto


func _on_auto_toggled(toggled_on: bool) -> void:
	if !toggled_on:
		# Hand manual control the exposure the camera is already at, so that
		# unchecking Auto does not itself change the view. The SpinBox's own
		# EV_STEP snapping is what rounds it to the nearest 1/3 stop.
		_manual_spinbox.set_value_no_signal(IVExposureManager.auto_exposure_ev)
		_exposure_manager.manual_exposure_ev = _manual_spinbox.value
	_exposure_manager.auto = toggled_on
	_update_auto_display()


func _on_manual_value_changed(value: float) -> void:
	_exposure_manager.manual_exposure_ev = _clamp_to_min(_manual_spinbox, value, MANUAL_MIN_EV)


func _on_adjustment_value_changed(value: float) -> void:
	_exposure_manager.exposure_adjustment_ev = _clamp_to_min(_adjustment_spinbox, value,
			ADJUSTMENT_MIN_EV)


func _clamp_to_min(spinbox: SpinBox, value: float, minimum: float) -> float:
	if value >= minimum:
		return value
	spinbox.set_value_no_signal(minimum)
	return spinbox.value
