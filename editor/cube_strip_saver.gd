# cube_strip_saver.gd
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
@tool
class_name IVCubeStripSaver
extends Object

## Editor-only helper that writes a cube-face strip [Image] into the cubemaps asset
## directory as [code]<file_prefix>.<channel>.<face_size>.png[/code] with the
## [code].import[/code] that makes Godot slice it into a [CompressedCubemap].
##
## [param file_prefix] carries the shell token when there is one ([code]Earth.clouds[/code]),
## exactly as the source map's name does, so a shell overlay round-trips.

const CUBEMAPS_DIR := "res://addons/ivoyager_assets/cubemaps"

## Channel tags, mapped to their two import settings: whether the strip needs BC7
## rather than BC1, and whether its data is linear rather than sRGB-friendly. An
## object-space normal needs both — BC1's 5:6:5 bands a normal badly. A strip that kept
## alpha takes BC7 as well, whatever its tag; see [method save_strip].
const CHANNELS: Dictionary[StringName, Array] = {
	&"albedo": [false, 0],
	&"normal": [true, 1],
	&"roughness": [false, 1],
	&"emission": [false, 0],
}

# Written verbatim rather than through ConfigFile so it stays byte-identical to
# bake_cubemap.py's IMPORT_TEMPLATE, which is the thing it has to agree with. The importer
# is "cubemap_texture": "cubemap" is not a registered name and silently falls back to the
# default png importer, yielding a plain 2D texture. arrangement 2 is the 3x2 layout (the
# enum runs 1x6, 2x3, 3x2, 6x1). uid / path / dest_files are omitted so the importer
# generates them on the single reimport.
const _IMPORT_TEMPLATE := """[remap]

importer="cubemap_texture"
type="CompressedCubemap"

[params]

compress/mode=2
compress/high_quality=%s
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/channel_pack=%d
mipmaps/generate=true
mipmaps/limit=-1
slices/arrangement=2
"""


## Writes [param strip] as [code]<prefix>.<channel>.<face_size>.png[/code] plus its
## [code].import[/code], and returns the resource path, or [code]""[/code] on failure.
## Does NOT import — call [method reimport] once after [IVMapConverter] has been freed.
## Importing a texture while a custom [SubViewport] is rendering corrupts the editor's
## GPU/preview state for that session (it breaks thumbnails and crashes manual Reimport on
## some drivers), so writing and importing are deliberately kept apart.
static func save_strip(file_prefix: String, channel: StringName, face_size: int,
		strip: Image) -> String:
	if !CHANNELS.has(channel):
		push_error("Map Convert: '%s' is not a channel tag" % channel)
		return ""
	if !DirAccess.dir_exists_absolute(CUBEMAPS_DIR):
		var directory_error := DirAccess.make_dir_recursive_absolute(CUBEMAPS_DIR)
		if directory_error != OK:
			push_error("Map Convert: could not create '%s' (error %s)"
					% [CUBEMAPS_DIR, directory_error])
			return ""
	var path := CUBEMAPS_DIR.path_join("%s.%s.%d.png" % [file_prefix, channel, face_size])
	var err := strip.save_png(path)
	if err != OK:
		push_error("Map Convert: could not save '%s' (error %s)" % [path, err])
		return ""
	# The strip's own format is the record of whether alpha survived the bake; IVMapConverter
	# keeps it only when the source carried something in it.
	_write_import_file(path, channel, strip.get_format() == Image.FORMAT_RGBA8)
	return path


## Registers and (re)imports [param paths] in one pass. Call only after [IVMapConverter]
## and its [SubViewport] have been freed (see [method save_strip]).
static func reimport(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	var editor_file_system := EditorInterface.get_resource_filesystem()
	for path in paths:
		editor_file_system.update_file(path)
	editor_file_system.reimport_files(paths)


static func _write_import_file(png_path: String, channel: StringName, has_alpha: bool) -> void:
	var settings: Array = CHANNELS[channel]
	# BC7 for alpha: mode 2 would otherwise pick BC3, which costs the same 8 bpp and
	# resolves alpha worse. bake_cubemap.py's save_strip() decides this the same way.
	var high_quality: bool = settings[0] or has_alpha
	var channel_pack: int = settings[1]
	var text := _IMPORT_TEMPLATE % ["true" if high_quality else "false", channel_pack]
	var file := FileAccess.open(png_path + ".import", FileAccess.WRITE)
	if !file:
		push_error("Map Convert: could not write '%s.import' (error %s)"
				% [png_path, FileAccess.get_open_error()])
		return
	file.store_string(text)
	file.close()
