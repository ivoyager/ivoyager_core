# table_initializer.gd
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
class_name IVTableInitializer
extends RefCounted

## Initializes tables using the ivoyager_tables plugin.
##
## All parameters sent for table postprocessing can be modified in
## [IVCoreSettings].


func _init() -> void:
	
	IVTableData.postprocess_tables(
			IVCoreSettings.tables.values(),
			IVQConvert.convert_quantity,
			IVCoreSettings.enable_wiki,
			IVCoreSettings.enable_precisions,
			IVCoreSettings.table_project_enums,
			IVCoreSettings.merge_table_constants,
			IVCoreSettings.replacement_missing_values,
	)
	
	# signal done
	IVGlobal.data_tables_imported.emit()
	
	IVGlobal.program.erase(&"TableInitializer")
