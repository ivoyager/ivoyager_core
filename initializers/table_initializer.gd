# table_initializer.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2024 Charles Whitfield
# I, Voyager is a registered trademark of Charles Whitfield in the US
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

# Postprocess tables specified in IVCoreSettings using Table Reader plugin.
# Table data will be ready to use after 'data_tables_imported' signal, which
# will happen while 'initializers' are added in ProjectBuilder.


func _init() -> void:
	
	# add compound units so Table Importer doesn't have to parse
	IVUnits.unit_multipliers[&"m^3/s^2"] =  IVUnits.METER ** 3 / IVUnits.SECOND ** 2
	IVUnits.unit_multipliers[&"km^3/s^2"] = IVUnits.KM ** 3 / IVUnits.SECOND ** 2
	IVUnits.unit_multipliers[&"m^3/(kg s^2)"] = IVUnits.METER ** 3 / (IVUnits.KG * IVUnits.SECOND ** 2)
	IVUnits.unit_multipliers[&"km^3/(kg s^2)"] = IVUnits.KM ** 3 / (IVUnits.KG * IVUnits.SECOND ** 2)
	IVUnits.unit_multipliers[&"deg/Cy^2"] = IVUnits.DEG / IVUnits.CENTURY ** 2
	
	IVTableData.postprocess_tables(
			IVCoreSettings.postprocess_tables,
			IVCoreSettings.table_project_enums,
			IVCoreSettings.enable_wiki,
			IVCoreSettings.enable_precisions
	)
	
	# signal done
	IVGlobal.data_tables_imported.emit()
	
	IVGlobal.program.erase(&"TableInitializer")

