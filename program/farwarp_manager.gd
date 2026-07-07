# farwarp_manager.gd
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
class_name IVFarwarpManager
extends Node

## Maintains per-frame state for "farwarp" compression, which keeps distant
## objects renderable despite the camera's limited depth range.
##
## The camera far plane is capped at ~6 orders of magnitude beyond the
## camera-to-target distance: the near:far ratio must stay under ~2^24 or the
## engine's float32 projection-plane extraction degenerates (see note in
## [IVCamera]). Farwarp compression re-renders anything beyond a start
## distance T (= camera distance x [member IVCoreSettings.farwarp_start_ratio])
## along its true camera ray at compressed distance g(d), uniformly scaled by
## g(d)/d so angular size and screen direction are [i]exactly[/i] preserved:[br][br]
##
## [code]g(d) = d[/code] for [code]d <= T[/code] (exact identity);
## [code]g(d) = T * (1 + ln(d / T))[/code] beyond (C1-continuous at T).[br][br]
##
## Monotonic g preserves occlusion order, including transits across T. True
## [IVBody] positions are never modified; only visuals move. [IVBody] applies
## the remap to its model space via an interposed top_level node positioned in
## world space from camera-relative math (float32 rounding then stays
## proportional to the compressed distance; see [member IVBody.farwarp_space]);
## orbit lines and small-body points apply the same g() per-vertex in view
## space (see [code]shaders/_farwarp.gdshaderinc[/code]). This node publishes
## one consistent per-frame state for all consumers: static state below plus a
## call to [method IVBody.update_farwarp] on every visible body, and the
## [code]iv_farwarp_start[/code] global shader parameter ([code]<= 0.0[/code]
## disables) for shaders.[br][br]
##
## Processes at priority +100: after the body tree AND after [IVCamera] (0) has
## moved and origin-shifted the Universe. Ordinary tree children ride the
## origin shift automatically, but the world-space (top_level) farwarp nodes
## do not - placing them from pre-shift state leaves them one frame of camera
## world-motion behind, which reads as violent shake on fast nearby orbiters
## (the camera's parent moves km per frame) and off-center models during fast
## camera rotation. This late pass reads the settled post-shift camera and body
## globals, so CPU placements land in the same frame coordinates the renderer
## and the vertex shaders use. To disable the whole system, set
## [member IVCoreSettings.apply_farwarp] false.


## Start distance T of the current frame's farwarp compression, in internal
## length units; <= 0.0 when disabled or no camera. Read-only.
static var farwarp_start := 0.0
## Post-origin-shift camera global position paired with [member farwarp_start].
## Read-only.
static var camera_global_position := Vector3.ZERO
## Mirror of [member IVCoreSettings.farwarp_angular_cutoff]. Read-only.
static var angular_cutoff := 0.0

var _start_ratio: float = IVCoreSettings.farwarp_start_ratio
var _camera: Camera3D


## The one source of truth for the farwarp compression curve; keep in exact
## sync with [code]shaders/_farwarp.gdshaderinc[/code]. Returns the compressed
## render distance g([param distance]) for compression starting at [param start].
static func get_farwarp_distance(distance: float, start: float) -> float:
	if start <= 0.0 or distance <= start:
		return distance
	return start * (1.0 + log(distance / start))


## Returns g([param distance]) / [param distance], the uniform scale (and
## offset multiplier minus one) for the farwarp remap; exactly 1.0 at or
## inside [param start] or when disabled ([param start] <= 0.0).
static func get_farwarp_factor(distance: float, start: float) -> float:
	if start <= 0.0 or distance <= start:
		return 1.0
	return start * (1.0 + log(distance / start)) / distance


func _ready() -> void:
	set_process_priority(100) # after the body tree and IVCamera's origin shift; see class doc
	angular_cutoff = IVCoreSettings.farwarp_angular_cutoff
	if !IVCoreSettings.apply_farwarp:
		RenderingServer.global_shader_parameter_set(&"iv_farwarp_start", 0.0)
		set_process(false)
		return
	IVGlobal.current_camera_changed.connect(_on_current_camera_changed)
	IVStateManager.about_to_free_procedural_nodes.connect(_clear_procedural)


func _process(_delta: float) -> void:
	if _camera:
		# Same distance expression IVCamera uses to set 'far', so T tracks the
		# far plane by construction: T/far == farwarp_start_ratio/FAR_MULTIPLIER.
		var dist := _camera.position.length()
		farwarp_start = dist * _start_ratio
		camera_global_position = _camera.global_position
	else:
		farwarp_start = 0.0
		camera_global_position = Vector3.ZERO
	RenderingServer.global_shader_parameter_set(&"iv_farwarp_start", farwarp_start)
	# With farwarp_start <= 0.0 the update places visuals at true positions.
	for body_name: StringName in IVBody.bodies:
		var body := IVBody.bodies[body_name]
		if body.visible:
			body.update_farwarp(camera_global_position, farwarp_start)


func _on_current_camera_changed(camera: Camera3D) -> void:
	_camera = camera


func _clear_procedural() -> void:
	_camera = null
	farwarp_start = 0.0
	camera_global_position = Vector3.ZERO
	RenderingServer.global_shader_parameter_set(&"iv_farwarp_start", 0.0)
