// points.l4l5.id.gdshader
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
shader_type spatial;
render_mode unshaded, cull_disabled, skip_vertex_transform;

// See comments in points.id.gdshader.
//
// For L4/L5 objects, a & m are determined by da, dl, f & th0 together with
// characteristic_length (semi-major axis of the secondary body) and mean
// longitude (leading or lagging secondary body by 60 degrees).
//
// da: amplitude of axis ocillation
// dl: amplitude of longitudinal ocillation
// f: frequency of ocillation (period = TAU / f)
// th0: phase at epoch
// e, i, s, g: same as non-lagrange-point orbits
// de (not used): e ocillation, I think. If so, what is the frequency & phase?
//
// We're using a harmonic ocillator as a *very* rough approximation. There are
// no closed-form solutions so we can only approximate L-point librations.
// TODO: Notwithstanding above, we could improve our ocillator functions to
// give more 'tadpole'-shaped librations.

global uniform float iv_time;

uniform float lp_mean_longitude; // update per frame
uniform int lp_integer; // 4 or 5; not currently used but should be for better ocillators
uniform float characteristic_length; // semi-major axis of the secondary body
uniform float point_size = 3.0;
uniform vec3 color : source_color = vec3(0.0, 1.0, 0.0);

varying flat vec3 fragment_id;

#include "_fragment_id.gdshaderinc"
#include "_orbit_math.gdshaderinc"


float longitude_ocillator(float dl, float th){
	// th = 0 when trojan is at 'leading' extreme (max L relative to L-point).
	return dl * cos(th);
}


float axis_ocillator(float da, float th){
	// clockwise; leading L4s are slowed and fall into lower orbit as they
	// approach the secondary body
	return da * sin(th);
}


void vertex() {
	fragment_id = VERTEX; // id for each vertex (not position!)
	
	// orbit elements
	float e = CUSTOM0[0]; // eccentricity
	float i = CUSTOM0[1]; // inclination
	float lan = CUSTOM0[2]; // longitude of the ascending node
	float aop = CUSTOM0[3]; // argument of periapsis
	
	// lagrange point parameters
	float da = CUSTOM1[0]; // amplitude of axis ocillation
	float dl = CUSTOM1[1]; // amplitude of longitudinal ocillation
	float f = CUSTOM1[2]; // frequency of ocillation
	float th0 = CUSTOM1[3]; // ocillator at epoch
	
	// orbit precessions
	float s = CUSTOM2[0]; // nodal precession (=longitude_ascending_node_rate)
	float g = CUSTOM2[1]; // apsidal precession (=longitude_of_periapsis_rate)
	
//	float mag = CUSTOM2[3]; // magnitude; NOT IMPLEMENTED
	
	// orbit precessions
	lan += s * iv_time;
	aop += (g - s) * iv_time; // arg of periapsis = long of periapsis - long ascending node
	lan = mod(lan, TAU);
	aop = mod(aop, TAU);
	
	// libration of a & m
	float th = th0 + f * iv_time;
	float a = characteristic_length + axis_ocillator(da, th);
	float m = lp_mean_longitude - lan - aop + longitude_ocillator(dl, th);
	m = mod(m + PI, TAU) - PI;
	
	vec3 position = get_orbit_position(a, e, i, lan, aop, m);
	
	// We skip VERTEX here, but this is the 2-step version...
	// VERTEX = (MODELVIEW_MATRIX * vec4(x, y, z, 1.0)).xyz;
	// POSITION = PROJECTION_MATRIX * vec4(VERTEX, 1.0);	
	POSITION = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(position, 1.0));
	
	POINT_SIZE = point_size;
}


void fragment() {
	if (is_id_fragment(FRAGCOORD.xy)){
		ALBEDO = get_id_fragment_color(fragment_id);
	} else {
		ALBEDO = color;
	}
}

