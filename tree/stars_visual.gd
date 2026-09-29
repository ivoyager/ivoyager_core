# stars_visual.gd
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
class_name IVStarsVisual
extends MeshInstance3D

## Catalog star field drawn as farwarp-remapped point sprites, one child mesh per
## magnitude bin.
##
## Builds a [constant Mesh.PRIMITIVE_POINTS] child per magnitude-binned star binary
## (produced by [code]addons/tools/build_star_binaries.py[/code] from the Hipparcos and
## Tycho-2 catalogues) on [signal IVStateManager.core_initialized]; this node draws
## nothing of its own. Each vertex is a star at its true ecliptic position (internal
## units); a [code]CUSTOM0[/code] channel carries raw (V magnitude, B-V), which the
## [code]stars[/code] shader converts to point size, brightness and color. The
## shader's per-vertex farwarp remap (shared with the small-body points) keeps
## distant stars inside the camera far plane and behind every simulation visual at
## any zoom.[br][br]
##
## The bin is a child rather than a surface because it is the CULLING unit: under
## physical light the compensating camera meters most of the catalog below one display
## code long before it has finished stopping down for a sunlit body, and a bin drawing
## nothing is then not submitted at all (see [member cull_invisible_bins]). One merged
## surface cannot be hidden in parts, which is the whole reason for the split.[br][br]
##
## Authored as a fixed node under [code]Universe[/code] (no PERSIST_MODE), so it
## rides the [IVCamera] origin shift automatically, builds once, and survives
## system rebuilds. No-ops with a warning if no binaries resolve (e.g. when
## ivoyager_assets is absent).[br][br]
##
## Note: Godot Editor shows a scene warning for missing mesh. This node holds none by
## design, so you can ignore the warning.


## Magnitude-bin upper edges; must match the bins written by
## [code]addons/tools/build_star_binaries.py[/code]. Each bin file holds stars up to its edge.
const BINARY_FILE_MAGNITUDES: Array[String] = ["2.0", "2.5", "3.0", "3.5", "4.0", "4.5", "5.0",
		"5.5", "6.0", "6.5", "7.0", "7.5", "8.0", "8.5", "9.0", "9.5", "10.0", "10.5", "11.0",
		"11.5", "12.0", "12.5", "13.0", "99.9"]

## [member magnitude_cutoff] for each value of user setting [code]star_catalog[/code] (see
## [member IVGraphicsManager.star_catalog_settings]), each a bin edge in
## [constant BINARY_FILE_MAGNITUDES]. The lower of the two cutoffs applies.
const STAR_CATALOG_CUTOFFS: Array[float] = [99.9, 11.0, 9.5]

## Share of [constant IVPhotometry.ONE_DISPLAY_CODE_LINEAR] a DRAWN bin must fall below to
## be hidden, against the whole code a hidden one must reach to come back. Half a code is
## the 8-bit rounding boundary and so the real "cannot move a pixel" line; the gap to a
## whole code is the hysteresis, without which a bin sitting on the line would flip every
## frame. For a star bin that gap is several EV wide, so which bins draw at a given exposure
## depends on the exposure the camera arrived with; see [i]Half a code[/i] in
## PHOTOMETRIC_MODEL.md.
const HIDE_THRESHOLD_FRACTION := 0.5

## Directional grid the per-bin sky density is measured over: bands of equal
## [code]sin(latitude)[/code] by equal longitude, so every cell holds the same solid angle.
const DENSITY_LATITUDE_BANDS := 8
## See [constant DENSITY_LATITUDE_BANDS].
const DENSITY_LONGITUDE_CELLS := 12

## Render height an off-screen capture is about to use, or 0.0 for none. A capture TALLER
## than the window renders every star brighter (the shaders' resolution law is
## [code]height^2[/code]), so a bin correctly hidden for the window would be visible in the
## capture: [IVScreenshotManager] registers its render height here, waits a frame, captures
## and clears it. A hidden bin returns on the frame it crosses the threshold, with no
## damping, which is what makes one frame enough. The background panorama needs no
## counterpart -- an extended source is sampled per pixel and its level is
## resolution-invariant.
static var capture_render_height := 0.0

const _ARRAY_FLAGS := Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
const _BINARY_MAGIC := 0x54535649 # b"IVST", little-endian
const _BINARY_VERSION := 2

## Path prefix for the star binaries. The loader appends
## [code].<magnitude>.ivbinary[/code] for each bin in [member BINARY_FILE_MAGNITUDES].
@export var stars_binary_path := "res://addons/ivoyager_assets/starmaps/stars"

## Loads magnitude bins up to and including this V-magnitude cutoff. Lower it (or
## remove bin files from the asset directory) to trade completeness for size. A
## project that renders at a fixed fov can drop every bin that fov cannot show;
## the ivoyager_assets README tabulates where each bin becomes invisible. User
## setting [code]star_catalog[/code] can lower it further (see [constant
## STAR_CATALOG_CUTOFFS]); its Options choices name the full catalog's star counts,
## which a lower value here makes wrong.
@export var magnitude_cutoff := 99.9

## Hides each magnitude bin the current exposure renders below one display code. This is
## relief with no visual change rather than a quality setting: wherever the compensating
## camera has stopped down for a sunlit body, most of the catalog is submitting vertices
## that draw nothing. Inert without physical light, where exposure rests at
## [constant IVExposureManager.INACTIVE_EXPOSURE] and no shipped bin falls below the
## threshold at any fov. Set false to render (and measure) against the full field.
## See [i]Skipping what the camera has metered away[/i] in PHOTOMETRIC_MODEL.md.
@export var cull_invisible_bins := true

# The tuning surface for IVPSFSettings, the camera every source images through -- this
# field and every in-scene body's PSF quad alike, so an edit here moves both. Values
# write through on change (and on build, once the settings object exists); the live
# material updates from the settings object's 'changed' signal, not from these setters.
# See stars.gdshader for each uniform's role. Each range runs from one visibly wrong
# extreme to the other, so dragging a slider end to end shows what the uniform does;
# the shipped value sits well inside.
@export_group("Point Spread Function")
## 0.1 = sub-pixel specks that scintillate; 1.5 = fat blurry discs.
@export_range(0.1, 1.5, 0.05, "or_greater") var psf_sigma := 0.5:
	set(value):
		psf_sigma = value
		if _psf_settings:
			_psf_settings.psf_sigma = value
## 0 = only the very brightest stars remain; 14 = every star saturates to white.
@export_range(0.0, 14.0, 0.1) var intensity_faint_mag := 6.5:
	set(value):
		intensity_faint_mag = value
		if _psf_settings:
			_psf_settings.intensity_faint_mag = value
## 0.05 = every star the same brightness; 2.0 = only a handful survive, the rest go black.
@export_range(0.05, 2.0, 0.05) var intensity_gamma := 1.0:
	set(value):
		intensity_gamma = value
		if _psf_settings:
			_psf_settings.intensity_gamma = value
## 0 = no stars at all; 1.5 = the field washes out to saturated blobs.
@export_range(0.0, 1.5, 0.01, "or_greater") var intensity_scale := 0.5:
	set(value):
		intensity_scale = value
		if _psf_settings:
			_psf_settings.intensity_scale = value
## The fov at which [member fov_compensation] neither brightens nor dims the field. Away
## from the camera's actual fov the whole field shifts: 10 = far too dim, 120 = blown out.
@export_range(10.0, 120.0, 0.5) var fov_reference_deg := 50.0:
	set(value):
		fov_reference_deg = value
		if _psf_settings:
			_psf_settings.fov_reference_deg = value
## 0 = stars hold brightness as you zoom (they swamp or fade against the background);
## 2 = double-compensated, so zooming in blows the field out.
@export_range(0.0, 2.0, 0.05) var fov_compensation := 1.0:
	set(value):
		fov_compensation = value
		if _psf_settings:
			_psf_settings.fov_compensation = value
## Amplitude of the [code]r^-2[/code] glare wing every star carries outside its Gaussian
## core, at 1 px and unit intensity; 0 turns it off. See [member IVPSFSettings.glare_scale].
@export_range(0.0, 0.05, 0.001, "or_greater") var glare_scale := 0.0126:
	set(value):
		glare_scale = value
		if _psf_settings:
			_psf_settings.glare_scale = value
## How fast the glare widens with flux: its outer radius grows as
## [code]intensity^(glare_gamma / 2)[/code]. See [member IVPSFSettings.glare_gamma].
@export_range(0.0, 1.0, 0.005) var glare_gamma := 0.286:
	set(value):
		glare_gamma = value
		if _psf_settings:
			_psf_settings.glare_gamma = value
## Largest glare radius in px at the reference viewport height.
## See [member IVPSFSettings.glare_max_px].
@export_range(16.0, 1024.0, 1.0, "or_greater") var glare_max_px := 384.0:
	set(value):
		glare_max_px = value
		if _psf_settings:
			_psf_settings.glare_max_px = value
## 0 = a white field; 1 = each star's physical blackbody color; 2.5 = a candy-colored sky.
## Unlike the sliders above, this changes no star's brightness or size.
@export_range(0.0, 2.5, 0.05) var color_saturation := 1.0:
	set(value):
		color_saturation = value
		if _psf_settings:
			_psf_settings.color_saturation = value

var _shader_material: ShaderMaterial
var _psf_settings: IVPSFSettings
var _bin_visuals: Array[MeshInstance3D] = [] # bright to faint, the order the cull assumes
var _bin_star_counts := PackedInt32Array()
var _bin_brightest_magnitudes := PackedFloat64Array()
var _bin_peak_densities := PackedFloat64Array() # stars/steradian where each bin is densest
var _drawn_bins := 0 # how long a prefix of _bin_visuals is currently visible



func _ready() -> void:
	set_process(false)
	# A fixed scene node's _ready() precedes core init, so the stars shader isn't
	# registered yet; build on core_initialized (resources populated and frozen).
	if IVStateManager.initialized_core:
		_build()
	else:
		IVStateManager.core_initialized.connect(_build, CONNECT_ONE_SHOT)


func _process(_delta: float) -> void:
	var drawn_bins := _get_drawn_bin_count()
	if drawn_bins == _drawn_bins:
		return
	var i := mini(drawn_bins, _drawn_bins)
	var last := maxi(drawn_bins, _drawn_bins)
	while i < last:
		_bin_visuals[i].visible = i < drawn_bins
		i += 1
	_drawn_bins = drawn_bins


## Number of magnitude bins built, bright to faint; 0 until the build.
func get_bin_count() -> int:
	return _bin_visuals.size()


## How long a prefix of the built bins is currently drawn. Equal to
## [method get_bin_count] whenever [member cull_invisible_bins] is false or physical
## light is inactive.
func get_drawn_bin_count() -> int:
	return _drawn_bins


func _build() -> void:
	var star_catalog: int = IVSettingsManager.get_setting(&"star_catalog")
	IVSettingsManager.set_running_value(&"star_catalog", star_catalog)
	# A stale cached index past the end takes the last cutoff, as the popup shows it.
	var cutoff := minf(magnitude_cutoff,
			STAR_CATALOG_CUTOFFS[clampi(star_catalog, 0, STAR_CATALOG_CUTOFFS.size() - 1)])
	var bin_meshes: Array[ArrayMesh] = []
	var bin_names: Array[String] = []
	for magnitude_str in BINARY_FILE_MAGNITUDES:
		if magnitude_str.to_float() > cutoff:
			break
		var bin_mesh := _build_bin_mesh(magnitude_str)
		if bin_mesh:
			bin_meshes.append(bin_mesh)
			bin_names.append("StarBin_" + magnitude_str.replace(".", "_"))
	if bin_meshes.is_empty():
		push_warning("IVStarsVisual: no star binaries found at '%s.*.ivbinary'" % stars_binary_path)
		return

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = IVGlobal.resources[&"stars_shader"]
	_psf_settings = IVGlobal.program[&"PSFSettings"]
	_push_psf_settings()
	_psf_settings.changed.connect(_apply_psf_uniforms)
	_apply_psf_uniforms() # _push_psf_settings emits nothing if every export is a default

	var i := 0
	while i < bin_meshes.size():
		var bin_visual := MeshInstance3D.new()
		bin_visual.name = bin_names[i]
		bin_visual.mesh = bin_meshes[i]
		bin_visual.material_override = _shader_material # one camera, so one material
		bin_visual.cast_shadow = SHADOW_CASTING_SETTING_OFF
		bin_visual.sorting_use_aabb_center = false # f32 collapses that AABB's centre
		bin_visual.layers = layers # VisualInstance3D.layers is not inherited from a parent
		add_child(bin_visual)
		_bin_visuals.append(bin_visual)
		i += 1
	_drawn_bins = _bin_visuals.size()
	set_process(true)


# Seeds the shared settings from this node's authored exports. The property setters
# cannot: they fire during scene load, before IVCoreInitializer has built the settings
# object, so their write-through no-ops and the authored values would never arrive.
func _push_psf_settings() -> void:
	_psf_settings.psf_sigma = psf_sigma
	_psf_settings.intensity_faint_mag = intensity_faint_mag
	_psf_settings.intensity_gamma = intensity_gamma
	_psf_settings.intensity_scale = intensity_scale
	_psf_settings.fov_reference_deg = fov_reference_deg
	_psf_settings.fov_compensation = fov_compensation
	_psf_settings.color_saturation = color_saturation
	_psf_settings.glare_scale = glare_scale
	_psf_settings.glare_gamma = glare_gamma
	_psf_settings.glare_max_px = glare_max_px


func _apply_psf_uniforms() -> void:
	_psf_settings.apply_to(_shader_material)


# A star's rendered value falls with magnitude, so what the camera can still show is always
# a PREFIX of the bins and what it drops is always a suffix. Walk the suffix inward from
# the faint end, because the two tests a bin has to fail are of different kinds: its
# brightest star must be invisible ON ITS OWN, and the glow of every bin dropped so far --
# which sums, blend_add being a sum -- must be invisible TOGETHER. Bins that are each below
# the line can be above it in aggregate, which is what the running total catches.
func _get_drawn_bin_count() -> int:
	var n_bins := _bin_visuals.size()
	if !cull_invisible_bins or !IVExposureManager.physical_active:
		return n_bins
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d()
	if !camera:
		return n_bins
	var render_height := maxf(IVGraphicsManager.get_render_size(viewport).y,
			capture_render_height)
	if render_height <= 0.0:
		return n_bins
	var resolution_scale := render_height / IVBodyPSF.get_reference_viewport_height()
	var fov_factor := _psf_settings.get_fov_compensation_factor(camera.fov)
	var tan_half_fov := tan(deg_to_rad(camera.fov) / 2.0)
	# Screen solid angle over pixel count, the aspect ratio cancelling out of both. The
	# small-angle form is the one fov_compensation itself is built on (1/tan^2), and it
	# over-states a wide screen's share of the sky, so the error is toward drawing.
	var steradians_per_pixel := 4.0 * tan_half_fov * tan_half_fov / (render_height * render_height)
	var exposure := IVExposureManager.exposure
	var summed_glow := 0.0
	var drawn_bins := n_bins
	while drawn_bins > 0:
		var bin_index := drawn_bins - 1
		var intensity := _psf_settings.get_point_intensity(
				_bin_brightest_magnitudes[bin_index], fov_factor, resolution_scale, exposure)
		var peak := _psf_settings.get_peak_light(intensity, resolution_scale)
		# A sprite lights at least the pixel it lands on, however far its radius has shrunk.
		var radius := _psf_settings.get_draw_radius(intensity, resolution_scale)
		var sprite_pixels := maxf(PI * radius * radius, 1.0)
		var glow := (peak * _bin_peak_densities[bin_index] * steradians_per_pixel
				* sprite_pixels)
		var threshold := IVPhotometry.ONE_DISPLAY_CODE_LINEAR
		if bin_index < _drawn_bins:
			threshold *= HIDE_THRESHOLD_FRACTION
		if peak >= threshold or summed_glow + glow >= threshold:
			break
		summed_glow += glow
		drawn_bins = bin_index
	return drawn_bins


# Returns one magnitude bin's points mesh, or null where its file is missing or unusable (a
# missing bin loads as no stars, as with the asteroid binaries -- which is what lets a
# project ship only the bins its own fov can show). ALSO APPENDS the bin's star count and
# its brightest star's magnitude, which _get_drawn_bin_count() reads every frame, so bins
# must be built in the order the cull walks them.
#
# The file is the packed v2 format; build_star_binaries.py's docstring is its
# specification, and the quantization constants ride in the header rather than
# being duplicated here so a rebuild cannot silently disagree with this decode.
func _build_bin_mesh(magnitude_str: String) -> ArrayMesh:
	var path := stars_binary_path + "." + magnitude_str + ".ivbinary"
	var file := FileAccess.open(path, FileAccess.READ)
	if !file:
		return null
	if file.get_32() != _BINARY_MAGIC:
		push_warning("IVStarsVisual: bad magic in '%s'" % path)
		return null
	var version := file.get_32()
	if version != _BINARY_VERSION:
		push_warning("IVStarsVisual: unexpected version %s in '%s'" % [version, path])
		return null
	var count := file.get_32()
	var parallax_count := file.get_32()
	var shell_pc := file.get_float()
	var max_distance_pc := file.get_float()
	var parallax_scale := file.get_float()
	var magnitude_min := file.get_float()
	var magnitude_step := file.get_float()
	var b_v_min := file.get_float()
	var b_v_step := file.get_float()
	if count == 0:
		return null
	# Two uint32 per star, bulk-read as one int32 array so the decode below is integer
	# masks on a packed buffer rather than a FileAccess call per field.
	var words := file.get_buffer(count * 8).to_int32_array()
	var parallax_codes := file.get_buffer(parallax_count * 2)
	file.close()

	# Direction components are quantized over +/-1 and deliberately left unnormalized
	# (see build_star_binaries.py); folding the 1/32767 into the distance is what keeps
	# the loop to one Vector3 multiply. The parallax stars come first in the file, so
	# the index alone says which distance a star takes.
	const PARSEC := IVUnits.PARSEC
	var shell_scale := shell_pc * PARSEC / 32767.0
	var parallax_numerator := 1000.0 * parallax_scale * PARSEC / 32767.0
	var vertices := PackedVector3Array()
	var magnitudes_colors := PackedFloat32Array() # (V_mag, B-V) per vertex -> CUSTOM0
	vertices.resize(count)
	magnitudes_colors.resize(count * 2)
	var brightest_code := 0xFF
	var i := 0
	while i < count:
		var word_0 := words[i * 2]
		var word_1 := words[i * 2 + 1]
		var distance_scale := shell_scale
		if i < parallax_count:
			distance_scale = parallax_numerator / float(parallax_codes.decode_u16(i * 2))
		vertices[i] = Vector3(
				float((word_0 & 0xFFFF) - 32768),
				float(((word_0 >> 16) & 0xFFFF) - 32768),
				float((word_1 & 0xFFFF) - 32768)) * distance_scale
		var magnitude_code := (word_1 >> 16) & 0xFF
		if magnitude_code < brightest_code:
			brightest_code = magnitude_code
		magnitudes_colors[i * 2] = magnitude_min + magnitude_step * float(magnitude_code)
		magnitudes_colors[i * 2 + 1] = b_v_min + b_v_step * float((word_1 >> 24) & 0xFF)
		i += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_CUSTOM0] = magnitudes_colors
	var bin_mesh := ArrayMesh.new()
	bin_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays, [], {}, _ARRAY_FLAGS)
	# Frustum culling tests this AABB against the far plane, but farwarp-remapped
	# points stay on-screen even when the true-scale test fails; size the AABB so
	# it always contains the camera (as IVSBGPositionsVisual does for its points).
	var half_extent := maxf(max_distance_pc * PARSEC, IVCoreSettings.max_camera_distance)
	var half_aabb := half_extent * Vector3.ONE
	bin_mesh.custom_aabb = AABB(-half_aabb, 2.0 * half_aabb)
	_bin_star_counts.append(count)
	_bin_brightest_magnitudes.append(magnitude_min + magnitude_step * float(brightest_code))
	_bin_peak_densities.append(_get_peak_sky_density(words, count))
	return bin_mesh


# Returns the highest star density this bin reaches anywhere on the sky, in stars per
# steradian. The cull needs the densest patch rather than the average because that is where
# a bin's summed glow arrives at one display code first, and the two differ by several
# times: the catalog is a galaxy seen from inside it, so a mean-density estimate would
# clear a bin for culling while its Milky Way band was still glowing. Sampled rather than
# counted whole, the decode loop above being hot enough already.
func _get_peak_sky_density(words: PackedInt32Array, count: int) -> float:
	const SAMPLE_TARGET := 50000
	const N_CELLS := DENSITY_LATITUDE_BANDS * DENSITY_LONGITUDE_CELLS
	var cell_counts := PackedInt32Array()
	cell_counts.resize(N_CELLS)
	@warning_ignore("integer_division") # a sample stride is a whole number of stars
	var stride := maxi(1, count / SAMPLE_TARGET)
	var samples := 0
	var i := 0
	while i < count:
		var word_0 := words[i * 2]
		var word_1 := words[i * 2 + 1]
		var x := float((word_0 & 0xFFFF) - 32768)
		var y := float(((word_0 >> 16) & 0xFFFF) - 32768)
		var z := float((word_1 & 0xFFFF) - 32768)
		var distance := sqrt(x * x + y * y + z * z)
		i += stride
		if distance == 0.0:
			continue
		var band := clampi(int((z / distance + 1.0) * 0.5 * DENSITY_LATITUDE_BANDS),
				0, DENSITY_LATITUDE_BANDS - 1)
		var sector := clampi(int((atan2(y, x) / TAU + 0.5) * DENSITY_LONGITUDE_CELLS),
				0, DENSITY_LONGITUDE_CELLS - 1)
		cell_counts[band * DENSITY_LONGITUDE_CELLS + sector] += 1
		samples += 1
	if samples == 0:
		return 0.0
	var peak_count := 0
	for cell_count in cell_counts:
		peak_count = maxi(peak_count, cell_count)
	# Back up to the whole bin from the subsample, then to a density: every cell holds the
	# same 4*PI/N_CELLS steradians, which is what the equal-sin(latitude) banding buys.
	return float(peak_count * count) / float(samples) * float(N_CELLS) / (4.0 * PI)
