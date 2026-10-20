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

## Composition of a body's atmosphere, trace atmosphere or photosphere, for display.
##
## [IVTableCompositionBuilder] builds these from data tables, and [IVSelectionData]
## shows one row per species. Nothing else references this class, so a project can
## replace it or remove the builder.

const PERSIST_MODE := IVGlobal.PERSIST_PROCEDURAL
const PERSIST_PROPERTIES: Array[StringName] = [
	&"species",
	&"amounts",
]

# persisted
## Text keys of the chemical species, entities of [code]chemicals.tsv[/code], in table order.
var species: Array[StringName] = []
## Amount of each species in [member species]: display text ("78.08%", "~1%"), a text key
## ([code]TXT_TRACE[/code]), or "" if unknown. Pass each through [method Object.tr].
var amounts: Array[String] = []
