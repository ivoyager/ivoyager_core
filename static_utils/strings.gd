# strings.gd
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
class_name IVStrings
extends Object

## String static utility methods.


## Returns 64 bit string formatted '00000000_00000000_00000000_...'.
## WARNING: The sign bit no longer works for shift operations as of Godot 4.6.1.
static func get_bit_string(flags: int, bytes := 4) -> String:
	var bits := bytes * 8
	var result := ""
	var index := 0
	while index < bits:
		if index % 8 == 0 and index != 0:
			result = "_" + result
		result = "1" + result if flags & 1 else "0" + result
		flags >>= 1
		index += 1
	return result
