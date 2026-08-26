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

Used only for GUI info display of "Classification". E.g., "Terrestrial Planet", "Gas Giant", "C-Type Asteroid", etc. See [surface_classes.tsv](#surface_classestsv) for the separate classification that affects 3D model representation.

## camera_attributes.tsv

Used by [IVWorldEnvironment](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/world_environment.gd) to set CameraAttributrutes parameters.

## dynamic_lights.tsv

Used to create [IVDynamicLight](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/dynamic_light.gd) instances for shadow casting.

## environments.tsv

Used by [IVWorldEnvironment](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/world_environment.gd) to set Environment parameters.

## moons.tsv

See [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/body.gd) and [IVTableBodyBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_body_builder.gd).

Orbital elements are in [orbits.tsv](#orbitstsv) (source https://ssd.jpl.nasa.gov/?sat_elem).

Keep each planet's moons in semi-major-axis order (now in orbits.tsv) for proper order in GUI display and selection.

## omni_lights.tsv

Used to build simple OmniLight instances. See light-building code in [IVBodyFinisher](https://github.com/ivoyager/ivoyager_core/blob/master/program/body_finisher.gd).

if `disable_if_dynamic_enabled` is TRUE (default) and renderer mode allows, code will prefer to build an IVDynamicLight instance instead (this is necessary for shadows).

## orbits.tsv

See [IVTableOrbitBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_orbit_builder.gd).

Holds the orbit for every non-root body (planets, moons, asteroids, spacecraft) on one common element set. Each body table references its orbit through a `TABLE_ROW` field `orbit`; a body with no `orbit` value (only the Sun) is the IVBody tree root. The body tables retain a `parent` field for backward compatibility, but it is deprecated and no longer read by Core — orbital parentage comes from this table's `parent` (resolved via the body's `orbit`).

Elements use argument of periapsis (ω), not longitude of periapsis (ϖ), and signed precession rates in deg/Cy throughout. Source epochs are preserved in `epoch_jd` (J2000 if absent); IVTableOrbitBuilder converts to internal J2000.

Convention notes (handled by IVTableOrbitBuilder): `mean_motion` (n) is the sidereal rate dL/dt, not the mean anomaly rate; the builder derives the orbit GM from it. The silent sub-threshold precession cutoff — for near-circular or near-equatorial orbits, where nodal/apsidal precession is meaningless — applies only to body-centric (Laplace/equatorial) reference frames; ecliptic planet/asteroid rates are never zeroed. Comment columns `#nodal_period` and `#apsidal_period` preserve the JPL satellite-elements periods the moon rates were derived from; `apsidal_period` (Pw) is the cycle period of ω measured from the moving node, which is why the Moon's Pw (5.997 yr) differs from its longitude-of-periapsis period (~8.85 yr): 1/(1/5.997 - 1/18.613) ≈ 8.85.

Sources: planets from https://ssd.jpl.nasa.gov/?planet_pos (3000 BC – 3000 AD; Earth is really the Earth-Moon barycenter; an earlier version of that page included Pluto; Ceres from AstDyS-2 proper elements); moons from https://ssd.jpl.nasa.gov/?sat_elem; asteroids and spacecraft from the JPL Small-Body Database and Horizons.

## planets.tsv

See [IVBody](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/body.gd) and [IVTableBodyBuilder](https://github.com/ivoyager/ivoyager_core/blob/master/program/table_body_builder.gd).

Orbital elements are in [orbits.tsv](#orbitstsv).

Physical characteristics are mostly from https://ssd.jpl.nasa.gov/?planet_phys_par or Wikipedia.

`triaxial_size` (moons.tsv) is the measured figure of a body too small to be round: its three **semi-axes** — not diameters — in the IAU order (a toward longitude 0, b toward 90°E, c polar). Several sources publish full dimensions instead, so halve those. It replaces `equatorial_radius`/`polar_radius` for such a body, which need not be set: `IVBody.get_equatorial_radius()` and `get_polar_radius()` read a and c from it. Sources: NAIF generic PCK `pck00011.tpc`, carrying the figures of Archinal et al. (2018) "Report of the IAU Working Group on Cartographic Coordinates and Rotational Elements: 2015" (Metis, Adrastea, Methone, Pallene, Polydeuces, Aegaeon); Karkoschka (2003) *Icarus* 162, 400 (Naiad, Thalassa, Despina, Galatea); Porter et al. (2021), tabulated in Porter et al. (2023) doi:10.3847/PSJ/acde77 (Nix, Hydra, Kerberos).

Keep planets in semi-major-axis order (now in orbits.tsv) for proper order in GUI display and selection.

## rings.tsv

Used by [IVRings](https://github.com/ivoyager/ivoyager_core/blob/master/tree_nodes/rings.gd) to build visual planetary rings and associated shadow casters.

We only have Saturn's rings now.

## shells.tsv

Defines every surface and overlay "shell" built by [IVShellsModel](https://github.com/ivoyager/ivoyager_core/blob/master/tree/shells_model.gd) — the model used for any body with no packed-scene 3D model. Each row is one shell, and is one of two kinds:

* A **body row**, named `SHELL_<body_name>_<tag>` and listed by its tag in the body's `shells` field (`ARRAY[STRING]`, e.g. `SURFACE;CLOUDS;LIMB`). The row flagged `shell0` is that body's surface; the rest are overlays.
* A **surface-class row**, identified by its `surface_class` field. This is the default surface for every body of that class, used when the body lists no `shell0` row of its own. A body row that *is* `shell0` replaces the class row wholly — the two are never merged, so such a row must restate everything it wants.

Structural columns are `surface_class`, `shell0`, `scale`, `file_tag`, `shader`, `process`, `process_args`, `is_sun` and `cast_shadow`. **Every other column is applied directly to the shell's material**, as a `StandardMaterial3D` property or — when the row names a `shader` — as the shader uniform of the same name. To expose a new material knob, just add that property's column; it is validated per shell at build time.

`scale` is a multiplier on the body's radius, 1.0 if unset. Overlays require one and must differ from each other (equal scales z-fight); values below 1.0 sit under the surface. A surface may carry one too, for a body whose visible "surface" is not at its mean radius — Venus's is its cloud top, ~65 km up. Scales are always measured against the body, so a scaled surface does not drag its overlays outward with it.

No shell needs a texture. `albedo_color` alone gives a uniform shell, and a surface with no color map at all falls back to its surface class's `fallback_color`.

Two kinds of value reach a shader shell beyond its own row's columns. Every shader material is handed the body's geometry as uniforms it may or may not declare — `body_radius_km`, `shell_scale` (its own) and `surface_scale` (shell 0's) — so a shader can work in kilometres of altitude above the disc. **Those kilometres are a shader frame, not an [IVUnits] quantity, and the `atm_*_km` columns must stay unitless in the `Unit` row.** `IVShellsModel` converts once, at `body_radius_km = _mean_radius / IVUnits.KM`, and everything the shader does with altitude is referred to that; giving the columns a `km` unit would have the table importer scale them into internal units while the shader still works in kilometres, which changes every altitude by `IVUnits.KM` and reports nothing. And the **`atm_*` columns** (the atmosphere the limb shader draws: Rayleigh gas, haze and detached-layer optical depths, scale heights, albedos and asymmetries, plus the haze's own top) are authored on the body's limb row only and propagated to shell 0 and every other shell, so the surface and cloud shaders redden their direct light through the same atmosphere. A limb shell's `scale` is not cosmetic: the shader draws on its front faces, so a ray whose tangent altitude clears the shell gets no fragment at all, and the atmosphere is cut off there. Size it above the altitude the profile fades out at when the camera is fully dark-adapted with a lit limb in frame — about 8 extra e-folds above the correctly exposed edge (the build project's `scratch/limb/shell_sizing2.py` computes it per body from the engine's own metering numbers). The shader takes the last few scale heights smoothly to zero regardless, so an under-sized shell costs the faintest part of the roll-off rather than showing an edge. A body's `perspective_radius` (its body table) should then cover that shell: the camera's closest approach is 1.2 of that radius and its near plane 0.1 of the distance, so a shell taller than about 1.08 × the perspective radius is near-plane-clipped at the floor — Titan's haze shell is why its `perspective_radius` is 3644 km on a 2575 km body.

`exposure_ceiling` and `limb_exposure_ceiling` are the cells the camera reads (see [PHOTOMETRIC_MODEL.md](../PHOTOMETRIC_MODEL.md)). Both assert an exposure the camera may not exceed while the shell is in view. Leave them blank unless a shell renders something whose brightness in the frame is a matter of taste rather than a photometric fact: an atmosphere limb clips against a correctly exposed disc, and whether the viewer wants that or wants the limb's own structure is not a question the metering can answer. Lower candidates still win, so a ceiling only ever acts where the others release.

The two differ in what holds the ceiling. `exposure_ceiling` is held by the shell's own screen area and by nothing else — not phase, not lit fraction, not luminance. Earth's surface shell is the filled cell, for its city lights. `limb_exposure_ceiling` belongs to an atmosphere limb row, and is held by the part of that limb that is **sunlit, forward-scattering and in the frame**: a limb is a ring, not a disc, so the camera compensates for one only while the ring is the view, and a limb lit from the camera's own side is not a ring anyone is looking at. Zoom inside the ring or pan it out of the window and the ceiling releases entirely, which is what lets a close pass over Venus, Mars or Titan run at the full dark-adapted exposure. How readily a limb may clip before the camera answers for it is `IVExposureManager.limb_meter_fraction_start` / `_full` and `limb_meter_edge_fraction`, not the cell.

Both of a limb row's radii are load-bearing, and they do different jobs. The ring is sampled on the **disc's** silhouette — the limb's foot, which is where its light is and where a viewer sees it — while the limb row's `scale` sets the **height** carried above each of those feet, and the shell's screen area is what the lit share scales. Close in the two silhouettes are far apart (from Titan's camera floor the disc's stands 41° off axis and the shell's 56°), so sampling the shell put every question about the limb 15° further around the body than the limb the viewer was looking at.

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

## surface_classes.tsv

An enumeration of body surface types — `G_STAR`, `ROCKY_WORLD`, `ICE_GIANT`, `C_TYPE_BODY`, etc., with `FALLBACK` last. Every body table has a `surface_class` column selecting one; several set a table `Default` (moons and asteroids `C_TYPE_BODY`, spacecraft `FALLBACK`). Use a `*_WORLD` class for planetary-mass objects and a `*_TYPE_BODY` class for small moons and asteroids.

A class's appearance lives in its [shells.tsv](#shellstsv) row. This table holds only what a body of that class falls back to when it has no assets of its own:

* `fallback_mesh_path` / `fallback_mesh_size` — a generic mesh standing in for any body of the class, and the mean radius that mesh represents (it is resized to each body's own). No class sets one now; a class with no mesh, or one whose file is absent, falls through — Core runs without the asset bundle.
* `fallback_triaxial_size` — generic semi-axes for a body of the class with no figure of its own, shaping the shared sphere instead of a mesh. Any scaling of the three works: they are normalized to the body's own mean radius. The `*_TYPE_BODY` classes use the median axis ratios of the small bodies whose figure has been measured, so an unresolved small body reads as irregular without claiming a shape it does not have.
* `fallback_color` — the surface color when the body ships no albedo or emission map. Default `gray`.

Precedence for a body's model is: packed scene (models/) > its own mesh (meshes/) > its class's `fallback_mesh_path` > its own `triaxial_size` (body tables) > its class's `fallback_triaxial_size` > its oblate radii > the shared sphere.

## views.tsv

Defines default [IVView](https://github.com/ivoyager/ivoyager_core/blob/master/tree_refs/view.gd) instances generated by [IVViewManager](https://github.com/ivoyager/ivoyager_core/blob/master/program/view_manager.gd). These optionally define a camera position (relative to specified body), camera "tracking" state (ground, orbit, eclipitc), HUDs state (color and visibility), and/or time state.

## visual_groups.tsv

Defines IVBody visual groups for [IVBodyHUDsState](https://github.com/ivoyager/ivoyager_core/blob/master/program/body_huds_state.gd) ("true planest", "dwarf planets", etc.). It specifies default values for HUD orbit colors and label visibilities.

## wiki_extras.tsv

This table has Wikipedia page titles for concepts (really text keys) like LABEL_ECCENTRICITY that are not entities in other tables. There is a field "en.wikipedia" in most other tables that has page titles for "entity" items like PLANET_MERCURY.
