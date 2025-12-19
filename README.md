# I, Voyager - Core (plugin)

This Godot Editor plugin runs an orbital simulation, with content data tables and binaries representing our Solar System.

[Homepage](https://www.ivoyager.dev) | [Forum](https://github.com/orgs/ivoyager/discussions) | [Issues](https://github.com/ivoyager/ivoyager_core/issues) | [Changelog](https://github.com/ivoyager/ivoyager_core/blob/master/CHANGELOG.md)  

### Overview

Functionality of this plugin can be modified extensively using external scripts and/or config files. It's best to view documentation from within the Godot Editor, but here are repository links to key document classes:

* [IVUniverseTemplate](https://github.com/ivoyager/ivoyager_core/blob/master/tree/universe_template.gd) for scene tree construction.
* [IVCoreInitializer](https://github.com/ivoyager/ivoyager_core/blob/master/singletons/core_initializer.gd) & [IVCoreSettings](https://github.com/ivoyager/ivoyager_core/blob/master/singletons/core_settings.gd) for plugin init & settings.
* [IVGlobal](https://github.com/ivoyager/ivoyager_core/blob/master/singletons/global.gd) & [IVStateManager](https://github.com/ivoyager/ivoyager_core/blob/master/singletons/state_manager.gd) for runtime state management.
* [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree/body.gd) for the physical 3D world.
* [IVOrbit](https://github.com/ivoyager/ivoyager_core/blob/master/tree_components/orbit.gd) for orbital mechanics.

### Requirements

* ivoyager_tables (plugin) - See [repository](https://github.com/ivoyager/ivoyager_tables) for installation instructions.
* ivoyager_units (plugin) - See [repository](https://github.com/ivoyager/ivoyager_units) for installation instructions.
* ivoyager_assets (non-Git-tracked assets) - The Core plugin will download this for you! Just press "Download" at the editor prompt. Alternatively, go [here](https://github.com/ivoyager/asset_downloads).

See [changelog](https://github.com/ivoyager/ivoyager_core/blob/master/CHANGELOG.md) for current version requirements.

### Installation

See our [Developers Page](https://www.ivoyager.dev/developers/).

If you are building a new game or app, we recomend using [Project Template](https://github.com/ivoyager/project_template) as your starting point. See also [Planetarium](https://github.com/ivoyager/planetarium) for a working project using this plugin. 

Instructions below are for adding plugins to an existing project.

The plugin directories `ivoyager_tables`, `ivoyager_units` and `ivoyager_core` should be added _directly to your addons directory_. You can do this one of two ways:

1. Download and extract the plugins, then add (in their entirety) to your addons directory, creating an 'addons' directory in your project if needed.
2. (Recommended) Add as a git submodules. From your project directory, use git commands:  
	`git submodule add https://github.com/ivoyager/ivoyager_tables addons/ivoyager_tables`  
	`git submodule add https://github.com/ivoyager/ivoyager_units addons/ivoyager_units`  
	`git submodule add https://github.com/ivoyager/ivoyager_core addons/ivoyager_core`  
	This method will allow you to version-control the plugins from within your project rather than moving directories manually. You'll be able to pull updates, checkout any commit, or submit pull requests back to us. This does require some learning to use git submodules. (We use [GitKraken](https://www.gitkraken.com/) to make this easier!)

Then enable "I, Voyager - Tables", "I, Voyager - Units" and "I, Voyager - Core" (Core after the other two) from editor menu Project/Project Settings/Plugins. The Core editor plugin will then prompt you to download non-Git-tracked assets.
