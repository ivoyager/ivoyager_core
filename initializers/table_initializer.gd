# table_initializer.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charlie Whitfield
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
class_name IVTableInitializer
extends RefCounted

## Initializes tables using the ivoyager_table_importer plugin.
##
## All parameters sent for table postprocessing can be modified in
## [IVCoreSettings].


func _init() -> void:
	
	# Add compound units so Table Importer doesn't have to parse strings. This
	# isn't necessary but might save a few microseconds.
	IVUnits.unit_multipliers[&"m^3/s^2"] =  IVUnits.METER ** 3 / IVUnits.SECOND ** 2
	IVUnits.unit_multipliers[&"km^3/s^2"] = IVUnits.KM ** 3 / IVUnits.SECOND ** 2
	IVUnits.unit_multipliers[&"m^3/(kg s^2)"] = IVUnits.METER ** 3 / (IVUnits.KG * IVUnits.SECOND ** 2)
	IVUnits.unit_multipliers[&"km^3/(kg s^2)"] = IVUnits.KM ** 3 / (IVUnits.KG * IVUnits.SECOND ** 2)
	IVUnits.unit_multipliers[&"deg/Cy^2"] = IVUnits.DEG / IVUnits.CENTURY ** 2
	
	IVTableData.postprocess_tables(
			IVCoreSettings.tables.values(),
			IVCoreSettings.table_project_enums,
			IVCoreSettings.enable_wiki,
			IVCoreSettings.enable_precisions,
			IVCoreSettings.merge_table_constants,
			IVCoreSettings.replacement_missing_values,
	)
	
	# signal done
	IVGlobal.data_tables_imported.emit()
	
	IVGlobal.program.erase(&"TableInitializer")
