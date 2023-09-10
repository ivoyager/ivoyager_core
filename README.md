# ivoyager_core
WIP

This will become the new core submodule (replacing 'ivoyager') to be housed in addons as an editor plugin. Using Planetarium as example, the new project structure will be:
```
planetarium
 |- addons
    |- ivoyager_assets
    |- ivoyager_core
    |- ivoyager_table_importer
 |- planetarium_stuff
```

The init file 'core_plugin.gd' will do several things:
* Add IVGlobal autoload singleton.
* Read 'ivoyager.cfg' file, then read project overrides 'res://ivoyager_overrides.cfg' if it exists.
* From config data, set SI base units.
* From config data, set all project vars in IVGlobal.
* From config data, define all ivoyager classes using `add_custom_type()`. In this new approach we will avoid using 'class_name' in all files. This will give user the option to subclass or replace any class seamlessly. They could easily break script compilation, but that's ok.
* [maybe] Verify that 'ivoyager_assets' is up to date, or offer to download expected or most current version.

