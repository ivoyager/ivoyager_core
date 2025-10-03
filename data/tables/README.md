# I, Voyager Data Tables

For table construction rules, see [ivoyager_tables/README.md](https://github.com/ivoyager/ivoyager_tables/blob/master/README.md).

Projects can add, remove or replace tables by modifying values in the "tables" dictionary in [IVTableInitializer](https://github.com/ivoyager/ivoyager_core/blob/master/initializers/table_initializer.gd). Alternatively, it's possible to modify existing table data by constructing ["mod" tables](https://github.com/ivoyager/ivoyager_tables/blob/master/README.md#db_entities_mod-format). 

#### Table Editor Warning!

Most .csv/.tsv file editors will "interpret" and change (i.e., corrupt) table data without any warning, including numbers and text that looks even vaguely like dates (or perhaps other things). Excel is especially agressive in stripping out precision in large or small numbers, e.g., "1.32712440018E+20" converts to "1.33E+20" on saving. One editor that does NOT change data without your input is [Rons Data Edit](https://www.ronsplace.ca/Products/RonsDataEdit). There is a free version that will let you work with files with up to 1000 rows.

*****

## asteroids.tsv

See [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/body.gd) and [IVTableBodyBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_body_builder.gd).

This table includes only the individually instantiated asteroids, which are all of the "visited" asteroids that we have 3D models for. (Our 70,000+ asteroids are defined in binary files and sorted into groups defined in [small_bodies_groups.tsv](#small_bodies_groupstsv).)

## body_classes.tsv

Used only for GUI info display of "Classification". E.g., "Terrestrial Planet", "Gas Giant", "C-Type Asteroid", etc. See [models.tsv](#modelstsv) for types that affect 3D model representation.

## camera_attributes.tsv

Used by [IVWorldEnvironment](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/world_environment.gd) to set CameraAttributrutes parameters.

## dynamic_lights.tsv

Used to create [IVDynamicLight](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/dynamic_light.gd) instances for shadow casting.

## environments.tsv

Used by [IVWorldEnvironment](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/world_environment.gd) to set Environment parameters.

## file_adjustments.tsv

Asset file adjustments. Default ("assumed") values are hard-coded so we don't have to include all files here.

Maps are assumed to have prime meridian at center and longitude 180° at edge, as is typical for maps of Earth and the Moon. If different, include here with `map_offset`. If a body has both albedo and emission maps, only one needs to be included here (if both are included, code will assert equal `map_offset`).

Model scale is assumed to be 1 meter (1:1). If different, include here with `model_scale`. Asteroids more commonly have a scale of 1000 m (1:1000).

## models.tsv

Fields are used by [IVModelSpace](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/model_space.gd) to build or modify 3D models for IVBody instances. All `spheroid` models share the same sphere mesh, scaled for size and oblateness.

Many of the model types are meant to facilitate graphic differences for different kinds of worlds or bodies such as "icy", "thick atmosphere", "volcanic", etc. But we haven't implemented actual graphic differences yet. (We need help from someone competent in 3D visuals!)

## moons.tsv

See [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/body.gd) and [IVTableBodyBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_body_builder.gd).

Source: https://ssd.jpl.nasa.gov/?sat_elem.

P_apsidal (apsidal_period) for the Moon from above source (5.997) is in conflict with other sources (e.g., Wikipedia: 8.85). WTH?

Sort each planet's moons by `semi_major_axis` for proper order in GUI display and selection.

## omni_lights.tsv

Used to build simple OmniLight instances. See light-building code in [IVBodyFinisher](https://github.com/ivoyager/ivoyager_core/blob/master/program/body_finisher.gd).

if `disable_if_dynamic_enabled` is TRUE (default) and renderer mode allows, code will prefer to build an IVDynamicLight instance instead (this is necessary for shadows).

## planets.tsv

See [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/body.gd) and [IVTableBodyBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_body_builder.gd).

Keplarian elements and rates are from https://ssd.jpl.nasa.gov/?planet_pos (data for 3000BC to 3000AD). Earth is really Earth-Moon barycenter. Note that an earlier version of this page had data for Pluto. Ceres was added using AstDyS-2 proper elements.

Physical characteristics are mostly from https://ssd.jpl.nasa.gov/?planet_phys_par or Wikipedia.

Sort planets by `semi_major_axis` for proper order in GUI display and selection.

## rings.tsv

Used by [IVRings](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/rings.gd) to build visual planetary rings and associated shadow casters.

We only have Saturn's rings now.

## small_bodies_groups.tsv

See [IVSmallBodiesGroup](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/small_bodies_group.gd), [IVTableSBGBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_sbg_builder.gd) and [IVBinaryAsteroidsBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/binary_asteroids_builder.gd).

This table defines groups instantiated as IVSmallBodiesGroup instances. At this time these are only asteroid groups, although the class is designed for other groupings of 1000s to 100,000s of bodies. For example, someday we may add 10000s of "Earth satellites".

Table fields are used by the Core plugin and/or [ivbinary_maker](https://github.com/ivoyager/ivbinary_maker). The later generated the binary files present in ivoyager_assets/asteroid_binaries/. **Edit this table with care!** Most columns (except for colors and en.wikipedia) are used to make binaries and should not be changed unless rebuilding binaries. E.g., `sbg_alias` is used by Core but it needs to be consistent with existing binary files.  

`mag_cutoff` is used by ivbinary_maker and the Core plugin. Core can reduce the number of asteroids loaded by reducing this number, but it can't add asteroids that are not already in the binary files.

Asteroids were sorted into groups by ivbinary_maker based on criteria fields in this table (`min_q`, `max_q`, `min_a`, etc.). Groups are based on https://en.wikipedia.org/wiki/List_of_minor_planets#Orbital_groups with some modification so there are no excluded orbits. Each asteroid is added to the first group that does not exclude it based on table criteria. q, perihelion; a, semimajor axis; e, eccentricity; i, inclination. For each group, binaries are created representing half-integer ranges of magnitude (up to `mag_cutoff`).

## spacecrafts.tsv

See [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/body.gd) and [IVTableBodyBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_body_builder.gd).

We only have a few at the moment. We would like to add more but [need 3D models!](https://github.com/ivoyager/ivoyager_core/issues/2)

## stars.tsv

See [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/body.gd) and [IVTableBodyBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_body_builder.gd).

We only have one! Data is mostly from Wikipedia.

## views.tsv

Defines default [IVView](https://github.com/ivoyager/ivoyager_core/blob/master/tree_refs/view.gd) instances generated by [IVViewManager](https://github.com/ivoyager/ivoyager_core/blob/master/program/view_manager.gd). These optionally define a camera position (relative to specified body), camera "tracking" state (ground, orbit, eclipitc), HUDs state (color and visibility), and/or time state.

## visual_groups.tsv

Defines IVBody visual groups for [IVBodyHUDsState](https://github.com/ivoyager/ivoyager_core/blob/master/program/body_huds_state.gd) ("true planest", "dwarf planets", etc.). It specifies default values for HUD orbit colors and label visibilities.

## wiki_extras.tsv

This table has Wikipedia page titles for concepts (really text keys) like LABEL_ECCENTRICITY that are not entities in other tables. There is a field "en.wikipedia" in most other tables that has page titles for "entity" items like PLANET_MERCURY.
