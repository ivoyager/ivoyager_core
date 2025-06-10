# composition.gd
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
class_name IVComposition
extends RefCounted

## Base class representing the composition of something, e.g., a planet's
## atmosphere or a star's photosphere.
##
## This object is designed for simple GUI display. It isn't referenced anywhere
## so it is easy to replace. (GUI widget IVSelectionData does expect an object
## with method "get_labels_values_display".)

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
var type: int
var components := {} # chemicals w/ amount string or null



func get_labels_values_display(labels_prefix := "") -> Array[String]:
	var result := IVUtils.init_array(2, "", TYPE_STRING) # label, value
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
