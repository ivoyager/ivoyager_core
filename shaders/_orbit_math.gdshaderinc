// _orbit_math.gdshaderinc
// This file is part of I, Voyager
// https://ivoyager.dev
// *****************************************************************************
// Copyright 2017-2025 Charlie Whitfield
// I, Voyager is a registered trademark of Charlie Whitfield in the US
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// *****************************************************************************

// TODO? There are faster algorithms for Keplar's equation that could be coded:
// https://github.com/oliverphilcox/Keplers-Goat-Herd.

vec3 get_orbit_position(float a, float e, float i, float lan, float aop, float m){
	// Mostly duplicates orbital math in IVOrbits.

	// A while loop here breaks WebGL1 export. From empirical testing, two
	// corrections are needed for the vast majority of points and only a
	// tiny minority receive the 5th correction.
	float ea = m + e * sin(m); // eccentric anomaly (initial approximation)
	float delta_ea = (ea - m - e * sin(ea)) / (1.0 - e * cos(ea));
	ea -= delta_ea;
	delta_ea = (ea - m - e * sin(ea)) / (1.0 - e * cos(ea));
	ea -= delta_ea;
	if (abs(delta_ea) > 1e-5){
		delta_ea = (ea - m - e * sin(ea)) / (1.0 - e * cos(ea));
		ea -= delta_ea;
		if (abs(delta_ea) > 1e-5){
			delta_ea = (ea - m - e * sin(ea)) / (1.0 - e * cos(ea));
			ea -= delta_ea;
			if (abs(delta_ea) > 1e-5){
				delta_ea = (ea - m - e * sin(ea)) / (1.0 - e * cos(ea));
				ea -= delta_ea;
			}
		}
	}

	float nu = 2.0 * atan(sqrt((1.0 + e) / (1.0 - e)) * tan(ea / 2.0));
	float r = a * (1.0 - e * cos(ea));
	float cos_i = cos(i);
	float sin_lan = sin(lan);
	float cos_lan = cos(lan);
	float sin_aop_nu = sin(aop + nu);
	float cos_aop_nu = cos(aop + nu);
	float x = r * (cos_lan * cos_aop_nu - sin_lan * sin_aop_nu * cos_i);
	float y = r * (sin_lan * cos_aop_nu + cos_lan * sin_aop_nu * cos_i);
	float z = r * sin(i) * sin_aop_nu;

	return vec3(x, y, z);
}
