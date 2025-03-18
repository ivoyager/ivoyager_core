# enums.gd
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
class_name IVEnums
extends Object

## Global context enums and enum constants.

## Duplicated from Tree Saver plugin so we can have these in our classes
## without the plugin.
enum PersistMode {
	NO_PERSIST, ## Non-persist object.
	PERSIST_PROPERTIES_ONLY, ## Object will not be freed (Node only; must have stable NodePath).
	PERSIST_PROCEDURAL, ## Object will be freed and rebuilt on game load (Node or RefCounted).
}
const NO_PERSIST := PersistMode.NO_PERSIST
const PERSIST_PROPERTIES_ONLY := PersistMode.PERSIST_PROPERTIES_ONLY
const PERSIST_PROCEDURAL := PersistMode.PERSIST_PROCEDURAL


enum SBGClass {
	SBG_CLASS_ASTEROIDS,
	SBG_CLASS_COMETS,
	SBG_CLASS_ARTIFICIAL_SATELLITES, # TODO: Roadmap
	SBG_CLASS_OTHER,
}

enum GUISize {
	GUI_SMALL,
	GUI_MEDIUM,
	GUI_LARGE,
}

enum StarmapSize {
	STARMAP_8K,
	STARMAP_16K,
}

enum Confidence {
	CONFIDENCE_NO,
	CONFIDENCE_DOUBTFUL,
	CONFIDENCE_UNKNOWN,
	CONFIDENCE_PROBABLY,
	CONFIDENCE_YES,
}

enum NetworkState {
	NO_NETWORK,
	IS_SERVER,
	IS_CLIENT,
}

enum NetworkStopSync {
	BUILD_SYSTEM,
	SAVE,
	LOAD,
	NEW_PLAYER, # needs save to enter in-progress game
	EXIT,
	QUIT,
	DONT_SYNC,
}
