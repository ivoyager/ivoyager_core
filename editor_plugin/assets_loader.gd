# assets_loader.gd
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
@tool
extends HTTPRequest

# Starts when added to the tree. Self-frees after completion or failure.

const ASSETS_DIR := "res://addons/ivoyager_assets"
const TEMP_FILE := "ivoyager_assets.zip"
const UNZIP_PREPEND := "res://addons/"

var _source: String
var _version: String
var _size_bytes: float
var _percent_downloaded := 0


func _init(source: String, version: String, size_mib: float) -> void:
	_source = source
	_version = version
	_size_bytes = size_mib * 1048576.0
	download_file = OS.get_temp_dir().path_join(TEMP_FILE)
	use_threads = true


func _ready() -> void:
	print("\nDownloading ivoyager_assets %s from\n%s" % [_version, _source])
	print("to temporary file %s..." % download_file)
	request_completed.connect(_on_request_completed)
	var error := request(_source)
	if error != HTTPRequest.RESULT_SUCCESS:
		push_error("There was an error in the HTTPRequest! Error = ", error)
		queue_free()


func _process(_delta: float) -> void:
	var bytes := get_downloaded_bytes()
	var percent := roundi(100 * bytes / _size_bytes)
	if percent >= _percent_downloaded + 10:
		_percent_downloaded += 10
		print("%s%% downloaded (%.1f MiB)" % [_percent_downloaded, bytes / 1048576.0])


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray,
		_body: PackedByteArray) -> void:
	print("HTTPRequest completed; response_code = %s" % response_code)
	set_process(false)
	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("Could not download ivoyager_assets; result = %s, response_code = %s"
				% [result, response_code])
		queue_free()
		return
	_replace_assets.call_deferred()


func _replace_assets() -> void:
	var zip_reader := ZIPReader.new()
	var error := zip_reader.open(download_file)
	if error != OK:
		push_error("Could not open zip archive at %s" % download_file)
		queue_free()
		return
	
	if DirAccess.dir_exists_absolute(ASSETS_DIR):
		print("Moving old ivoyager_assets to trash...")
		OS.move_to_trash(ProjectSettings.globalize_path(ASSETS_DIR))
	
	print("Uncompressing new ivoyager_assets...")
	await get_tree().process_frame
	var count := 0
	for zip_path in zip_reader.get_files():
		if zip_path.get_extension() == "": # is directory
			continue
		assert(zip_path.begins_with("ivoyager_assets/"))
		var file_data := zip_reader.read_file(zip_path)
		var file_path := UNZIP_PREPEND + zip_path
		var dir_path := file_path.get_base_dir()
		if !DirAccess.dir_exists_absolute(dir_path):
			DirAccess.make_dir_recursive_absolute(dir_path)
		var file := FileAccess.open(file_path, FileAccess.WRITE)
		if !file:
			push_error("Could not open file for write at %s" % file_path)
			queue_free()
			return
		file.store_buffer(file_data)
		count += 1
	zip_reader.close()
	print("Added %s files to %s" % [count, ASSETS_DIR])
	await get_tree().process_frame
	print("Removing temporary download file ", download_file)
	DirAccess.remove_absolute(download_file)
	print(
"""

*******************************************************************************
New or updated assets have been added at res://addons/ivoyager_assets.
It's sometimes necessesary restart the Editor to trigger (re)import of assets.
Clicking off and then on the Editor window may also work.
*******************************************************************************

"""
	)
	
	queue_free()
