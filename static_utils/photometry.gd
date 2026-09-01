# photometry.gd
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
class_name IVPhotometry
extends Object

## Visible-light photometric anchors and conversion static methods.
##
## Apparent V magnitude is the flux anchor (m = 0 defined as
## [constant MAG0_ILLUMINANCE] at the observer) and mag/arcsec^2 is the
## surface-brightness anchor. [IVExposureManager] builds the physical-light
## chain from these.[br][br]
##
## These anchors define the V-band magnitude and surface-brightness scales that
## table data is already expressed in, so unlike [IVAstronomy]'s constants they
## are not meant to be replaced. The physical-light system's one tunable
## anchor is [member IVExposureManager.background_peak_magnitude_per_arcsec2].

## Illuminance of a magnitude-0 star at the observer, in internal units
## (lux at sim scale). The V-band anchor that welds catalog magnitudes to
## photometric quantities.
const MAG0_ILLUMINANCE := 2.518e-6 * IVUnits.CANDELA / IVUnits.METER ** 2
## Luminance of surface brightness 0 mag/arcsec^2, in internal units
## (cd/m^2 at sim scale); L = SB0_LUMINANCE * 10^(-0.4 * S).
const SB0_LUMINANCE := 1.08e5 * IVUnits.CANDELA / IVUnits.METER ** 2


## Returns apparent V magnitude for [param absolute_magnitude] at
## [param distance] (internal units).
static func get_apparent_magnitude(absolute_magnitude: float, distance: float) -> float:
	const FIVE_OVER_LN10 := 2.1714724095162594 # 5 / ln(10), for m = M + 5*log10(d / 10pc)
	return absolute_magnitude + FIVE_OVER_LN10 * log(distance / (10.0 * IVUnits.PARSEC))


## Returns illuminance at the observer (internal units) for
## [param apparent_magnitude] (V).
static func get_illuminance_from_apparent_magnitude(apparent_magnitude: float) -> float:
	return MAG0_ILLUMINANCE * 10.0 ** (-0.4 * apparent_magnitude)


## Returns apparent V magnitude for [param illuminance] at the observer
## (internal units). Inverse of [method get_illuminance_from_apparent_magnitude];
## INF for a non-positive illuminance, which reads as "infinitely faint" through
## every magnitude consumer.
static func get_apparent_magnitude_from_illuminance(illuminance: float) -> float:
	const TWO_HALF_OVER_LN10 := 1.0857362047581294 # 2.5 / ln(10), for m = -2.5*log10(E / E0)
	if illuminance <= 0.0:
		return INF
	return -TWO_HALF_OVER_LN10 * log(illuminance / MAG0_ILLUMINANCE)


## Returns luminance (internal units) for [param surface_brightness]
## (V mag/arcsec^2).
static func get_luminance_from_surface_brightness(surface_brightness: float) -> float:
	return SB0_LUMINANCE * 10.0 ** (-0.4 * surface_brightness)


## Returns the mean disc luminance (internal units) of a star of
## [param absolute_magnitude] (V) and [param radius] (internal units).
## Distance-invariant: a resolved disc's surface brightness does not change
## with distance (only unresolved flux carries the distance gradient).
static func get_star_disc_luminance(absolute_magnitude: float, radius: float) -> float:
	var illuminance_10pc := get_illuminance_from_apparent_magnitude(absolute_magnitude)
	var angular_radius_10pc := radius / (10.0 * IVUnits.PARSEC)
	return illuminance_10pc / (PI * angular_radius_10pc * angular_radius_10pc)


## Returns apparent V magnitude of a sunlit body seen as a point source: its whole
## disc's reflected flux, expressed as the magnitude an unresolved source of that
## flux would have. [param geometric_albedo] is the table's [code]albedo[/code] —
## NOT [code]meter_albedo[/code], which is the camera-facing reflectance a body's
## shells add to; the relation below is exact at zero phase only for the geometric
## albedo, which is defined by it. [param star_illuminance] is the star's
## illuminance at the body and [param phase_factor] its disc-integrated phase
## function (see [method get_disc_phase_function]). Returns INF where any input
## leaves no light to draw.
static func get_reflected_apparent_magnitude(geometric_albedo: float, radius: float,
		camera_distance: float, star_illuminance: float, phase_factor: float) -> float:
	if geometric_albedo <= 0.0 or radius <= 0.0 or camera_distance <= 0.0:
		return INF
	var angular_radius := radius / camera_distance
	var illuminance := (geometric_albedo * phase_factor * star_illuminance
			* angular_radius * angular_radius)
	return get_apparent_magnitude_from_illuminance(illuminance)


## Returns the disc-integrated phase function of a Lunar-Lambert surface at
## [param phase_angle] (radians), normalized to 1.0 at zero phase.
## [param lunar_lambert] is the same L the body's surface shader renders with
## (shells.tsv [code]lunar_lambert[/code]), so an unresolved body dims through
## phase exactly as the disc it hands off to.[br][br]
##
## Lunar-Lambert blends Lommel-Seeliger and Lambert on the surface, and the disc
## integral of the blend is the same blend of their disc integrals — weighted by
## each term's zero-phase disc flux, which is L for the Lommel-Seeliger term
## (uniform across the disc there) and 2/3 (1 - L) for the Lambert term (the mean
## of mu0 over the projected disc). Both integrals are closed form, so this costs
## no quadrature.[br][br]
##
## KNOWN LIMITATION: a smooth BRDF's disc integral is shallower than a real
## regolith's, whose shadow-hiding takes far more light out at moderate phase —
## the quarter Moon comes out about 1.6 mag bright here. That error is the
## rendered DISC's already; taking the point's law from anywhere else would buy
## catalog accuracy at the cost of a flux step through the handoff. A Hapke
## treatment would fix both halves at once.
static func get_disc_phase_function(phase_angle: float, lunar_lambert: float) -> float:
	# Clamped off both ends: the Lommel-Seeliger form below is 0/0 at each, with
	# limits 1 and 0. At these bounds a body is fully lit or 5e-7 lit, so the clamp
	# has nothing to say about anything visible.
	const MIN_ANGLE := 1e-6
	const MAX_ANGLE := PI - 1e-4
	var angle := clampf(phase_angle, MIN_ANGLE, MAX_ANGLE)
	var lambert := (sin(angle) + (PI - angle) * cos(angle)) / PI
	# 1 - sin(a/2) tan(a/2) ln(cot(a/4)), rewritten in t = tan(a/4) so nothing
	# evaluates tan() at its pole.
	var tan_quarter := tan(angle / 4.0)
	var tan_quarter_sq := tan_quarter * tan_quarter
	var lommel_seeliger := (1.0 + 4.0 * tan_quarter_sq * log(tan_quarter)
			/ (1.0 - tan_quarter_sq * tan_quarter_sq))
	var blend := clampf(lunar_lambert, 0.0, 1.0)
	var lambert_weight := (2.0 / 3.0) * (1.0 - blend)
	return ((blend * lommel_seeliger + lambert_weight * lambert)
			/ (blend + lambert_weight))


## Returns the [method get_disc_phase_function] L that best stands in for a
## Minnaert surface of exponent [param minnaert_k]. Exact at both ends of the
## useful range — k = 1 is Lambert (L = 0) and k = 0.5 [i]is[/i] Lommel-Seeliger
## (L = 1) — and linear between. The giants' cloud decks sit below 0.5 and clamp
## to Lommel-Seeliger.
static func get_minnaert_equivalent_lunar_lambert(minnaert_k: float) -> float:
	return clampf(2.0 * (1.0 - minnaert_k), 0.0, 1.0)
