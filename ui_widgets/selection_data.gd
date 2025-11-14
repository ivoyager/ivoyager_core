# selection_data.gd
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
class_name IVSelectionData
extends VBoxContainer

## GUI widget that provides a parent node and specific content for
## [IVSelectionDataFoldable] instances.
##
## This is a content-only class that can be modified or replaced as parent to
## [IVSelectionDataFoldable] instances, which search up their ancestry tree for
## content and validity test dictionaries. All functions here are
## provided as content Callables for data formatting and show/hide logic.[br][br]
##
## Two dictionaries are provided here for [IVSelectionDataFoldable] use:[br][br]
##
## [member selection_data_content] is required and must contain keys that match the
## names of all descendent [IVSelectionDataFoldable] instances. Each value
## is an array of arrays that specifies row data for a [IVSelectionDataFoldable].
## Each row array has the following elements:[br][br]
##
## [0] Row label as a StringName, a label Callable that returns a StringName, or
##     null (null only if value path returns a [labels, values] array.)[br]
## [1] Value path relative to current [IVSelection]. Path can point to a class
##     property, a dictionary key, or a get method.[br]
## [2, optional] Value format Callable.[br]
## [3, optional] A row hide Callable.[br][br]
##
## Rows are hidden if value path can't be resolved or returns null or NAN, or
## if the value format Callable returns "", or if the hide Callable returns
## true.[br][br]
##
## [member selection_data_valid_tests] is optional and optionally contains keys that match
## names of descendent [IVSelectionDataFoldable] instances. If dictionary and
## key are present, the value will provide a Callable test for validity of the
## entire foldable data section. The section will be hidden if this Callable
## exists and returns true.[br][br]
##
## For most applications, you'll want to put this widget in a ScrollContainer.[br][br]

const NumberType := IVQFormat.NumberType
const BodyFlags := IVBody.BodyFlags


## Theme type variation used by [IVSelectionDataFoldable] decendents. If &""
## (default), the foldable widgets will keep looking up the Node tree for this
## "tree property". The property is set in [IVTopUI] for a global GUI value.
@export var foldables_theme_type_variation := &""

## Content dictionary. Must contain all descendent [IVSelectionDataFoldable]
## names as keys. See class doc for content format.
var selection_data_content: Dictionary[StringName, Array] = {
	OrbitalCharacteristics = [
		[get_periapsis_label, "body/orbit/get_periapsis", dynamic_unit.bind(&"length_km_au",
			false, 5)],
		[get_apoapsis_label, "body/orbit/get_apoapsis", dynamic_unit.bind(&"length_km_au",
			false, 5)],
		[&"LABEL_SEMI_MAJOR_AXIS", "body/orbit/get_semi_major_axis",
			dynamic_unit.bind(&"length_km_au", false, 5)],
		[&"LABEL_ECCENTRICITY", "body/orbit/get_eccentricity", as_float.bind(false, 5)],
		[&"LABEL_ORBITAL_PERIOD", "body/orbit/get_period", dynamic_unit.bind(&"time_h_d_y",
			false, 5)],
		[&"LABEL_INCLINATION", "body/orbit/get_inclination", fixed_unit.bind(&"deg",
			false, 3, NumberType.DECIMAL_PLACES)],
		[&"LABEL_DIST_GALACTIC_CORE", "body/characteristics/dist_galactic_core",
			dynamic_unit.bind(&"length_km_au")],
		[&"LABEL_GALACTIC_PERIOD", "body/characteristics/galactic_period", fixed_unit.bind(&"yr")],
		[&"LABEL_AVERAGE_ORBITAL_SPEED", "body/characteristics/galactic_orbital_speed",
			fixed_unit.bind(&"km/s")],
		[&"LABEL_VELOCITY_VS_CMB", "body/characteristics/velocity_vs_cmb",
			fixed_unit.bind(&"km/s")],
		[&"LABEL_VELOCITY_VS_NEAR_STARS", "body/characteristics/velocity_vs_near_stars",
			fixed_unit.bind(&"km/s")],
		[&"LABEL_KN_PLANETS", "body/characteristics/n_kn_planets"],
		[&"LABEL_KN_DWF_PLANETS", "body/characteristics/n_kn_dwf_planets"],
		[&"LABEL_KN_MINOR_PLANETS", "body/characteristics/n_kn_minor_planets"],
		[&"LABEL_KN_COMETS", "body/characteristics/n_kn_comets"],
		[&"LABEL_NAT_SATELLITES", "body/characteristics/n_nat_satellites", natural_satellites],
		
	] as Array[Array],
	PhysicalCharacteristics = [
		[&"LABEL_CLASSIFICATION", "body/characteristics/body_class",
			table_row_name.bind(&"body_classes")],
		[&"LABEL_STELLAR_CLASSIFICATION", "body/characteristics/stellar_classification"],
		[&"LABEL_MEAN_RADIUS", "body/mean_radius", fixed_unit.bind(&"km"), hide_mean_radius],
		[&"LABEL_EQUATORIAL_RADIUS", "body/characteristics/equatorial_radius",
			fixed_unit.bind(&"km"), hide_equatorial_polar_radius],
		[&"LABEL_POLAR_RADIUS", "body/characteristics/polar_radius", fixed_unit.bind(&"km"),
			hide_equatorial_polar_radius],
		[&"LABEL_HYDROSTATIC_EQUILIBRIUM", "body/characteristics/hydrostatic_equilibrium",
			enum_name.bind(IVGlobal.Confidence), hide_hydrostatic_equilibrium],
		[&"LABEL_MASS", "body/characteristics/mass", fixed_unit.bind(&"kg")],
		[&"LABEL_SURFACE_GRAVITY", "body/characteristics/surface_gravity", fixed_unit.bind(&"g0")],
		[&"LABEL_ESCAPE_VELOCITY", "body/characteristics/esc_vel",
			dynamic_unit.bind(&"velocity_mps_kmps")],
		[&"LABEL_MEAN_DENSITY", "body/characteristics/mean_density", fixed_unit.bind(&"g/cm^3")],
		[&"LABEL_ALBEDO", "body/characteristics/albedo", as_float],
		[&"LABEL_SURFACE_TEMP_MIN", "body/characteristics/min_t", fixed_unit.bind(&"degC")],
		[&"LABEL_SURFACE_TEMP_MEAN", "body/characteristics/surf_t", fixed_unit.bind(&"degC")],
		[&"LABEL_SURFACE_TEMP_MAX", "body/characteristics/max_t", fixed_unit.bind(&"degC")],
		[&"LABEL_TEMP_CENTER", "body/characteristics/temp_center", fixed_unit.bind(&"K")],
		[&"LABEL_TEMP_PHOTOSPHERE", "body/characteristics/temp_photosphere", fixed_unit.bind(&"K")],
		[&"LABEL_TEMP_CORONA", "body/characteristics/temp_corona", fixed_unit.bind(&"K")],
		[&"LABEL_ABSOLUTE_MAGNITUDE", "body/characteristics/absolute_magnitude", as_float],
		[&"LABEL_LUMINOSITY", "body/characteristics/luminosity", fixed_unit.bind(&"W")],
		[&"LABEL_COLOR_B_V", "body/characteristics/color_b_v", as_float],
		[&"LABEL_METALLICITY", "body/characteristics/metallicity", as_float],
		[&"LABEL_AGE", "body/characteristics/age", fixed_unit.bind(&"yr")],
		[&"LABEL_ROTATION_PERIOD", "body/get_rotation_period", fixed_unit.bind(&"d", true, 5)],
		[&"LABEL_AXIAL_TILT_TO_ORBIT", "body/get_axial_tilt_to_orbit", axial_tilt_to_orbit],
		[&"LABEL_AXIAL_TILT_TO_ECLIPTIC", "body/get_axial_tilt_to_ecliptic", axial_tilt_to_ecliptic],
	] as Array[Array],
	Atmosphere = [
		[&"LABEL_SURFACE_PRESSURE", "body/characteristics/surf_pres", prefixed_unit.bind(&"bar")],
		[&"LABEL_TRACE_PRESSURE", "body/characteristics/trace_pres", prefixed_unit.bind(&"Pa")],
		[&"LABEL_TRACE_PRESSURE_HIGH", "body/characteristics/trace_pres_high",
			prefixed_unit.bind(&"Pa")],
		[&"LABEL_TRACE_PRESSURE_LOW", "body/characteristics/trace_pres_low",
			prefixed_unit.bind(&"Pa")],
		[&"LABEL_TEMP_AT_1_BAR", "body/characteristics/one_bar_t", fixed_unit.bind(&"degC")],
		[&"LABEL_TEMP_AT_HALF_BAR", "body/characteristics/half_bar_t", fixed_unit.bind(&"degC")],
		[&"LABEL_TEMP_AT_10TH_BAR", "body/characteristics/tenth_bar_t", fixed_unit.bind(&"degC")],
	] as Array[Array],
	AtmosphereComposition = [
		[null, "body/components/atmosphere", mulitline_labels_values]
	] as Array[Array],
	TraceAtmosphereComposition = [
		[null, "body/components/trace_atmosphere", mulitline_labels_values]
	] as Array[Array],
	PhotosphereComposition = [
		[null, "body/components/photosphere", mulitline_labels_values]
	] as Array[Array]
}


## Optional valid tests for each foldable section.
var selection_data_valid_tests: Dictionary[StringName, Callable] = {
	PhotosphereComposition = func(selection: IVSelection) -> bool:
		const BODYFLAGS_STAR := IVBody.BodyFlags.BODYFLAGS_STAR
		return bool(selection.get_body_flags() & BODYFLAGS_STAR)
}



# *****************************************************************************
# Label callables (content index 0)

func get_periapsis_label(selection: IVSelection) -> StringName:
	return selection.get_periapsis_label()


func get_apoapsis_label(selection: IVSelection) -> StringName:
	return selection.get_apoapsis_label()


# *****************************************************************************
# Value callables.
#
# Function signatures:
#   Args 0, 1, and 2 from loop code in IVSelectionDataFoldable
#   (internal_precision is -1 unless IVGlobal.enable_precisions == true)
#   args 3,... are binds from section_content
#
# Return type determines how it is handled by IVSelectionDataFoldable:
#  * String - print as is
#  * StringName - test as translation and/or wiki key (if wiki links enabled)
#  * Array - print as a list of labels/values

func dynamic_unit(_selection: IVSelection, x: float, internal_precision: int,
		dynamic_key: StringName, override_internal_precision := false, precision := 3,
		number_type := NumberType.DYNAMIC) -> String:
	# args 0, 1 from loop code in IVSelectionDataFoldable
	# internal_precision is -1 unless IVGlobal.enable_precisions == true
	# args 2,... are binds from section_content
	if is_inf(x):
		return "?"
	if !override_internal_precision and internal_precision != -1:
		precision = internal_precision
	return IVQFormat.dynamic_unit(x, dynamic_key, precision, number_type)


func fixed_unit(_selection: IVSelection, x: float, internal_precision: int, unit: StringName,
		override_internal_precision := false, precision := 3,
		number_type := NumberType.DYNAMIC) -> String:
	if is_inf(x):
		return "?"
	if !override_internal_precision and internal_precision != -1:
		precision = internal_precision
	return IVQFormat.fixed_unit(x, unit, precision, number_type)


func prefixed_unit(_selection: IVSelection, x: float, internal_precision: int, unit: StringName,
		override_internal_precision := false, precision := 3,
		number_type := NumberType.DYNAMIC) -> String:
	if is_inf(x):
		return "?"
	if !override_internal_precision and internal_precision != -1:
		precision = internal_precision
	return IVQFormat.prefixed_unit(x, unit, precision, number_type)


func as_float(_selection: IVSelection, x: float, internal_precision: int,
		override_internal_precision := false, precision := 3,
		number_type := NumberType.DYNAMIC) -> String:
	if is_inf(x):
		return "?"
	if !override_internal_precision and internal_precision != -1:
		precision = internal_precision
	return IVQFormat.number(x, precision, number_type)


func table_row_name(_selection: IVSelection, row: int, table_name: StringName) -> StringName:
	if row == -1:
		return &""
	return IVTableData.get_db_entity_name(table_name, row)


func enum_name(_selection: IVSelection, enum_int: int, enum_dict: Dictionary) -> StringName:
	if enum_int == -1:
		return &""
	return enum_dict.find_key(enum_int)


func mulitline_labels_values(_selection: IVSelection, object: Object) -> Array[String]:
	# Object must create a data subsection w/ lables & values
	assert(object.has_method(&"get_labels_values_display"))
	@warning_ignore("unsafe_method_access")
	return object.get_labels_values_display() # [labels String, values String]


# specific

func axial_tilt_to_orbit(selection: IVSelection, x: float, internal_precision: int) -> String:
	# "~0°" if axis locked. Adds " (variable)" qualifier to chaotic tumblers.
	const BODYFLAGS_AXIS_LOCKED := IVBody.BodyFlags.BODYFLAGS_AXIS_LOCKED
	const BODYFLAGS_CHAOTIC_TUMBLER := IVBody.BodyFlags.BODYFLAGS_CHAOTIC_TUMBLER
	var body_flags := selection.get_body_flags()
	if body_flags & BODYFLAGS_AXIS_LOCKED:
		return "~0°"
	var text := fixed_unit(selection, x, internal_precision, &"deg", true, 4)
	if body_flags & BODYFLAGS_CHAOTIC_TUMBLER:
		return "%s (%s)" % [text, tr(&"TXT_VARIABLE").to_lower()]
	return text


func axial_tilt_to_ecliptic(selection: IVSelection, x: float, internal_precision: int) -> String:
	# Adds " (variable)" qualifier to chaotic tumblers.
	const BODYFLAGS_CHAOTIC_TUMBLER := IVBody.BodyFlags.BODYFLAGS_CHAOTIC_TUMBLER
	var body_flags := selection.get_body_flags()
	var text := fixed_unit(selection, x, internal_precision, &"deg", true, 4)
	if body_flags & BODYFLAGS_CHAOTIC_TUMBLER:
		return text + (" (%s)" % tr(&"TXT_VARIABLE").to_lower())
	return text


func natural_satellites(_selection: IVSelection, x: int) -> String:
	# Adds " (known)" qualifier if many. Ad hoc solution for gas giants and Pluto.
	const DISPLAY_KNOWN_QUALIFIER := 5
	if x < DISPLAY_KNOWN_QUALIFIER:
		return str(x)
	return "%s (%s)" % [x, tr(&"TXT_KNOWN").to_lower()]


# *****************************************************************************
# Hide callables.

func hide_mean_radius(selection: IVSelection) -> bool:
	const DISPLAY_EQUATORIAL_POLAR_RADII := IVBody.BodyFlags.BODYFLAGS_DISPLAY_EQUATORIAL_POLAR_RADII
	return bool(selection.get_body_flags() & DISPLAY_EQUATORIAL_POLAR_RADII)


func hide_equatorial_polar_radius(selection: IVSelection) -> bool:
	const DISPLAY_EQUATORIAL_POLAR_RADII := IVBody.BodyFlags.BODYFLAGS_DISPLAY_EQUATORIAL_POLAR_RADII
	return !bool(selection.get_body_flags() & DISPLAY_EQUATORIAL_POLAR_RADII)


func hide_hydrostatic_equilibrium(selection: IVSelection) -> bool:
	const BODYFLAGS_MOON := IVBody.BodyFlags.BODYFLAGS_MOON
	return !bool(selection.get_body_flags() & BODYFLAGS_MOON)
