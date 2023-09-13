# ivoyager_core

WIP

This will become the new core submodule (replacing 'ivoyager') added to the addons directory as an editor plugin. Using Planetarium as example, the new project structure will be:
```
planetarium
 |- addons
    |- ivoyager_assets
    |- ivoyager_core
    |- ivoyager_table_importer
 |- planetarium_stuff
```

The submodule has no ivoyager content yet but it does have a WIP init system that uses config files.

The editor plugin 'core_plugin.gd' does several things:
* Loads config file from project directory at path 'res://ivoyager.cfg'. If that file doesn't exist it makes the file from a template.
* Loads several autoloads. These are defined in 'res://addons/ivoyager_core/ivoyager_base.cfg' and can be modified by 'res://ivoyager.cfg'. In base settup these are 'IVGlobal', 'IVInitializer' and 'IVUnits'.
* [TODO?] Verify that 'ivoyager_assets' is up to date, or offer to download expected or most current version.

The singletons IVGlobal and IVInitializer then use 'res://ivoyager.cfg' to overwrite their own init properties or modify their own container values. (Alternatively, user project can modify singletons directly via an initializer GDScript. User choice.)

