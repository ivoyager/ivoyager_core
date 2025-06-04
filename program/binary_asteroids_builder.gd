# binary_asteroids_builder.gd
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
class_name IVBinaryAsteroidsBuilder
extends RefCounted

## Builds an [IVSmallBodiesGroup] instance from asteroid binary data.
##
## Binary asteroid data is in ivoyager_assets and is created by
## [url=https://github.com/ivoyager/ivbinary_maker]ivbinary_maker[/url].

const VPRINT = false # print verbose asteroid summary on load
const DPRINT = false

const BINARY_EXTENSION := "ivbinary"
const BINARY_FILE_MAGNITUDES: Array[String] = ["11.0", "11.5", "12.0", "12.5", "13.0", "13.5",
		"14.0", "14.5", "15.0", "15.5", "16.0", "16.5", "17.0", "17.5", "18.0", "18.5", "99.9"]



func build_sbg_from_binaries(sbg: IVSmallBodiesGroup, binary_dir: String, mag_cutoff: float
		) -> void:
	for mag_str in BINARY_FILE_MAGNITUDES:
		if mag_str.to_float() > mag_cutoff:
			break
		_load_asteroids_group_binary(sbg, binary_dir, mag_str)
	assert(!VPRINT or sbg.vprint_load("asteroids"))


func _load_asteroids_group_binary(sbg: IVSmallBodiesGroup, binary_dir: String, mag_str: String
		) -> void:
	var lp_integer := sbg.lp_integer
	var binary_name: String = sbg.sbg_alias + "." + mag_str + "." + BINARY_EXTENSION
	var path: String = binary_dir.path_join(binary_name)
	var binary := FileAccess.open(path, FileAccess.READ)
	if !binary: # skip quietly if file doesn't exist
		return
	assert(!DPRINT or IVDebug.dprint("Reading binary %s" % path))

	var binary_data: Array = binary.get_var()
	binary.close()
	var names: PackedStringArray = binary_data[0]
	var e_i_lan_ap: PackedFloat32Array = binary_data[1]
	var a_m0_n: PackedFloat32Array = binary_data[2]
	var s_g_mag_de: PackedFloat32Array = binary_data[3]
	var da_d_f_th0: PackedFloat32Array
	if lp_integer != -1:
		da_d_f_th0 = binary_data[4]
	
	# apply scale if needed
	var size := names.size()
	assert(size)
	const scale_multiplier := IVUnits.METER
	if scale_multiplier != 1.0:
		var index := 0
		while index < size:
			a_m0_n[index * 3] *= scale_multiplier # a only
			if lp_integer != -1:
				da_d_f_th0[index * 4] *= scale_multiplier # da only
			index += 1
	
	sbg.append_data(names, e_i_lan_ap, a_m0_n, s_g_mag_de, da_d_f_th0)
