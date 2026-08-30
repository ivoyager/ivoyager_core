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
