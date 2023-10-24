# Changelog

This file documents changes to [ivoyager_core](https://github.com/ivoyager/ivoyager_core).

Assets are not Git-tracked and must be downloaded from official releases [here](https://github.com/ivoyager/ivoyager_core/releases) or development (non-release) assets [here](https://github.com/ivoyager/non_release_assets/releases).

File format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

See cloning and downloading instructions [here](https://www.ivoyager.dev/developers/).

## [v0.0.18] - Not Released

Under development using Godot 4.2.beta2. _Has backward breaking changes!_

Requires non-Git-tracked, non-release **ivoyager_assets-0.0.18.dev.20231019**; find [here](https://github.com/ivoyager/non_release_assets/releases/tag/2023-10-19).    
Requires plugin [ivoyager_table_reader](https://github.com/ivoyager/ivoyager_table_importer) v0.0.6

### Changed
* Use static vars for localized class items.
* For loop typing and error fixes for Godot 4.2.
* Removed functions '_on_init', '_on_ready', '_on_process', etc. These were needed in Godot 3.x because virtual functions could not be overridden by subclasses. This is no longer the case.
* Removed number & unit names from translation (now added in ivoyager_table_importer).

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

[v0.0.18]: https://github.com/ivoyager/ivoyager/compare/v0.0.17...HEAD
