# editor_plugin.gd
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
extends EditorPlugin

# This file adds autoloads and shader globals for ivoyager_core. You can change
# these by editing res://ivoyager_override.cfg in your project directory. See
# res://addons/ivoyager_core/ivoyager_core.cfg for base values and comments.
#
# If you modify autoloads or shader globals, you'll need to disable and re-
# enable the plugin (or quit and restart the editor) for your changes to have
# effect.
#
# The editor plugin also checks ivoyager_assets presence and version and offers
# to download current assets if appropriate.

const REQUIRED_PLUGINS: Array[String] = ["ivoyager_units", "ivoyager_tables"]

var _config: ConfigFile # with overrides
var _autoloads: Dictionary[String, String] = {}
var _shader_globals: Dictionary[String, Dictionary] = {}


func _enter_tree() -> void:
	
	# Wait for required plugins...
	await get_tree().process_frame
	var wait_counter := 0
	while !_is_required_plugins_enabled():
		wait_counter += 1
		if wait_counter == 10:
			push_error("Enable required plugins before ivoyager_core: " + str(REQUIRED_PLUGINS))
			push_error("After enabling plugins above, you MUST disable & re-enable ivoyager_core!")
			return
		await get_tree().process_frame
	
	IVPluginUtils.print_plugin_name_and_version("ivoyager_core", " - https://ivoyager.dev")
	_process_ivoyager_cofig_files()
	_add_autoloads()
	_add_shader_globals()
	_handle_assets_update()


func _exit_tree() -> void:
	# We don't remove shader globals here because it causes errors on startup
	# when they are used by external projects.
	print("Removing I, Voyager - Core (plugin)")
	_config = null
	_remove_autoloads()


func _is_required_plugins_enabled() -> bool:
	for plugin in REQUIRED_PLUGINS:
		if !EditorInterface.is_plugin_enabled(plugin):
			return false
	return true


func _process_ivoyager_cofig_files() -> void:
	_config = IVPluginUtils.get_ivoyager_config("res://addons/ivoyager_core/ivoyager_core.cfg")
	if !_config:
		push_error("Could not load config at res://addons/ivoyager_core/ivoyager_core.cfg")
		return
	
	# init project ivoyager_override.cfg if it doesn't exist
	if IVPluginUtils.config_exists("res://ivoyager_override.cfg"):
		return
	var dir := DirAccess.open("res://addons/ivoyager_core/")
	var err := dir.copy("res://addons/ivoyager_core/override_template.cfg",
			"res://ivoyager_override.cfg")
	if err != OK:
		push_error("Failed to copy 'ivoyager_override.cfg' to the project directory")
		return
	print(
"""

*******************************************************************************
Created config 'ivoyager_override.cfg' in your project directory. Modify this
file to change the behavior of 'ivoyager_core' and other 'ivoyager_' plugins.
*******************************************************************************

"""
	)


func _add_autoloads() -> void:
	for autoload_name in _config.get_section_keys("core_autoload"):
		var value: Variant = _config.get_value("core_autoload", autoload_name)
		if value: # could be null or "" to negate
			assert(typeof(value) == TYPE_STRING,
					"'%s' must specify a path as String" % autoload_name)
			_autoloads[autoload_name] = value
	for autoload_name in _autoloads:
#		await get_tree().process_frame
		var path := _autoloads[autoload_name]
		add_autoload_singleton(autoload_name, path)


func _remove_autoloads() -> void:
	for autoload_name: String in _autoloads:
		remove_autoload_singleton(autoload_name)
	_autoloads.clear()


func _add_shader_globals() -> void:
	for global_name in _config.get_section_keys("core_shader_globals"):
		var value: Variant = _config.get_value("core_shader_globals", global_name)
		if value: # could be null or {} to negate
			assert(typeof(value) == TYPE_DICTIONARY, "'%s' must specify a Dictionary" % global_name)
			_shader_globals[global_name] = value
	for global_name: String in _shader_globals:
		var dict: Dictionary = _shader_globals[global_name]
		ProjectSettings.set_setting("shader_globals/" + global_name, dict)
		# These don't show up in editor menu immediately, but are in project.godot
		# and show up in editor menu after restart.
	ProjectSettings.save() # Does this do anything...???


func _handle_assets_update() -> void:
	var disable_asset_loader: bool = _config.get_value("ivoyager_assets", "disable_asset_loader")
	if disable_asset_loader:
		return
	
	# Delay allows other Editor setup and is aesthetically pleasing...
	for i in 20:
		await get_tree().process_frame
	
	var expected_version: String = _config.get_value("ivoyager_assets", "version")
	var present_version := ""
	var assets_config := IVPluginUtils.get_config("res://addons/ivoyager_assets/assets.cfg")
	
	if assets_config:
		if assets_config.has_section("ivoyager_assets"):
			present_version = assets_config.get_value("ivoyager_assets", "version")
		if present_version == expected_version:
			return # We're good!
	
	var message := ""
	if !present_version:
		message = (
"""
Plugin 'ivoyager_core' requires assets to run!

Press 'Download' to download assets %s and install at addons/ivoyager_assets.

Press 'Cancel' to manage assets manually. See https://ivoyager.dev/developers.

Check download progress in the Output window. You may need to restart the Editor
to trigger asset import after download.
"""
		) % expected_version
	else:
		message = (
"""
'ivoyager_assets' version %s does not match expected %s.

Press 'Download' to download assets %s and replace existing addons/ivoyager_assets.

Press 'Cancel' to manage assets manually. See https://ivoyager.dev/developers.

Check download progress in the Output window. You may need to restart the Editor
to trigger asset import after download.
"""
		) % [present_version, expected_version, expected_version]
	
	# Don't popup download dialog while the plugins window or other exclusive
	# window is open (e.g., progress bar if the Editor is working on someting).
	var last_exclusive_window := get_last_exclusive_window()
	if last_exclusive_window == get_window(): # no exclusive popup window now
		_popup_download_confirmation(message)
	else:
		last_exclusive_window.visibility_changed.connect(
				_popup_download_confirmation.bind(message), CONNECT_ONE_SHOT)


func _popup_download_confirmation(message: String) -> void:
	# Create and destroy one-shot confirmation dialog.
	await get_tree().process_frame
	var confirm_dialog := ConfirmationDialog.new()
	confirm_dialog.confirmed.connect(_init_assets_loader)
	confirm_dialog.confirmed.connect(confirm_dialog.queue_free)
	confirm_dialog.canceled.connect(confirm_dialog.queue_free)
	confirm_dialog.dialog_text = message
	confirm_dialog.ok_button_text = "Download"
	var editor_gui := EditorInterface.get_base_control()
	editor_gui.add_child(confirm_dialog)
	confirm_dialog.popup_centered()


func _init_assets_loader() -> void:
	var version: String = _config.get_value("ivoyager_assets", "version")
	var source: String = _config.get_value("ivoyager_assets", "source")
	var size_mib: float = _config.get_value("ivoyager_assets", "size_mib")
	var assets_loader := preload("assets_loader.gd").new(source, version, size_mib)
	add_child(assets_loader)
