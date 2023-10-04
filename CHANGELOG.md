# Changelog

This file documents changes to [ivoyager_core](https://github.com/ivoyager/ivoyager_core).

Assets are not Git-tracked and must be downloaded from official releases [here](https://github.com/ivoyager/ivoyager_core/releases) or development (non-release) assets [here](https://github.com/ivoyager/non_release_assets/releases).

File format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

See cloning and downloading instructions [here](https://www.ivoyager.dev/developers/).

## v0.0.17 - 2023-10-03

Developed using Godot 4.1.1.

Requires non-Git-tracked **ivoyager_assets-0.0.17**; find in ivoyager_core [releases](https://github.com/ivoyager/ivoyager_core/releases).    
Requires plugin [ivoyager_table_reader](https://github.com/ivoyager/ivoyager_table_importer) v0.0.5.

#### Added
* Core submodule content previously in [ivoyager](https://github.com/ivoyager/ivoyager) v0.0.16.

#### Changed
* ivoyager_core works as an editor plugin!
* All autoload singletons, shader globals, project settings, and class definitions can be modified by editing res://ivoyager_overrides.cfg.
* Previous project settings in IVGlobal have been moved to IVCoreSettings.
* Previous class definitions in IVProjectBuilder have been moved to IVCoreInitializer.


##
I, Voyager projects v0.0.16 and earlier used a different core submodule [ivoyager](https://github.com/ivoyager/ivoyager) (now depreciated); see previous changelog [here](https://github.com/ivoyager/ivoyager/blob/master/CHANGELOG.md).

