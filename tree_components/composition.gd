# composition.gd
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
class_name IVComposition
extends RefCounted

## Base class representing the composition of something, e.g., a planet's
## atmosphere or a star's photosphere.
##
## This object is designed for simple GUI display. It can be subclassed or
## replaced (it isn't referenced anywhere so it's easy to replace). GUI widget
## [IVSelectionData] expects an object with method "get_labels_values_display".

enum CompositionType {
	BY_WEIGHT, 
	BY_VOLUME,
}

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"type",
	&"components",
]

# persisted
## How [member components] amounts should be interpreted; one of
## [enum CompositionType].
var type: int
## Map of chemical name to amount string ([code]null[/code] if amount unknown).
var components := {} # chemicals w/ amount string or null



## Returns parallel [code][label, value][/code] strings for GUI display.
## [param labels_prefix] is prepended to each label.
func get_labels_values_display(labels_prefix := "") -> Array[String]:
	const arrays := preload("uid://bv7xrcpcm24nc")
	var result := arrays.init_array(2, "", TYPE_STRING) # label, value
	for key: String in components:
		var value: Variant = components[key]
		var optn_newline := "\n" if result[0] else ""
		match typeof(value):
			TYPE_NIL:
				result[0] += optn_newline + labels_prefix + key
				result[1] += optn_newline + ""
			TYPE_STRING:
				result[0] += optn_newline + labels_prefix + key
				result[1] += optn_newline + value
	return result
