# arrays.gd
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
class_name IVArrays
extends Object

## Array static utility methods.


## Init array of given [param size], [param fill], and type parameters. Keep
## [param fill] == null to not fill.
static func init_array(size: int, fill: Variant = null, type := -1, class_name_ := &"",
		script: Variant = null) -> Array:
	var array: Array
	if type == -1:
		array = []
	else:
		array = Array([], type, class_name_, script)
	array.resize(size)
	if fill == null:
		return array
	array.fill(fill)
	return array


## Merges the contents of [param from] Array into the provided [param into]
## Array [b]without[/b] duplication.
static func merge_array(into: Array, from: Array) -> void:
	for item: Variant in from:
		if not into.has(item):
			into.append(item)
