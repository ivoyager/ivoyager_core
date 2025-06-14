# wiki_initializer.gd
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
class_name IVWikiInitializer
extends RefCounted

# FIXME or DEPRECATE: IVCoreSettings 'wiki' settings don't do anything now. We need
# to figure out how to do localization.
# Many loose ends after shift to Table Importer plugin...


func _init() -> void:
	if !IVCoreSettings.enable_wiki:
		return
	if IVCoreSettings.use_internal_wiki:
		IVGlobal.wiki = "wiki"
	else:
		var locale := TranslationServer.get_locale()
		if IVCoreSettings.wikipedia_locales.has(locale):
			IVGlobal.wiki = locale + ".wikipedia"
		else:
			IVGlobal.wiki = "en.wikipedia"
	
	IVGlobal.project_objects_instantiated.connect(_remove_self)



func _remove_self() -> void:
	IVGlobal.program.erase(&"WikiInitializer")
