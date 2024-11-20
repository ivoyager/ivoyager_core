# Changelog

This file documents changes to [ivoyager_core](https://github.com/ivoyager/ivoyager_core).

File format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

See cloning and downloading instructions [here](https://www.ivoyager.dev/developers/).

## [v0.0.19] - Not Released

Under development using Godot 4.3.

Requires plugin [ivoyager_table_reader](https://github.com/ivoyager/ivoyager_table_importer) v0.0.7.

Requires **ivoyager_assets-v0.0.19.dev.20240906**. (The editor plugin will download if you agree at the prompt.)

### Added
* API support for adding IVSmallBodiesGroup data by code (not just tables/binaries).
* IVBody.remove_and_disable_model_space()
* Shader global 'iv_sun_global_positions' that can track up to 3 suns for shader effects. Used for phase angle in Saturn's Rings.

### Changed
* [API breaking] Improved builder class names with "source" and "what": "BinaryAsteroidsBuilder", "TableBodyBuilder", "TableOrbitBuilder", etc.
* [Project breaking] Removed fake virtual function _ivcore_init().
* [Project breaking] IVCoreInitializer no longer adds admin popups (save dialog, options popup, etc.). Projects can now add these in a more Godot-like manner by constructing a control scene tree.
* Tables specified in IVCoreSettings.body_tables no longer need to be top-down ordered.
* [API breaking] Changed IVCamera fov/focal-length API. Replaced widgets FocalLengthButtons and FocalLengthLabel with new and better better FocalLengthControl.

### Fixed
* Our rings "1D" texture mipmaps are broken in Godot 4.3. This is fixed by explicit LOD coding using separate LOD textures. **Requires asset update!**


## [v0.0.18] - 2024-03-15

Developed using Godot 4.2.1. _Has backward breaking changes!_

Requires plugin [ivoyager_table_reader](https://github.com/ivoyager/ivoyager_table_importer) v0.0.7.

Requires **ivoyager_assets-0.0.18**. **_NEW! The plugin will update this for you! Just press 'Download' at the dialog prompt._** (Alternatively, download [here](https://github.com/ivoyager/non_release_assets/releases/tag/2024-01-29).)


### Added
* Assets download & version management! The editor plugin checks presence and version of ivoyager_assets, and offers to download and add (or replace) as appropriate.
* Class documentation using Godot ## tags (work-in-progress).
* IVWorldEnvironment scene with default Environment and CameraAttributes. Project can specify data tables to override properties in Environment and CameraAttributes.

### Changed
* [ivoyager_assets] Major Neptune color adjustment (and minor Uranus) to match newly published true color estimations.
* [ivoyager_assets] New Titan images to show true atmospheric view rather than radar image.
* Unlocked the time setter widget so year can be set outside of 3000 BC to 3000 AD. The widget now displays a text warning telling user that planet positions are valid in that range. (Widget used in Planetarium.)
* Improved IVSaveBuilder Dictionary handling: a) Persist objects can be keys. b) String versus StringName types are correctly distinguished and persisted as keys.
* [Possibly breaking] Optimized IVSaveBuilder with new rules for Objects in containers: Objects can be in object member Arrays (which must be Object-typed) or object member Dictionaries (as keys or values), but cannot be in nested Arrays or Dictionaries inside of Arrays or Dictionaries. (Pure "data" containers can still be nested at any level.)
* IVSaveBuilder: Improved debug asserts at game save. Throws errors on rule violations that could lead to load problems.
* [API breaking] Removed `IVUtils.free_procedural_nodes()`. Replaced usage with `IVSaveBuilder.free_all_procedural_objects()`. The new function nulls all references to procedural objects (so frees RefCounted instances having circular references) and then frees the Nodes.
* Use static vars for localized class items.
* For loop typing and error fixes for Godot 4.2.
* Removed functions `_on_init()`, `_on_ready()`, `_on_process()`, etc. These were needed in Godot 3.x because virtual functions could not be overridden by subclasses. This is no longer the case.
* Removed number & unit names from translation (now added in ivoyager_table_importer).

### Removed
* IVSaveBuilder class. Save/load functionality has been removed from core and is now added by the [Tree Saver](https://github.com/ivoyager/ivoyager_tree_saver) plugin.

### Fixed
* [Migration regression] Fixed array type error causing crash in `IVTimekeeper.is_valid_gregorian_date()`.

## v0.0.17 - 2023-10-03

Developed using Godot 4.1.1.

Requires non-Git-tracked **ivoyager_assets-0.0.17**; find in ivoyager_core [releases](https://github.com/ivoyager/ivoyager_core/releases).    
Requires plugin [ivoyager_table_reader](https://github.com/ivoyager/ivoyager_table_importer) v0.0.5.

### Added
* Core submodule content previously in [ivoyager](https://github.com/ivoyager/ivoyager) v0.0.16.

### Changed
* ivoyager_core works as an editor plugin!
* All autoload singletons, shader globals, project settings, and class definitions can be modified by editing res://ivoyager_overrides.cfg.
* Previous project settings in IVGlobal have been moved to IVCoreSettings.
* Previous class definitions in IVProjectBuilder have been moved to IVCoreInitializer.


##
I, Voyager projects v0.0.16 and earlier used a different core submodule [ivoyager](https://github.com/ivoyager/ivoyager) (now depreciated); see previous changelog [here](https://github.com/ivoyager/ivoyager/blob/master/CHANGELOG.md).

[v0.0.19]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.18...HEAD
[v0.0.18]: https://github.com/ivoyager/ivoyager_core/compare/v0.0.17...v0.0.18
