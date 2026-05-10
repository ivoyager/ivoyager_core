# fragment_identifier.gd
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
class_name IVFragmentIdentifier
extends Node

## Decodes a unique id broadcast by an "id" shader fragment (e.g., an orbit
## line or asteroid point) at the mouse position.
##
## Each "id" shader writes its 33-bit fragment id into [code]ALBEDO[/code]
## at a sparse 3-pixel grid pattern around the mouse, bounded by
## [member fragment_range]. An [IVFragmentIDCompositorEffect] attached to the
## active [Camera3D]'s [Compositor] dispatches a tiny compute shader at
## [code]POST_TRANSPARENT[/code], reads the resolved HDR color buffer
## ([code]RGBA16F[/code], pre-tonemap), finds the broadcast pixel closest to
## the mouse, and asynchronously returns the id to GDScript.[br][br]
##
## The system requires a [RenderingDevice] (Forward+ or Mobile renderer). On
## Compatibility renderer, this object removes itself from
## [member IVGlobal.program] and consumers fall back to the non-id material
## paths via their existing [code]if _fragment_identifier:[/code] guards.[br][br]
##
## To register an id from a producer (orbit line, point, etc.), call
## [method get_new_id] (or [method get_new_id_as_vec3]) with a data array
## whose first element is [code]target.get_instance_id()[/code]. The target
## must implement [code]get_fragment_text(data: Array) -> String[/code] for
## [IVMouseTargetLabel] to display.

## Emitted when the fragment under the mouse changes. [param id] is the new
## 33-bit fragment id, or [code]-1[/code] when the previous fragment is lost.
## Look up the matching record in [member fragment_data].
signal fragment_changed(id: int)


## Categories used as the second element of each [member fragment_data] entry.
enum {
	FRAGMENT_BODY_ORBIT,
	FRAGMENT_SBG_POINT,
	FRAGMENT_SBG_ORBIT,
}


const _CHANNEL_BIT_WIDTH := 11 # half-float represents integers exactly to 2048
const _CHANNEL_MASK := (1 << _CHANNEL_BIT_WIDTH) - 1
const _ID_BIT_WIDTH := _CHANNEL_BIT_WIDTH * 3 # 33 bits across R, G, B
const _ID_MAX := (1 << _ID_BIT_WIDTH) - 1


## Tunes the loss of current id by time. OK to change at runtime.
var drop_id_frames := 40
## Tunes the loss of current id by mouse movement. OK to change at runtime.
var drop_id_mouse_movement := 20.0
## Sets probe size around mouse. Side length sampled is
## [code](fragment_range / 3 + 1)^2[/code] (49 pixels at default 9). Must be a
## non-negative multiple of 3. Don't change at runtime.
var fragment_range := 9

# Read-only.
## Most recently identified fragment id, or [code]-1[/code] for none.
var current_id := -1
## Data arrays indexed by 33-bit id. [code]data[0][/code] is the target's
## instance id; additional indexes are caller-defined.
var fragment_data: Dictionary[int, Array] = {}

var _world_controller: IVWorldController
var _camera: Camera3D
var _effect: IVFragmentIDCompositorEffect
var _drop_frame_counter := 0
var _drop_mouse_coord := Vector2.ZERO


# *****************************************************************************
# Static encode / decode (paired with shader ID values in [1, 2048]).


## Encodes a 33-bit [param id] as a Vector3 with each component in
## [code][1, 2048][/code] (offset by +1 so any zero in the buffer is a clean
## reject sentinel).
static func encode_vec3(id: int) -> Vector3:
	assert(id >= 0 and id <= _ID_MAX)
	var c0 := (id & _CHANNEL_MASK) + 1
	id >>= _CHANNEL_BIT_WIDTH
	var c1 := (id & _CHANNEL_MASK) + 1
	id >>= _CHANNEL_BIT_WIDTH
	var c2 := (id & _CHANNEL_MASK) + 1
	return Vector3(float(c0), float(c1), float(c2))


## Reverses [method encode_vec3]. Each component must be in [code][1, 2048][/code].
static func decode_channels(c0: int, c1: int, c2: int) -> int:
	assert(c0 >= 1 and c0 <= _CHANNEL_MASK + 1)
	assert(c1 >= 1 and c1 <= _CHANNEL_MASK + 1)
	assert(c2 >= 1 and c2 <= _CHANNEL_MASK + 1)
	return (c0 - 1) | ((c1 - 1) << _CHANNEL_BIT_WIDTH) | ((c2 - 1) << (_CHANNEL_BIT_WIDTH * 2))


# *****************************************************************************

func _ready() -> void:
	set_process(false)
	if IVGlobal.is_gl_compatibility:
		# CompositorEffect requires RenderingDevice. Existing consumers null-check
		# IVGlobal.program.get(&"FragmentIdentifier") and fall back to non-id
		# materials, so erasing here is sufficient.
		IVGlobal.program.erase(&"FragmentIdentifier")
		queue_free()
		return
	assert(fragment_range >= 0 and fragment_range % 3 == 0)
	RenderingServer.global_shader_parameter_set(&"iv_fragment_id_range", float(fragment_range))
	_effect = IVFragmentIDCompositorEffect.new(fragment_range)
	_effect.fragment_decoded.connect(_on_fragment_decoded)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)
	IVStateManager.core_initialized.connect(_configure_for_core_inited)
	IVStateManager.run_state_changed.connect(_on_run_state_changed)


func _process(_delta: float) -> void:
	# Setting the global before draw submission so this frame's id-shaders
	# broadcast at the same pixel the compositor effect will sample. Window
	# pixels are assumed equal to internal-buffer pixels (no FSR scaling).
	var mouse_pos := _world_controller.mouse_position
	RenderingServer.global_shader_parameter_set(&"iv_mouse_fragcoord",
			mouse_pos + Vector2(0.5, 0.5))
	_effect.set_world_mouse(mouse_pos)


# *****************************************************************************
# Public API.

## Assigns a fresh 33-bit fragment id and stores [param data] under it in
## [member fragment_data]. [param data][0] should be the target's instance id;
## additional indexes are caller-defined. Returns the new id.
func get_new_id(data: Array) -> int:
	var id := ((randi() & 1) << 32) | randi() # 33 bits
	while fragment_data.has(id):
		id = ((randi() & 1) << 32) | randi()
	fragment_data[id] = data
	return id


## Convenience wrapper around [method get_new_id] that returns the new id
## already encoded as a Vector3 ready to feed to a shader.
func get_new_id_as_vec3(data: Array) -> Vector3:
	return encode_vec3(get_new_id(data))


## Removes [param id] from [member fragment_data]. No-op if not present.
func remove_id(id: int) -> void:
	fragment_data.erase(id)


# *****************************************************************************
# Lifecycle.

func _configure_for_core_inited() -> void:
	_world_controller = IVGlobal.program[&"WorldController"]
	IVGlobal.current_camera_changed.connect(_on_current_camera_changed)
	# Probe in case a camera already emitted (e.g. on reload).
	var current_camera := get_viewport().get_camera_3d()
	if current_camera:
		_on_current_camera_changed(current_camera)


func _on_run_state_changed(running: bool) -> void:
	set_process(running)
	if _effect:
		_effect.enabled = running


func _on_current_camera_changed(camera: Camera3D) -> void:
	if _camera and is_instance_valid(_camera):
		var old_compositor := _camera.compositor
		if old_compositor:
			var old_effects := old_compositor.compositor_effects.duplicate()
			old_effects.erase(_effect)
			old_compositor.compositor_effects = old_effects
	_camera = camera
	if !_camera:
		return
	if _camera.compositor == null:
		_camera.compositor = Compositor.new()
	var compositor := _camera.compositor
	var effects := compositor.compositor_effects.duplicate()
	if !effects.has(_effect):
		effects.append(_effect)
		compositor.compositor_effects = effects


func _clear_procedural() -> void:
	fragment_data.clear()
	current_id = -1
	_camera = null
	_drop_frame_counter = 0
	_drop_mouse_coord = Vector2.ZERO


func _on_fragment_decoded(id: int) -> void:
	if id != -1 and fragment_data.has(id):
		if current_id != id:
			current_id = id
			fragment_changed.emit(id)
		_drop_frame_counter = 0
		_drop_mouse_coord = _world_controller.mouse_position
		return

	if current_id == -1:
		return

	var mouse_pos := _world_controller.mouse_position
	if (_drop_frame_counter > drop_id_frames
			or _drop_mouse_coord.distance_to(mouse_pos) > drop_id_mouse_movement):
		current_id = -1
		fragment_changed.emit(-1)
		return

	_drop_frame_counter += 1
