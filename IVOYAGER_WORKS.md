# I, Voyager Original Works and Source-Data Attribution

This document catalogs files whose **content originates with I, Voyager** — created by I, Voyager rather than obtained from a third party — together with attribution of the public-domain source data from which they were derived. It also documents I, Voyager-generated derivative outputs (the 2D body icons and the cube-face reprojections), whose copyright and license follow their source, documented in [3RD_PARTY.md](3RD_PARTY.md) where that source is third-party.

A third party's image remains that party's work even after I, Voyager processes it, and is documented in [3RD_PARTY.md](3RD_PARTY.md). General acknowledgments are in [CREDITS.md](CREDITS.md).

The master version of this file is maintained [here](https://github.com/ivoyager/asset_downloads/blob/master/IVOYAGER_WORKS.md).

**Contact:** Charlie Whitfield (mail@ivoyager.dev)

Unless a specific entry below states otherwise, the files in this document are:

- **Copyright:** © Charlie Whitfield (I, Voyager). The underlying source data is public domain, chiefly U.S. Government, except where an entry names its source and terms.
- **License:** [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) (see [LICENSE.txt](LICENSE.txt)); Public Domain for the underlying source data, again except where an entry says otherwise.

These files are distributed from [this repository](https://github.com/ivoyager/asset_downloads) in two packages: `ivoyager_assets`, which installs at `/addons/ivoyager_assets/` in project development builds, and `ivoyager_originated_extras`, which carries the I, Voyager-originated equirectangular map masters from which the corresponding cubemaps are baked.

As of 2026-08, most shipped surface cubemaps (here and in [3RD_PARTY.md](3RD_PARTY.md)) are rescaled in linear light so each map's sphere-averaged reflectance equals the body's V-band geometric albedo — the convention I, Voyager's physically calibrated lighting meters against. The equirectangular masters in `ivoyager_originated_extras` keep their own documented levels; the rescale is a bake-side step.

---

## Europa

The Europa surface map is an I, Voyager original, built from public-domain imagery. It ships as an equirectangular master in `ivoyager_originated_extras` and as the `/cubemaps/Europa.albedo.2048.png` cubemap baked from it in `ivoyager_assets`. Its detail comes from the USGS controlled Voyager/Galileo mosaics of Europa (Bland et al., 2021, released CC0) and the earlier global 500 m monochrome mosaic (Becker et al., 2010), both reprojected from NASA/JPL Galileo SSI and Voyager data. Björn Jónsson's global color map, published by [The Planetary Society](https://www.planetary.org/space-images/color-global-map-of-europa), and his [account of making it](https://www.planetary.org/articles/0218-mapping-europa) guided our method — in particular his technique of carrying low-resolution filter color on a high-resolution grayscale intensity layer.

We build the map from the public-domain data directly. Surface detail is the 500 m controlled monochrome mosaic. No public-domain global *color* map of Europa exists — Galileo's color coverage is sparse, and where it exists it carries little usable per-pixel structure — so we set the color to Europa's true disk average from published photometry: a pale warm-white, linear RGB 1.05 : 1.00 : 0.87, derived from Cassini ISS geometric albedos (Mayorga et al., 2021) and cross-checked against Jupiter's color indices and a Cassini image of the two bodies together. Onto that average we add a gentle reddening of the darker chaos and lineae — physically expected, but finer than the color data resolves, and so an honest reconstruction rather than a measurement. The unimaged south-polar region is left a flat average color.

---

## Mercury

The Mercury surface map is an I, Voyager original, built from public-domain imagery. It ships as an equirectangular master in `ivoyager_originated_extras` and as the `/cubemaps/Mercury.albedo.1024.png` cubemap in `ivoyager_assets`. Its surface detail is the USGS MESSENGER MDIS low-incidence global monochrome basemap (the "LOI" basemap; MESSENGER Team, ASU, Johns Hopkins APL, Carnegie Institution of Washington; via USGS Astrogeology), chosen over the shaded morphology basemap so the albedo carries no baked lighting — relief comes from the engine and the `Mercury.normal` map.

No public-domain true-color global map of Mercury exists — the released MESSENGER color mosaics are false color (near-infrared or principal-component composites) — so the color is ours. We set it to Mercury's true disk-average tint, linear RGB 1.139 : 0.982 : 0.772 (a warm tan-grey), calibrated by integrating the disk-median MDIS visible-band spectrum (the 480/560/630 nm filters, from the public-domain MDIS multispectral records) against the CIE 1931 observer under an equal-energy illuminant. A single flat tint is the honest choice: measured local true-color variation across Mercury is below the perceptual threshold, so surface units (rays, plains, low-reflectance material) read through the grayscale brightness, not color. The permanently-shadowed polar craters and the small never-imaged polar gaps are inpainted from surrounding sunlit terrain.

---

## Body models and surface-relief maps

The 3D body models and surface-relief maps in this section are original works created for I, Voyager. They are not third-party works. They are listed here to attribute the source data from which they were derived — chiefly public-domain NASA mission data (governed by the [NASA Images and Media Usage Guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/)), plus the NOAA ETOPO 2022 global relief model for the Earth maps. The eight custom-mesh bodies (Ceres, Charon, Deimos, Iapetus, Miranda, Phobos, Phoebe, Vesta) each ship as a geometry mesh (`/meshes/<Body>.obj`) plus two cubemaps sampled by surface direction: an albedo (diffuse) cubemap (`/cubemaps/<Body>.albedo.512.png`) and an object-space normal cubemap (`/cubemaps/<Body>.normal.512.png`). The albedo is third-party imagery documented in [3RD_PARTY.md](3RD_PARTY.md), not an I, Voyager work; the mesh and the normal cubemap are I, Voyager works. A further fourteen small moons that no spacecraft has mapped ship a mesh and nothing else; they are listed separately below.

### Custom-mesh bodies (`/meshes/*.obj` + `/cubemaps/*.normal.*.png`)

- `/meshes/Ceres.obj` + `/cubemaps/Ceres.normal.512.png` — derived from the Dawn Framing Camera HAMO global Digital Terrain Model (Preusker et al., 2016; NASA/JPL-Caltech/UCLA/MPS/DLR/IDA).
- `/meshes/Charon.obj` + `/cubemaps/Charon.normal.512.png` — derived from the New Horizons LORRI/MVIC global Digital Elevation Model (Schenk et al., 2018; NASA/Johns Hopkins APL/SwRI). The normal cubemap is flat wherever the albedo carries the unimaged fill, so no relief is shaded over ground the map does not claim.
- `/meshes/Deimos.obj` + `/cubemaps/Deimos.normal.512.png` — derived from the Deimos stereophotoclinometry shape model of Ernst et al. (2023), 20 m ground sample distance, the first shape model to resolve Deimos' geology (C. M. Ernst, R. W. Gaskell et al., *High-resolution shape models of Phobos and Deimos from stereophotoclinometry*, Earth, Planets and Space 75:103, doi:10.1186/s40623-023-01814-7; built from Viking Orbiter, Mars Global Surveyor, Mars Express and Mars Reconnaissance Orbiter imaging and distributed through the Small Body Mapping Tool, Johns Hopkins APL).
- `/meshes/Iapetus.obj` + `/cubemaps/Iapetus.normal.512.png` — an idealized figure based on the published triaxial radii of Thomas et al. (2007); no global Iapetus elevation model is publicly available.
- `/meshes/Miranda.obj` + `/cubemaps/Miranda.normal.512.png` — the triaxial figure of Thomas (1988), 240.4 × 234.2 × 232.9 km, carrying Paul Schenk's controlled Voyager 2 digital elevation model over the imaged hemisphere and relaxing to the bare ellipsoid over the unimaged one (Schenk, P. and Moore, J. (2020), *Philosophical Transactions of the Royal Society A* 378, 20200102; distributed by the Lunar and Planetary Institute, no license asserted; underlying imagery NASA/JPL).
- `/meshes/Phobos.obj` + `/cubemaps/Phobos.normal.512.png` — derived from the Phobos stereophotoclinometry shape model of Ernst et al. (2023), 36 m ground sample distance (same publication and distribution as Deimos above; built from Viking Orbiter, Phobos 2, Mars Global Surveyor, Mars Express and Mars Reconnaissance Orbiter imaging).
- `/meshes/Phoebe.obj` + `/cubemaps/Phoebe.normal.512.png` — derived from the Gaskell stereophotoclinometry shape model (R. Gaskell, Cassini ISS; PDS Small Bodies Node dataset CO-SA-ISSNA-5-PHOEBESHAPE-V2.0).
- `/meshes/Vesta.obj` + `/cubemaps/Vesta.normal.512.png` — derived from the Dawn Framing Camera HAMO global stereophotogrammetric Digital Terrain Model (Preusker et al., 2016; NASA/JPL-Caltech/UCLA/MPS/DLR/IDA).

### Shape meshes for unmapped small moons (`/meshes/*.obj`)

Fourteen small moons have a published shape model but no map worth shipping. They carry a geometry mesh and no textures at all, so they render in their surface class's flat gray and the silhouette alone tells them apart — which is also what marks them as bodies no spacecraft has imaged closely. The meshes are I, Voyager works: each published shape is placed in the engine's authoring frame and decimated to about 2000 triangles, a reduction that moves the modelled surface by 0.1–0.2 % of the body's mean radius. The four Voyager-era shapes are additionally scaled to each moon's currently accepted mean radius, which their own scale predates. (A moon with only a measured *ellipsoid* ships no asset at all — its three semi-axes live in the Core plugin's data tables.)

- `/meshes/Pan.obj`, `/meshes/Daphnis.obj`, `/meshes/Atlas.obj`, `/meshes/Prometheus.obj`, `/meshes/Pandora.obj`, `/meshes/Epimetheus.obj`, `/meshes/Janus.obj`, `/meshes/Telesto.obj`, `/meshes/Calypso.obj`, `/meshes/Helene.obj` — derived from the Cassini ISS shape models of P. Thomas, J. Joseph and T. Ansty (*Saturn Small Moon Shape Models V1.0*, NASA Planetary Data System, 2018, doi:10.26033/ewy3-jy61), solved from control-point stereogrammetry with limb and terminator constraints after Thomas et al. (2013).
- `/meshes/Amalthea.obj`, `/meshes/Thebe.obj`, `/meshes/Larissa.obj`, `/meshes/Proteus.obj` — derived from the Voyager shape models of P. Stooke (*Stooke Small Bodies Shape Models V1.0*, NASA Planetary Data System, 2025, doi:10.26033/yt84-5y91).

### Surface-normal (bump) maps

For shaded relief on the shared spheroid mesh:

- `/cubemaps/Moon.normal.1024.png` — derived from LRO LOLA topography (NASA Scientific Visualization Studio, CGI Moon Kit).
- `/cubemaps/Mercury.normal.512.png` — derived from MESSENGER global topography (NASA/JHUAPL/Carnegie Institution of Washington; USGS Astrogeology DEM).
- `/cubemaps/Mars.normal.2048.png` — derived from MGS MOLA global topography (NASA/JPL/GSFC MOLA Science Team; USGS Astrogeology DEM).
- `/cubemaps/Enceladus.normal.512.png` — derived from the Cassini Global DEM 200m of Schenk & McKinnon (2024), distributed by USGS Astrogeology (NASA/JPL-Caltech/Space Science Institute).
- `/cubemaps/Earth.normal.1024.png` — derived from the NOAA ETOPO 2022 global relief model (60 arc-second ice surface; NOAA National Centers for Environmental Information), with ocean bathymetry flattened to sea level.

### Surface roughness map

For the specular Sun-glint on open water (smooth water; matte land, ice and snow):

- `/cubemaps/Earth.roughness.1024.png` — a land/sea mask derived from the `Earth.normal` relief map (NOAA ETOPO 2022, ocean flattened to sea level) and the `Earth.albedo` ocean color (NASA Blue Marble Next Generation): open water reads smooth (specular), land and ice matte.

---

## Data binaries and textures

These files are essentially data distributions; we make no claim on their content.

- `/asteroid_binaries/*` — asteroid proper orbital elements from the [Asteroids Dynamic Site (AstDyS)](https://newton.spacedys.com/astdys), packed by orbital group and magnitude limit.
- `/starmaps/hipparcos_stars.*.ivbinary` — star positions, magnitudes and B-V colors from the [ESA Hipparcos Catalogue](https://www.cosmos.esa.int/web/hipparcos) (ESA, 1997; ESA SP-1200), packed by magnitude limit.
- `/rings/*` — Saturn ring light-scattering data created by [Björn Jónsson](https://bjj.mmedia.is/data/s_rings/index.html), converted to shader-sampler textures.

---

## Derived cube-face reprojections

The `/cubemaps/` directory holds every world map the simulator uses, stored as a six-face cube-face strip rather than an equirectangular image mainly to prevent polar artifacts. Every albedo strip was reprojected by I, Voyager from an equirectangular source image and resampled to the stored face size. (The object-space normal strips of the custom-mesh bodies are not reprojections at all: each is computed from that body's own mesh geometry, and Phoebe's is ray-cast against the mesh directly.)

A reprojection is mechanical — a change of coordinates plus resampling — so **each reprojected cubemap carries the copyright and license of the source image it was reprojected from**:

- I, Voyager's Apache 2.0 license, for the surface-relief maps and the roughness map listed above;
- Public Domain, for maps built from public-domain NASA data;
- the source map's license, for maps from third-party sources (see [3RD_PARTY.md](3RD_PARTY.md) — e.g. the Björn Jónsson and James Hastings-Trew maps).

---

## Derived 2D body icons

The `/bodies_2d/` directory contains one small flat-image icon per body (`<Body>.256.png`), plus the Sun's `Sun_slice.128x1024.png`, used in the GUI. Each is rendered by I, Voyager from that body's 3D model, surface map or surface shader; as a derivative work, each carries the same copyright and license as the source body asset it was rendered from:

- Public Domain, for bodies built from public-domain NASA data;
- the source map's license, for bodies textured from third-party maps (see [3RD_PARTY.md](3RD_PARTY.md) — e.g. the Björn Jónsson maps);
- I, Voyager's Apache 2.0 license, for bodies built from the I, Voyager original models and maps listed above. The Sun's icons derive from its procedural surface shader.
