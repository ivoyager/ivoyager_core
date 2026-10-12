# edge_container.gd
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
@tool
class_name IVEdgeContainer
extends Container

## Container that holds its children against its edges and corners without overlap.
##
## A child sits where its size flags put it: Shrink Begin, Shrink Center or
## Shrink End in each axis, or Fill to span that axis. Both flags at Shrink End
## put a child in the bottom-right corner; Shrink Center and Shrink End put it
## at the middle of the bottom edge.[br][br]
##
## Children are placed in tree order, and a later child yields to the ones
## before it. One centered horizontally slides along its edge to the nearest
## clear place; otherwise it moves off its edge past any child that sits across
## that edge, so two children given the same corner stack there. A child held to
## the top or bottom edge then gets a maximum height that ends where the next
## child beyond it begins.[br][br]
##
## A horizontal [FlowContainer] that doesn't fill its width takes one row where
## the clear space at its edge allows, and otherwise wraps to fit that space; a
## centered one is offered the widest gap between the children placed before
## it.[br][br]
##
## Panels that a user opens and closes can close one another when there isn't
## room for them together: see [member cullable_children].[br][br]
##
## Order children by precedence, and give any child that may be squeezed a
## [ScrollContainer] with vertical scroll mode
## [constant ScrollContainer.SCROLL_MODE_MAXIMIZE_FIRST]: it then fits its
## content until space runs out and scrolls after that, where a child that
## can't shrink would spill past its bounds.[br][br]
##
## Hazard: this container sets the height of [member Control.custom_maximum_size]
## on every child held to its top or bottom edge, replacing any set there.[br][br]
##
## Margins and separation follow the "gui_size" setting. Anchor this container
## to fill its parent: it has no minimum size of its own.

enum {
	ALIGN_BEGIN,
	ALIGN_CENTER,
	ALIGN_END,
	ALIGN_FILL,
}

const SIZE_FLAG_OPTIONS: PackedInt32Array = [SIZE_FILL, SIZE_SHRINK_BEGIN, SIZE_SHRINK_CENTER,
		SIZE_SHRINK_END]


## Space between the children and this container's edges at GUI size Large (see
## [member IVCoreSettings.gui_size_multipliers]).
@export var base_margin := 10.0:
	set = set_base_margin
## Space kept between children at GUI size Large.
@export var base_separation := 8.0:
	set = set_base_separation
## Children that close to make room for one another, as panels a user opens and
## closes. When one of them is moved off its edge, the one shown last stays
## open, and each one shown before it stays only if it still fits beside those
## shown after it; one moved off its edge by any other child closes nothing.
## Read at ready.
@export var cullable_children: Array[Control] = []


var _multiplier := 1.0
var _shown_cullables: Array[Control] = [] # shown longest ago first
var _is_cull_queued := false



func _ready() -> void:
	if Engine.is_editor_hint():
		return
	for cullable in cullable_children:
		cullable.visibility_changed.connect(_on_cullable_visibility_changed.bind(cullable))
		if cullable.visible:
			_shown_cullables.append(cullable)
	if IVStateManager.initialized_core:
		_configure_after_core_inited()
	else:
		IVStateManager.core_initialized.connect(_configure_after_core_inited, CONNECT_ONE_SHOT)


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		_sort_children()


func _get_allowed_size_flags_horizontal() -> PackedInt32Array:
	return SIZE_FLAG_OPTIONS


func _get_allowed_size_flags_vertical() -> PackedInt32Array:
	return SIZE_FLAG_OPTIONS


func set_base_margin(value: float) -> void:
	base_margin = value
	queue_sort()


func set_base_separation(value: float) -> void:
	base_separation = value
	queue_sort()


func _configure_after_core_inited() -> void:
	IVSettingsManager.changed.connect(_settings_listener)
	_update_multiplier()


func _update_multiplier() -> void:
	var gui_size: int = IVSettingsManager.get_setting(&"gui_size")
	_multiplier = IVCoreSettings.gui_size_multipliers[gui_size]
	queue_sort()


func _sort_children() -> void:
	var displaced_children := _place_children(true)
	if _is_cull_queued:
		return
	for cullable in _shown_cullables:
		if displaced_children.has(cullable):
			_is_cull_queued = true
			_cull_children.call_deferred()
			return


# Places the visible children, or, if not applied, works out only where they would go were
# the given cullable children the only ones shown. Returns the children moved off their edge.
func _place_children(is_applied: bool, shown_cullables: Array[Control] = []) -> Array[Control]:
	var margin := roundf(base_margin * _multiplier)
	var separation := roundf(base_separation * _multiplier)
	var inner := Rect2(Vector2(margin, margin), (size - 2.0 * Vector2(margin, margin)).maxf(0.0))
	# The editor has no gui_size, and a maximum set there would be saved into the scene.
	var set_maximums := is_applied and !Engine.is_editor_hint()
	var placed: Array[Rect2] = []
	var displaced_children: Array[Control] = []
	for child in get_children():
		var control := child as Control
		if !control or control.top_level:
			continue
		var is_shown := control.visible
		if !is_applied and cullable_children.has(control):
			is_shown = shown_cullables.has(control)
		if !is_shown:
			continue
		var h_align := _get_alignment(control.size_flags_horizontal)
		var v_align := _get_alignment(control.size_flags_vertical)
		var minimum := control.get_combined_minimum_size()
		# A FlowContainer's minimum width is its widest child, which would make it a column.
		var flow := control as FlowContainer
		var is_wrapping_flow := flow and !flow.vertical and h_align != ALIGN_FILL
		if is_wrapping_flow:
			minimum = _get_flow_size(flow, h_align, v_align, placed, inner, separation)
		var rect := Rect2()
		rect.size.x = inner.size.x if h_align == ALIGN_FILL else minf(minimum.x, inner.size.x)
		rect.size.y = inner.size.y if v_align == ALIGN_FILL else minf(minimum.y, inner.size.y)
		rect.position.x = _get_aligned_position(inner.position.x, inner.size.x, rect.size.x, h_align)
		rect.position.y = _get_aligned_position(inner.position.y, inner.size.y, rect.size.y, v_align)
		var aligned_y := rect.position.y
		rect = _get_clear_rect(rect, h_align, v_align, placed, inner, separation)
		if rect.position.y != aligned_y:
			displaced_children.append(control)
		if v_align != ALIGN_CENTER:
			var height_limit := _get_height_limit(rect, v_align, placed, inner, separation)
			if set_maximums:
				_set_maximum_height(control, height_limit)
			var height := height_limit
			if v_align != ALIGN_FILL:
				# A flow's own minimum height is for the width it had at its last sort.
				var minimum_height := (minimum.y if is_wrapping_flow
						else control.get_bound_minimum_size().y)
				height = minf(minimum_height, height_limit)
			if v_align == ALIGN_END:
				rect.position.y = rect.end.y - height
			rect.size.y = height
		if is_applied and is_wrapping_flow:
			# fit_child_in_rect() would shrink it back to its own minimum width.
			control.position = rect.position
			control.size = rect.size
		elif is_applied:
			fit_child_in_rect(control, rect)
		placed.append(rect)
	return displaced_children


# Keeps the cullable children shown last, and each earlier one only where it neither is
# moved off its edge by those kept nor moves one of them off theirs.
func _cull_children() -> void:
	_is_cull_queued = false
	var kept: Array[Control] = []
	for i in range(_shown_cullables.size() - 1, -1, -1):
		var candidate := _shown_cullables[i]
		var with_candidate: Array[Control] = kept.duplicate()
		with_candidate.append(candidate)
		var displaced_with := _place_children(false, with_candidate)
		var is_crowding := (displaced_with.has(candidate)
				and !_place_children(false, [candidate]).has(candidate))
		if !is_crowding:
			var displaced_without := _place_children(false, kept)
			for keeper in kept:
				if displaced_with.has(keeper) and !displaced_without.has(keeper):
					is_crowding = true
					break
		if !is_crowding:
			kept.append(candidate)
	for cullable in cullable_children:
		if cullable.visible and !kept.has(cullable):
			cullable.hide()


func _get_alignment(size_flags: int) -> int:
	if size_flags & SIZE_SHRINK_END:
		return ALIGN_END
	if size_flags & SIZE_SHRINK_CENTER:
		return ALIGN_CENTER
	if size_flags & SIZE_FILL:
		return ALIGN_FILL
	return ALIGN_BEGIN


func _get_aligned_position(begin: float, span: float, length: float, alignment: int) -> float:
	match alignment:
		ALIGN_CENTER:
			return roundf(begin + (span - length) / 2.0)
		ALIGN_END:
			return begin + span - length
	return begin


# One row where the clear span at the flow's edge allows, else wrapped to that span's width.
# Where not even its widest child fits there, one row again: it will be moved off its edge.
func _get_flow_size(flow: FlowContainer, h_align: int, v_align: int, placed: Array[Rect2],
		inner: Rect2, separation: float) -> Vector2:
	var child_sizes: Array[Vector2i] = []
	for child in flow.get_children():
		var control := child as Control
		if control and control.visible and !control.top_level:
			child_sizes.append(Vector2i(control.get_bound_minimum_size()))
	if child_sizes.is_empty():
		return flow.get_combined_minimum_size()
	var h_separation := flow.get_theme_constant(&"h_separation")
	var v_separation := flow.get_theme_constant(&"v_separation")
	var row_width := -h_separation
	var widest := 0
	for child_size in child_sizes:
		row_width += child_size.x + h_separation
		widest = maxi(widest, child_size.x)
	var unwrapped_width := minf(row_width, inner.size.x)
	var width := unwrapped_width
	for _i in child_sizes.size():
		var height := _get_flow_height(child_sizes, h_separation, v_separation, width)
		var top := _get_aligned_position(inner.position.y, inner.size.y, height, v_align)
		var bottom := inner.end.y if v_align == ALIGN_FILL else top + height
		var span := _get_clear_span_width(top, bottom, h_align, placed, inner, separation)
		if span >= width:
			break
		if span < widest:
			width = unwrapped_width
			break
		width = floorf(span)
	return Vector2(width, _get_flow_height(child_sizes, h_separation, v_separation, width))


# Height of the lines a horizontal FlowContainer breaks its children into at this width,
# breaking them as the engine does.
func _get_flow_height(child_sizes: Array[Vector2i], h_separation: int, v_separation: int,
		width: float) -> float:
	var lines_height := 0
	var line_x := 0
	var line_height := 0
	var line_count := 0
	for child_size in child_sizes:
		if line_count > 0:
			line_x += h_separation
		if line_x + child_size.x > width:
			lines_height += line_height + v_separation
			line_x = 0
			line_height = 0
			line_count = 0
		line_height = maxi(line_height, child_size.y)
		line_x += child_size.x
		line_count += 1
	return lines_height + line_height


# Width of the clear span between two heights that a rect may take: the widest one for a
# horizontally centered rect, else the one at its held side.
func _get_clear_span_width(top: float, bottom: float, h_align: int, placed: Array[Rect2],
		inner: Rect2, separation: float) -> float:
	var blocks: Array[Vector2] = [] # x begin and end, separation included
	for other in placed:
		if _overlaps(top, bottom, other.position.y, other.end.y, separation):
			blocks.append(Vector2(other.position.x - separation, other.end.x + separation))
	blocks.sort()
	var widest := 0.0
	var span_begin := inner.position.x
	for block in blocks:
		if block.x > span_begin:
			var span := minf(block.x, inner.end.x) - span_begin
			if h_align == ALIGN_BEGIN:
				return span if span_begin == inner.position.x else 0.0
			widest = maxf(widest, span)
		span_begin = maxf(span_begin, block.y)
	var last_span := maxf(inner.end.x - span_begin, 0.0)
	match h_align:
		ALIGN_BEGIN:
			return last_span if span_begin == inner.position.x else 0.0
		ALIGN_END:
			return last_span
	return maxf(widest, last_span)


# Slides a horizontally centered rect along its edge to the nearest clear place. Failing
# that, or for any other rect, moves it off its edge past what sits across that edge. What
# lies further out is not an obstacle here: it caps the rect's height.
func _get_clear_rect(rect: Rect2, h_align: int, v_align: int, placed: Array[Rect2],
		inner: Rect2, separation: float) -> Rect2:
	if !_hits_any(rect, placed, separation):
		return rect
	if h_align == ALIGN_CENTER:
		var candidates: Array[float] = []
		for other in placed:
			if _overlaps(rect.position.y, rect.end.y, other.position.y, other.end.y, separation):
				candidates.append(other.position.x - separation - rect.size.x)
				candidates.append(other.end.x + separation)
		var best_x := NAN
		for x in candidates:
			if x < inner.position.x or x + rect.size.x > inner.end.x:
				continue
			if !is_nan(best_x) and absf(x - rect.position.x) >= absf(best_x - rect.position.x):
				continue
			if !_hits_any(Rect2(Vector2(x, rect.position.y), rect.size), placed, separation):
				best_x = x
		if !is_nan(best_x):
			rect.position.x = best_x
			return rect
	if v_align == ALIGN_CENTER:
		return rect
	for _i in placed.size():
		var edge := Rect2(rect.position.x, rect.position.y, rect.size.x, 1.0)
		if v_align == ALIGN_END:
			edge.position.y = rect.end.y - 1.0
		var hit := _get_first_hit(edge, placed, separation)
		if !hit.has_area():
			break
		if v_align == ALIGN_END:
			rect.position.y = hit.position.y - separation - rect.size.y
		else:
			rect.position.y = hit.end.y + separation
	return rect


# Space from the rect's held edge to whatever lies beyond it in its columns.
func _get_height_limit(rect: Rect2, v_align: int, placed: Array[Rect2], inner: Rect2,
		separation: float) -> float:
	if v_align == ALIGN_END:
		var top := inner.position.y
		for other in placed:
			if (other.end.y <= rect.end.y
					and _overlaps(rect.position.x, rect.end.x, other.position.x, other.end.x,
					separation)):
				top = maxf(top, other.end.y + separation)
		return maxf(rect.end.y - top, 0.0)
	var bottom := inner.end.y
	for other in placed:
		if (other.position.y >= rect.position.y
				and _overlaps(rect.position.x, rect.end.x, other.position.x, other.end.x,
				separation)):
			bottom = minf(bottom, other.position.y - separation)
	return maxf(bottom - rect.position.y, 0.0)


func _set_maximum_height(control: Control, height: float) -> void:
	var maximum := control.custom_maximum_size
	if maximum.y != height:
		control.custom_maximum_size = Vector2(maximum.x, height)


func _hits_any(rect: Rect2, placed: Array[Rect2], separation: float) -> bool:
	return _get_first_hit(rect, placed, separation).has_area()


func _get_first_hit(rect: Rect2, placed: Array[Rect2], separation: float) -> Rect2:
	for other in placed:
		if (_overlaps(rect.position.x, rect.end.x, other.position.x, other.end.x, separation)
				and _overlaps(rect.position.y, rect.end.y, other.position.y, other.end.y,
				separation)):
			return other
	return Rect2()


# True if two spans come closer than the separation (a half-pixel tolerance absorbs
# rounding).
func _overlaps(begin_a: float, end_a: float, begin_b: float, end_b: float, separation: float
		) -> bool:
	return begin_a < end_b + separation - 0.5 and begin_b < end_a + separation - 0.5


func _on_cullable_visibility_changed(cullable: Control) -> void:
	_shown_cullables.erase(cullable)
	if cullable.visible:
		_shown_cullables.append(cullable)


func _settings_listener(setting: StringName, _value: Variant) -> void:
	if setting == &"gui_size":
		_update_multiplier()
