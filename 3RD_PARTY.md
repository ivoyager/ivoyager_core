# Third-Party Copyright and License Information

This document provides copyright and license information for third-party software and files used in "I, Voyager" software distributed from https://www.ivoyager.dev and https://github.com/ivoyager.

The master version of this file is maintained [here](https://github.com/ivoyager/asset_downloads/blob/master/3RD_PARTY.md).

**Contact:** Charlie Whitfield (mail@ivoyager.dev)

---

## Software

### Godot Engine

I, Voyager software distributions run on the [Godot Engine](https://godotengine.org/) and were developed using the Godot Engine editor. Licensing information for files used in Godot Engine can be found [here](https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt).

- **Copyright:** 2014-present, Godot Engine [contributors](https://github.com/godotengine/godot/blob/master/AUTHORS.md); 2007-2014, Juan Linietsky, Ariel Manzur  
- **License:** [MIT](#mit)


## Files

These files are located in subdirectories of `/addons/ivoyager_assets/` in project development builds and distributed from [this repository](https://github.com/ivoyager/asset_downloads), except where noted otherwise.

A file is listed here when its **content** came from somewhere other than I, Voyager, whatever processing we then applied to it. **Public Domain is a license, not the absence of one** — an unmodified public-domain image is not ours to claim, and one we reworked substantially stays here as well: we make no claim on these files even after our own work on them. Files whose content originates with I, Voyager — custom meshes, surface-relief maps, reconstructed surface maps — are documented separately in [IVOYAGER_WORKS.md](IVOYAGER_WORKS.md), along with I, Voyager-generated derivatives such as the `bodies_2d/` icons; each of those inherits the copyright and license of the source it was made from, including the third-party-licensed sources below.

**Modifications by I, Voyager.** Each section below says what we downloaded and what we then did to it to make the file we distribute. One step is common to all of them and is not repeated: we reprojected every downloaded equirectangular image into a six-face cube-face strip in `/cubemaps/` and resampled it to the stored face size. For the oblate planets that step also resamples latitude, so a map drawn on the planet's flattened figure lands correctly on the sphere the renderer uses. A second common step (2026-08): most surface maps are rescaled in linear light so that each map's sphere-averaged reflectance equals the body's V-band geometric albedo, the convention I, Voyager's physically calibrated lighting meters against. One map, **Earth**, remains well below that level and is nearer its downloaded one: its source is a land product whose ocean is a painted placeholder, and what should replace that is still an open question. Seven maps — **Ariel, Ganymede, Io, Oberon, Pluto, Titania and Triton** — could not be rescaled to it at all, being drawn with more brightness contrast than those bodies have reflectance range, so that a rescale alone would have driven ordinary terrain past white; for those we compressed luminance by a power law, chosen in each case as the least compression that reaches the level, leaving the color of every pixel untouched — except **Pluto**, where a published measurement of the body's own reflectance range sets it instead, and the map is stored with the range tag that lets it keep the result. That is a real change to the downloaded image and not a mechanical one, and the sections below add what is specific to each. A third common step, where a file name carries trailing letter-and-digit groups such as `.l01682.h08149`, is storage only: the image is stored scaled into the range of reflectance it actually covers, and those groups name the range so the renderer restores the original values exactly. Reprojection, level rescaling and range packing are mechanical transformations and do not alter the copyright or license of the underlying image.


### Jupiter map by Björn Jónsson (from Planetary Society)

We downloaded Jónsson's merged Cassini and Juno map of Jupiter from https://www.planetary.org/space-images/merged-cassini-and-juno. We changed nothing but the projection: the cubemap carries his color and his detail as downloaded.

- **Files:**
  - `/cubemaps/Jupiter.albedo.2048.png`
- **Copyright:** Björn Jónsson
- **License:** [CC-BY-3.0](#cc-by-30), which requires attribution. Please credit **NASA/JPL-Caltech/SSI/SwRI/MSSS/ASI/INAF/JIRAM/Björn Jónsson**.


### World maps by Björn Jónsson (from bjj.mmedia.is)

We downloaded Jónsson's global maps of Callisto, Ganymede, Io, Neptune and Saturn from https://bjj.mmedia.is/data/planetary_maps.html, and his [Io DEM](https://bjj.mmedia.is/data/io/io_dem.html) from the same site. Each is an equirectangular image he assembled and color-corrected from spacecraft frames.

For Callisto and Saturn we changed nothing but the projection and the overall level: those two cubemaps carry his color and his detail as downloaded.

Ganymede and Io are two of the five maps whose luminance we compressed to reach the physical level, as described above. Io needs one thing more: even after that compression its brightest saturated terrain exceeds 100% reflectance in red, at an albedo of 0.63 with the color his map carries. We store those values rather than desaturating them to fit, which is what the trailing groups in its file name record.

For Neptune we did not use the whole map. We cut only its light clouds and dark spots into `Neptune.clouds.albedo`, a translucent overlay, and generate the banding pattern beneath it in shader code — taking his map and Voyager 2 images as references and [Irwin et al. (2024)](https://academic.oup.com/mnras/article/527/4/11521/7511973) for true color.

Our Io normal map we built from the Io DEM, which Jónsson describes as largely fictional (a grayscale version of his Io map processed into height, with the known mountains painted in from a catalog). We scaled it as he recommends — black at -5 km, white at +10 km — and converted it to surface normals.

- **Files:**
  - `/cubemaps/Callisto.albedo.512.png`
  - `/cubemaps/Ganymede.albedo.512.png`
  - `/cubemaps/Io.albedo.1024.lr00679.lg00562.h13169.hg10775.hb10724.png`
  - `/cubemaps/Io.normal.512.png`
  - `/cubemaps/Neptune.clouds.albedo.512.l03864.lr02738.h09663.hg11302.hb09756.png`
  - `/cubemaps/Saturn.albedo.1024.l03864.lg03094.lb01682.h08149.hb05395.png`
- **Copyright:** Björn Jónsson
- **License:** From "Use of the planetary maps" on his [acknowledgements page](https://bjj.mmedia.is/acknow.html):
```
The planetary maps on these pages are publicly available. You do not
need a special permission to use them but if you do then please mention
their origin in your work, e.g. "created by Björn Jónsson" or something
equivalent. Also I would like to see renderings/animations created using
them if possible, I'm interested in space art.
```


### Uranian satellite mosaics by Paul Schenk (LPI)

We downloaded Paul Schenk's controlled Voyager 2 global mosaics of Miranda, Ariel and Titania from the Lunar and Planetary Institute at https://repository.hou.usra.edu/handle/20.500.11753/1687. They are NASA-funded science, published alongside Schenk, P. and Moore, J. (2020), "Topography and geology of Uranian mid-sized icy satellites in comparison with Saturnian and Plutonian satellites", *Philosophical Transactions of the Royal Society A* 378, 20200102, with no license asserted; the accompanying readme asks that users contact the author for guidance on appropriate use of the data. Miranda's digital elevation model comes from the same release; the mesh and normal map I, Voyager built from it are documented in [IVOYAGER_WORKS.md](IVOYAGER_WORKS.md), which carries the same citation.

To each downloaded mosaic we then did the following: interpolated away the Voyager camera's réseau marks, trimmed the ragged frame-coverage fringe and the terminator fade at its data edge, filled the hemisphere Voyager never imaged with a flat tone taken from that body's own average, reset the three moons' brightness relative to one another from published geometric albedos (Karkoschka 2001), and applied each moon's true disk-average color.

- **Files:**
  - `/cubemaps/Ariel.albedo.512.png`
  - `/cubemaps/Miranda.albedo.512.png`
  - `/cubemaps/Titania.albedo.512.png`
- **Copyright:** Paul Schenk, Lunar and Planetary Institute; underlying imagery NASA/JPL
- **License:** None asserted. Please cite Schenk & Moore (2020).


### Color maps of Saturn's icy moons by Paul Schenk (Cassini ISS)

We downloaded the first global color mosaics of Dione, Enceladus, Iapetus, Rhea and Tethys, assembled from Cassini's first ten years at Saturn and released as PIA18434, PIA18435, PIA18436, PIA18438 and PIA18439. NASA's captions record that "image selection, radiometric calibration, geographic registration and photometric correction, as well as mosaic selection and assembly were performed by Paul Schenk at the Lunar and Planetary Institute."

The color in the downloaded mosaics is enhanced, or broader, than human vision, extending into the ultraviolet and infrared, and our five maps keep it unchanged: we did not attempt to convert them to true color. For Rhea we additionally interpolated across the Cassini camera's réseau marks and trimmed the mosaic at its small data gaps. Iapetus rides a custom mesh, so its map is sampled by surface direction rather than wrapped on a sphere; the imagery itself is unaltered.

The Enceladus surface-relief map is an I, Voyager work built from the Cassini Global DEM 200m of Schenk & McKinnon (2024), distributed by USGS Astrogeology; it is documented in [IVOYAGER_WORKS.md](IVOYAGER_WORKS.md) with the other surface-normal maps.

- **Files:**
  - `/cubemaps/Dione.albedo.1024.png`
  - `/cubemaps/Enceladus.albedo.1024.png`
  - `/cubemaps/Iapetus.albedo.512.png`
  - `/cubemaps/Rhea.albedo.1024.png`
  - `/cubemaps/Tethys.albedo.1024.png`
- **Copyright:** Public Domain
- **License:** Public Domain. Please credit NASA/JPL-Caltech/Space Science Institute/Lunar and Planetary Institute.


### USGS Astrogeology mosaics

We downloaded the Viking Colorized Global Mosaic 232m (MDIM 2.1; originator NASA Ames, publisher USGS Astrogeology) and derived our Mars map from it.

The downloaded mosaic's color is not a measurement — USGS give its purpose as making "an artistically colorized version" of the controlled monochrome mosaic — and it renders the dark regions blue-dominant, which Mars is not. We kept its luminance, which is 4,600 controlled Viking Orbiter frames at 232 m/pixel, and replaced its chromaticity with Mars' measured true color: a spectrum fitted to the twelve published geometric albedos of Mallama, Krobusek and Pavlov (2017) — seven Johnson-Cousins bands and five Sloan — then integrated against the CIE 1931 observer, giving chromaticity xy (0.3925, 0.3867) and reproducing Mars' published B−V of 1.37. We scaled the overall level to the same work's V geometric albedo of 0.170. In our map the residual polar caps are held neutral, as water and CO2 frost are across the visible, while the seasonal frost around them — which the mosaic's source frames caught but which is gone by each pole's summer — carries a partial ice tone instead of the full cap.

We downloaded the Voyager 2 Global Color Mosaic 600m (originators NASA, JPL and Dr. Paul Schenk; publisher USGS Astrogeology; released as PIA18668) and derived our Triton map from it.

The downloaded mosaic's three channels are Voyager's orange, violet and ultraviolet filters shown as red, green and blue, which is not what the eye would see — violet light is displayed as green, and the blue channel is light outside the visible range altogether. We discarded the ultraviolet channel, restored the inter-filter calibration from Voyager's own disk-integrated photometry (Nelson et al. 1990, geometric albedo 0.68 at 0.41 µm rising to 0.81 at 0.56 µm), and rebuilt per-pixel true color by integrating the resulting spectral slope against the CIE 1931 observer, carried on the orange band's luminance. We imposed only the disk average, so in our map the south polar cap keeps its real reddening against the fresher equatorial deposits. We filled the region Voyager never imaged with a flat tone taken from the body's own average.

- **Files:**
  - `/cubemaps/Mars.albedo.2048.png`
  - `/cubemaps/Triton.albedo.1024.l03094.lg03005.lb02462.hg09216.hb08880.png`
- **Copyright:** Public Domain
- **License:** Public Domain. Please cite the USGS Astrogeology Science Center.


### NASA images and models

Most NASA images and models are in the public domain. Use is governed by [NASA Images and Media Usage Guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/).

Where a downloaded map leaves regions no spacecraft has imaged, we filled them with a flat neutral tone taken from that body's own average: Ceres' black south pole (in seasonal shadow throughout the Dawn mission), Vesta's north polar cap (in polar winter throughout that mission), Phoebe's unimaged regions, and the hemispheres of Umbriel and Oberon that Voyager 2 never saw.

Our Milky Way background is derived from Deep Star Maps 2020, downloaded from https://svs.gsfc.nasa.gov/4851/ — the "Milky Way background in galactic coordinates ... that omits the bright (Hipparcos and Tycho) stars". We downloaded and processed the available 64K EXR file into an 8-bit sRGB 4K PNG that is intentionally smoother than the available 4K EXR. Our in-app discrete stars are rendered separately by shader code (see ESA, Hipparcos Catalogue in [CREDITS.md](CREDITS.md)).

Our Moon color map is derived from the LROC WAC color mosaic in the NASA Scientific Visualization Studio CGI Moon Kit (https://svs.gsfc.nasa.gov/4720). We toned it toward true color, restoring the terrae/mare hue differentiation from the public-domain LROC WAC Hapke-normalized 415/566/643 nm mosaic bands, and rebuilt the Kit's uncolored polar caps on the cube from the LROC WAC polar-stereographic mosaics (WAC_GLOBAL_P900N/S), filling the permanently-shadowed remainder from the same kit's co-registered LOLA topography.

Our Ceres and Vesta albedo maps are true-color composites we built from the public-domain Dawn Framing Camera HAMO mosaics (Roatsch et al., NASA PDS): each body's clear-filter mosaic supplies luminance and detail, and its F7/F2/F8 color filters (653/555/438 nm) supply per-pixel hue through the CIE color-matching functions (method after Schröder et al. 2017). Within Ceres' unimaged south-polar F8 gap we synthesized blue from the global blue/green ratio. Dawn observed Vesta in southern summer, so its clear-filter mosaic carries that illumination as well as albedo; we divided out the latitudinal trend and compressed the residual shadow and glare.

Our Phobos and Deimos albedo maps are derived from Philip Stooke's controlled global mosaics (Stooke Small Bodies Maps, NASA PDS): for Phobos the DLR-controlled Viking Orbiter mosaic, redistributed at 5 m/pixel by USGS Astrogeology; for Deimos the Viking Orbiter / Mars Reconnaissance Orbiter mosaic. Stooke notes that where images of opposing illumination meet, artistic blending was applied to appearance though not to map geometry. We divided out the residual latitudinal illumination each downloaded mosaic carries, referenced to the illumination-free relative albedo of the Ernst et al. (2023) stereophotoclinometry solutions, and tinted both moons to their true disk-average color, linear RGB 1.021 : 1.005 : 0.887 (a warm grey-brown), calibrated by integrating Phobos' published per-filter HRSC geometric albedos (440/530/750 nm; Fernando et al. 2024) against the CIE 1931 observer under an equal-energy illuminant.

Our Umbriel and Oberon maps are derived from the Uranus moon textures published in NASA 3D Resources, credited to USGS/Tammy Becker and JPL/Caltech. Both downloads are neutral greyscale — the faint tan seen in some copies is JPEG chroma artifacting on neutral data, not real color — and both leave the hemisphere Voyager 2 never imaged as plain black. We gave the two the same treatment as the three Schenk mosaics above: we filled that black with a flat body-average tone, feathered, set each moon's level from its published geometric albedo (Karkoschka 2001 — Umbriel 0.259, Oberon 0.314), and applied its measured disk-average tint.

Our Charon map is derived from the New Horizons global color map embedded in the NASA 3D Resources Charon model — the encounter hemisphere plus the reddish Mordor Macula north polar cap. Only one hemisphere was well imaged by the 2015 flyby, and the remainder carries a neutral grey fill. One unimaged pocket near 35°S was left black in the download, with cartographic grid lines drawn across it; we extended the flat fill over both. The imaged terrain is otherwise unchanged, reprojected onto Charon's custom mesh.

Our Pluto map is the Pluto Global Color Map (New Horizons Ralph/MVIC, three filters), downloaded from https://science.nasa.gov/resource/pluto-global-color-map/. That product is an enhanced-color rendering rather than a natural-color one — its own publication, Olkin et al. (2017), "The Global Color of Pluto from New Horizons", *The Astronomical Journal* 154, 258, describes it as "enhanced color (not natural color as perceived by the human eye)", and its red channel carries a near-infrared band the eye cannot see. We kept its brightness structure, which is the real one, and compressed its color variation toward what the same camera recorded in natural color on the same flyby, measured from NASA's own refined-calibration view of Pluto (credit NASA/Johns Hopkins University Applied Physics Laboratory/Southwest Research Institute/Alex Parker), region by region: both how red each terrain is and how its green tracks that redness are taken from measurements of that view rather than from any assumed spectrum, which is what keeps Pluto's dark equatorial terrain the deep red-brown it is rather than the olive a simpler model gives it. Where the enhanced product carries no usable color information at all — its bands cannot rank the ordinary terrain's colors — we carried the natural-color view's own large-scale color differences across directly, which is what preserves the yellow streaks running down from the northern polar region and the faint tint that sets Sputnik Planitia apart from the other bright terrain. We also reset its brightness range to Pluto's published normal reflectances of 0.08 to 1.0 (Buratti et al. 2017), the widest of any body we ship, which is what lets its dark equatorial terrain read as dark rather than merely brown. Pluto keeps the reddish tholin coloring it is known for, at the strength the calibrated data supports. The region New Horizons never imaged, about a fifth of the sphere, is filled with a flat tone at the body's own average.

Our Phoebe map is derived from the stereophotoclinometry relative-albedo map of John R. Weirich (2023), solved over Robert Gaskell's Cassini ISS shape model and archived at the PDS Small Bodies Node. About 27% of the downloaded map is unimaged black; we filled those regions with the imaged mean grey, feathered, while leaving the small crater-floor shadows alone so real craters keep their relief.

Our three Earth maps come from the NASA Earth Observatory: the surface map from Blue Marble Next Generation, July 2004 (imagery by Reto Stöckli); the cloud map from The Blue Marble 2002 combined cloud product (image by Reto Stöckli); and the night-lights emission map from the Black Marble 2016 grayscale (lights-only) release. To the night lights we applied a uniform warm tint (a 3000 K blackbody color) in linear light and downsampled in linear light so city brightness is preserved; the grayscale product's dark regions are genuinely zero, and we subtracted no floor, so faint real sources — villages, gas flares, fishing fleets — remain. Black Marble is assembled from ten-degree tiles and carries a small mark on each tile corner, which our night side renders as a regular lattice of lights over open ocean; we cleared those marks, but only where nothing else is lit anywhere near them, so no real light source is touched. Earth's relief and roughness maps are I, Voyager works built from NOAA ETOPO 2022 and are documented in [IVOYAGER_WORKS.md](IVOYAGER_WORKS.md).

3D models were downloaded from https://science.nasa.gov/3d-resources/. Model subdirectories each contain the downloaded file (usually *.glb extension) and files extracted from the model by Godot's importer.

- **Files:**
  - `/cubemaps/Ceres.albedo.512.png`
  - `/cubemaps/Charon.albedo.512.png`
  - `/cubemaps/Deimos.albedo.512.png`
  - `/cubemaps/Earth.albedo.2048.png`
  - `/cubemaps/Earth.clouds.albedo.512.png`
  - `/cubemaps/Earth.emission.1024.png`
  - `/cubemaps/Moon.albedo.1024.png`
  - `/cubemaps/Oberon.albedo.512.png`
  - `/cubemaps/Phobos.albedo.512.png`
  - `/cubemaps/Phoebe.albedo.512.png`
  - `/cubemaps/Pluto.albedo.1024.png`
  - `/cubemaps/Umbriel.albedo.512.png`
  - `/cubemaps/Vesta.albedo.512.png`
  - `/starmaps/milkyway_background.4096.png`
  - `pale_blue_dot.png` is distributed in the [Project Template repository](https://github.com/ivoyager/project_template).
  - `pale_blue_dot_453x614.jpg` is distributed in web-based deployments of the [Planetarium app](https://www.ivoyager.dev/planetarium/).
- **Model subdirectories:**
  - `/models/arrokoth/*`
  - `/models/bennu/*`
  - `/models/eros/*`
  - `/models/hubble/*`
  - `/models/hyperion/*`
  - `/models/iss/*`
  - `/models/itokawa/*`
  - `/models/juno/*`
  - `/models/jwst/*`
  - `/models/mimas/*`
  - `/models/new_horizons/*`
  - `/models/pioneer_10/*`
  - `/models/voyager/*`
- **Copyright:** Public Domain
- **License:** Public Domain; see [NASA Images and Media Usage Guidelines](https://www.nasa.gov/nasa-brand-center/images-and-media/).


### Roboto / Noto Sans Symbols fonts

The font file used is a merge of Roboto and Noto Sans Symbols, both [Google Fonts](https://fonts.google.com/).

- **File:** `/fonts/Roboto-NotoSansSymbols-merged.ttf`
- **Copyright:** Google LLC
- **License:** [SIL OPEN FONT LICENSE Version 1.1](#sil-open-font-license-version-11)


---

## Licenses in Detail

### MIT

```
 Permission is hereby granted, free of charge, to any person obtaining
 a copy of this software and associated documentation files (the
 "Software"), to deal in the Software without restriction, including
 without limitation the rights to use, copy, modify, merge, publish,
 distribute, sublicense, and/or sell copies of the Software, and to
 permit persons to whom the Software is furnished to do so, subject to
 the following conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### CC-BY-3.0

[Creative Commons Attribution 3.0 Unported](http://creativecommons.org/licenses/by/3.0/)

```
 Creative Commons Attribution 3.0 Unported
 
 CREATIVE COMMONS CORPORATION IS NOT A LAW FIRM AND DOES NOT PROVIDE
 LEGAL SERVICES. DISTRIBUTION OF THIS LICENSE DOES NOT CREATE AN
 ATTORNEY-CLIENT RELATIONSHIP. CREATIVE COMMONS PROVIDES THIS INFORMATION
 ON AN "AS-IS" BASIS. CREATIVE COMMONS MAKES NO WARRANTIES REGARDING THE
 INFORMATION PROVIDED, AND DISCLAIMS LIABILITY FOR DAMAGES RESULTING FROM
 ITS USE.
 
 License
 
 THE WORK (AS DEFINED BELOW) IS PROVIDED UNDER THE TERMS OF THIS CREATIVE
 COMMONS PUBLIC LICENSE ("CCPL" OR "LICENSE"). THE WORK IS PROTECTED BY
 COPYRIGHT AND/OR OTHER APPLICABLE LAW. ANY USE OF THE WORK OTHER THAN AS
 AUTHORIZED UNDER THIS LICENSE OR COPYRIGHT LAW IS PROHIBITED.
 
 BY EXERCISING ANY RIGHTS TO THE WORK PROVIDED HERE, YOU ACCEPT AND AGREE
 TO BE BOUND BY THE TERMS OF THIS LICENSE. TO THE EXTENT THIS LICENSE MAY
 BE CONSIDERED TO BE A CONTRACT, THE LICENSOR GRANTS YOU THE RIGHTS
 CONTAINED HERE IN CONSIDERATION OF YOUR ACCEPTANCE OF SUCH TERMS AND
 CONDITIONS.
 
 1. Definitions
 
 a. "Adaptation" means a work based upon the Work, or upon the Work and
 other pre-existing works, such as a translation, adaptation, derivative
 work, arrangement of music or other alterations of a literary or
 artistic work, or phonogram or performance and includes cinematographic
 adaptations or any other form in which the Work may be recast,
 transformed, or adapted including in any form recognizably derived from
 the original, except that a work that constitutes a Collection will not
 be considered an Adaptation for the purpose of this License. For the
 avoidance of doubt, where the Work is a musical work, performance or
 phonogram, the synchronization of the Work in timed-relation with a
 moving image ("synching") will be considered an Adaptation for the
 purpose of this License.
 
 b. "Collection" means a collection of literary or artistic works, such
 as encyclopedias and anthologies, or performances, phonograms or
 broadcasts, or other works or subject matter other than works listed in
 Section 1(f) below, which, by reason of the selection and arrangement of
 their contents, constitute intellectual creations, in which the Work is
 included in its entirety in unmodified form along with one or more other
 contributions, each constituting separate and independent works in
 themselves, which together are assembled into a collective whole. A work
 that constitutes a Collection will not be considered an Adaptation (as
 defined above) for the purposes of this License.
 
 c.  "Distribute" means to make available to the public the original and
 copies of the Work or Adaptation, as appropriate, through sale or other
 transfer of ownership.
 
 d. "Licensor" means the individual, individuals, entity or entities that
 offer(s) the Work under the terms of this License.
 
 e. "Original Author" means, in the case of a literary or artistic work,
 the individual, individuals, entity or entities who created the Work or
 if no individual or entity can be identified, the publisher; and in
 addition (i) in the case of a performance the actors, singers,
 musicians, dancers, and other persons who act, sing, deliver, declaim,
 play in, interpret or otherwise perform literary or artistic works or
 expressions of folklore; (ii) in the case of a phonogram the producer
 being the person or legal entity who first fixes the sounds of a
 performance or other sounds; and, (iii) in the case of broadcasts, the
 organization that transmits the broadcast.
 
 f. "Work" means the literary and/or artistic work offered under the
 terms of this License including without limitation any production in the
 literary, scientific and artistic domain, whatever may be the mode or
 form of its expression including digital form, such as a book, pamphlet
 and other writing; a lecture, address, sermon or other work of the same
 nature; a dramatic or dramatico-musical work; a choreographic work or
 entertainment in dumb show; a musical composition with or without words;
 a cinematographic work to which are assimilated works expressed by a
 process analogous to cinematography; a work of drawing, painting,
 architecture, sculpture, engraving or lithography; a photographic work
 to which are assimilated works expressed by a process analogous to
 photography; a work of applied art; an illustration, map, plan, sketch
 or three-dimensional work relative to geography, topography,
 architecture or science; a performance; a broadcast; a phonogram; a
 compilation of data to the extent it is protected as a copyrightable
 work; or a work performed by a variety or circus performer to the extent
 it is not otherwise considered a literary or artistic work.
 
 g. "You" means an individual or entity exercising rights under this
 License who has not previously violated the terms of this License with
 respect to the Work, or who has received express permission from the
 Licensor to exercise rights under this License despite a previous
 violation.
 
 h. "Publicly Perform" means to perform public recitations of the Work
 and to communicate to the public those public recitations, by any means
 or process, including by wire or wireless means or public digital
 performances; to make available to the public Works in such a way that
 members of the public may access these Works from a place and at a place
 individually chosen by them; to perform the Work to the public by any
 means or process and the communication to the public of the performances
 of the Work, including by public digital performance; to broadcast and
 rebroadcast the Work by any means including signs, sounds or images.
 
 i. "Reproduce" means to make copies of the Work by any means including
 without limitation by sound or visual recordings and the right of
 fixation and reproducing fixations of the Work, including storage of a
 protected performance or phonogram in digital form or other electronic
 medium.
 
 2. Fair Dealing Rights. Nothing in this License is intended to reduce,
 limit, or restrict any uses free from copyright or rights arising from
 limitations or exceptions that are provided for in connection with the
 copyright protection under copyright law or other applicable laws.
 
 3. License Grant. Subject to the terms and conditions of this License,
 Licensor hereby grants You a worldwide, royalty-free, non-exclusive,
 perpetual (for the duration of the applicable copyright) license to
 exercise the rights in the Work as stated below:
 
 a. to Reproduce the Work, to incorporate the Work into one or more
 Collections, and to Reproduce the Work as incorporated in the
 Collections;
 
 b. to create and Reproduce Adaptations provided that any such
 Adaptation, including any translation in any medium, takes reasonable
 steps to clearly label, demarcate or otherwise identify that changes
 were made to the original Work. For example, a translation could be
 marked "The original work was translated from English to Spanish," or a
 modification could indicate "The original work has been modified.";
 
 c. to Distribute and Publicly Perform the Work including as incorporated
 in Collections; and,
 
 d. to Distribute and Publicly Perform Adaptations.
 
 e. For the avoidance of doubt:
 
 i. Non-waivable Compulsory License Schemes. In those jurisdictions in
 which the right to collect royalties through any statutory or compulsory
 licensing scheme cannot be waived, the Licensor reserves the exclusive
 right to collect such royalties for any exercise by You of the rights
 granted under this License;
 
 ii. Waivable Compulsory License Schemes. In those jurisdictions in which
 the right to collect royalties through any statutory or compulsory
 licensing scheme can be waived, the Licensor waives the exclusive right
 to collect such royalties for any exercise by You of the rights granted
 under this License; and,
 
 iii. Voluntary License Schemes. The Licensor waives the right to collect
 royalties, whether individually or, in the event that the Licensor is a
 member of a collecting society that administers voluntary licensing
 schemes, via that society, from any exercise by You of the rights
 granted under this License.
 
 The above rights may be exercised in all media and formats whether now
 known or hereafter devised. The above rights include the right to make
 such modifications as are technically necessary to exercise the rights
 in other media and formats. Subject to Section 8(f), all rights not
 expressly granted by Licensor are hereby reserved.
 
 4. Restrictions. The license granted in Section 3 above is expressly
 made subject to and limited by the following restrictions:
 
 a. You may Distribute or Publicly Perform the Work only under the terms
 of this License. You must include a copy of, or the Uniform Resource
 Identifier (URI) for, this License with every copy of the Work You
 Distribute or Publicly Perform. You may not offer or impose any terms on
 the Work that restrict the terms of this License or the ability of the
 recipient of the Work to exercise the rights granted to that recipient
 under the terms of the License. You may not sublicense the Work. You
 must keep intact all notices that refer to this License and to the
 disclaimer of warranties with every copy of the Work You Distribute or
 Publicly Perform. When You Distribute or Publicly Perform the Work, You
 may not impose any effective technological measures on the Work that
 restrict the ability of a recipient of the Work from You to exercise the
 rights granted to that recipient under the terms of the License. This
 Section 4(a) applies to the Work as incorporated in a Collection, but
 this does not require the Collection apart from the Work itself to be
 made subject to the terms of this License. If You create a Collection,
 upon notice from any Licensor You must, to the extent practicable,
 remove from the Collection any credit as required by Section 4(b), as
 requested. If You create an Adaptation, upon notice from any Licensor
 You must, to the extent practicable, remove from the Adaptation any
 credit as required by Section 4(b), as requested.
 
 b. If You Distribute, or Publicly Perform the Work or any Adaptations or
 Collections, You must, unless a request has been made pursuant to
 Section 4(a), keep intact all copyright notices for the Work and
 provide, reasonable to the medium or means You are utilizing: (i) the
 name of the Original Author (or pseudonym, if applicable) if supplied,
 and/or if the Original Author and/or Licensor designate another party or
 parties (e.g., a sponsor institute, publishing entity, journal) for
 attribution ("Attribution Parties") in Licensor's copyright notice,
 terms of service or by other reasonable means, the name of such party or
 parties; (ii) the title of the Work if supplied; (iii) to the extent
 reasonably practicable, the URI, if any, that Licensor specifies to be
 associated with the Work, unless such URI does not refer to the
 copyright notice or licensing information for the Work; and (iv) ,
 consistent with Section 3(b), in the case of an Adaptation, a credit
 identifying the use of the Work in the Adaptation (e.g., "French
 translation of the Work by Original Author," or "Screenplay based on
 original Work by Original Author"). The credit required by this Section
 4 (b) may be implemented in any reasonable manner; provided, however,
 that in the case of a Adaptation or Collection, at a minimum such credit
 will appear, if a credit for all contributing authors of the Adaptation
 or Collection appears, then as part of these credits and in a manner at
 least as prominent as the credits for the other contributing authors.
 For the avoidance of doubt, You may only use the credit required by this
 Section for the purpose of attribution in the manner set out above and,
 by exercising Your rights under this License, You may not implicitly or
 explicitly assert or imply any connection with, sponsorship or
 endorsement by the Original Author, Licensor and/or Attribution Parties,
 as appropriate, of You or Your use of the Work, without the separate,
 express prior written permission of the Original Author, Licensor and/or
 Attribution Parties.
 
 c. Except as otherwise agreed in writing by the Licensor or as may be
 otherwise permitted by applicable law, if You Reproduce, Distribute or
 Publicly Perform the Work either by itself or as part of any Adaptations
 or Collections, You must not distort, mutilate, modify or take other
 derogatory action in relation to the Work which would be prejudicial to
 the Original Author's honor or reputation. Licensor agrees that in those
 jurisdictions (e.g. Japan), in which any exercise of the right granted
 in Section 3(b) of this License (the right to make Adaptations) would be
 deemed to be a distortion, mutilation, modification or other derogatory
 action prejudicial to the Original Author's honor and reputation, the
 Licensor will waive or not assert, as appropriate, this Section, to the
 fullest extent permitted by the applicable national law, to enable You
 to reasonably exercise Your right under Section 3(b) of this License
 (right to make Adaptations) but not otherwise.
 
 5. Representations, Warranties and Disclaimer
 
 UNLESS OTHERWISE MUTUALLY AGREED TO BY THE PARTIES IN WRITING, LICENSOR
 OFFERS THE WORK AS-IS AND MAKES NO REPRESENTATIONS OR WARRANTIES OF ANY
 KIND CONCERNING THE WORK, EXPRESS, IMPLIED, STATUTORY OR OTHERWISE,
 INCLUDING, WITHOUT LIMITATION, WARRANTIES OF TITLE, MERCHANTIBILITY,
 FITNESS FOR A PARTICULAR PURPOSE, NONINFRINGEMENT, OR THE ABSENCE OF
 LATENT OR OTHER DEFECTS, ACCURACY, OR THE PRESENCE OF ABSENCE OF ERRORS,
 WHETHER OR NOT DISCOVERABLE. SOME JURISDICTIONS DO NOT ALLOW THE
 EXCLUSION OF IMPLIED WARRANTIES, SO SUCH EXCLUSION MAY NOT APPLY TO YOU.
 
 6. Limitation on Liability. EXCEPT TO THE EXTENT REQUIRED BY APPLICABLE
 LAW, IN NO EVENT WILL LICENSOR BE LIABLE TO YOU ON ANY LEGAL THEORY FOR
 ANY SPECIAL, INCIDENTAL, CONSEQUENTIAL, PUNITIVE OR EXEMPLARY DAMAGES
 ARISING OUT OF THIS LICENSE OR THE USE OF THE WORK, EVEN IF LICENSOR HAS
 BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
 
 7. Termination
 
 a. This License and the rights granted hereunder will terminate
 automatically upon any breach by You of the terms of this License.
 Individuals or entities who have received Adaptations or Collections
 from You under this License, however, will not have their licenses
 terminated provided such individuals or entities remain in full
 compliance with those licenses. Sections 1, 2, 5, 6, 7, and 8 will
 survive any termination of this License.
 
 b. Subject to the above terms and conditions, the license granted here
 is perpetual (for the duration of the applicable copyright in the Work).
 Notwithstanding the above, Licensor reserves the right to release the
 Work under different license terms or to stop distributing the Work at
 any time; provided, however that any such election will not serve to
 withdraw this License (or any other license that has been, or is
 required to be, granted under the terms of this License), and this
 License will continue in full force and effect unless terminated as
 stated above.
 
 8. Miscellaneous
 
 a. Each time You Distribute or Publicly Perform the Work or a
 Collection, the Licensor offers to the recipient a license to the Work
 on the same terms and conditions as the license granted to You under
 this License.
 
 b. Each time You Distribute or Publicly Perform an Adaptation, Licensor
 offers to the recipient a license to the original Work on the same terms
 and conditions as the license granted to You under this License.
 
 c. If any provision of this License is invalid or unenforceable under
 applicable law, it shall not affect the validity or enforceability of
 the remainder of the terms of this License, and without further action
 by the parties to this agreement, such provision shall be reformed to
 the minimum extent necessary to make such provision valid and
 enforceable.
 
 d. No term or provision of this License shall be deemed waived and no
 breach consented to unless such waiver or consent shall be in writing
 and signed by the party to be charged with such waiver or consent. This
 License constitutes the entire agreement between the parties with
 respect to the Work licensed here. There are no understandings,
 agreements or representations with respect to the Work not specified
 here. Licensor shall not be bound by any additional provisions that may
 appear in any communication from You.
 
 e. This License may not be modified without the mutual written agreement
 of the Licensor and You.
 
 f. The rights granted under, and the subject matter referenced, in this
 License were drafted utilizing the terminology of the Berne Convention
 for the Protection of Literary and Artistic Works (as amended on
 September 28, 1979), the Rome Convention of 1961, the WIPO Copyright
 Treaty of 1996, the WIPO Performances and Phonograms Treaty of 1996 and
 the Universal Copyright Convention (as revised on July 24, 1971). These
 rights and subject matter take effect in the relevant jurisdiction in
 which the License terms are sought to be enforced according to the
 corresponding provisions of the implementation of those treaty
 provisions in the applicable national law. If the standard suite of
 rights granted under applicable copyright law includes additional rights
 not granted under this License, such additional rights are deemed to be
 included in the License; this License is not intended to restrict the
 license of any rights under applicable law.
 
 Creative Commons Notice
 
 Creative Commons is not a party to this License, and makes no warranty
 whatsoever in connection with the Work. Creative Commons will not be
 liable to You or any party on any legal theory for any damages
 whatsoever, including without limitation any general, special,
 incidental or consequential damages arising in connection to this
 license. Notwithstanding the foregoing two (2) sentences, if Creative
 Commons has expressly identified itself as the Licensor hereunder, it
 shall have all rights and obligations of Licensor.
 .
 Except for the limited purpose of indicating to the public that the Work
 is licensed under the CCPL, Creative Commons does not authorize the use
 by either party of the trademark "Creative Commons" or any related
 trademark or logo of Creative Commons without the prior written consent
 of Creative Commons. Any permitted use will be in compliance with
 Creative Commons' then-current trademark usage guidelines, as may be
 published on its website or otherwise made available upon request from
 time to time. For the avoidance of doubt, this trademark restriction
 does not form part of this License.
 
 Creative Commons may be contacted at http://creativecommons.org/.
```

### SIL OPEN FONT LICENSE Version 1.1

[SIL OPEN FONT LICENSE Version 1.1 - 26 February 2007](https://openfontlicense.org/open-font-license-official-text/)
```
PREAMBLE
The goals of the Open Font License (OFL) are to stimulate worldwide
development of collaborative font projects, to support the font creation
efforts of academic and linguistic communities, and to provide a free and
open framework in which fonts may be shared and improved in partnership
with others.

The OFL allows the licensed fonts to be used, studied, modified and
redistributed freely as long as they are not sold by themselves. The
fonts, including any derivative works, can be bundled, embedded,
redistributed and/or sold with any software provided that any reserved
names are not used by derivative works. The fonts and derivatives,
however, cannot be released under any other type of license. The
requirement for fonts to remain under this license does not apply
to any document created using the fonts or their derivatives.

DEFINITIONS
"Font Software" refers to the set of files released by the Copyright
Holder(s) under this license and clearly marked as such. This may
include source files, build scripts and documentation.

"Reserved Font Name" refers to any names specified as such after the
copyright statement(s).

"Original Version" refers to the collection of Font Software components as
distributed by the Copyright Holder(s).

"Modified Version" refers to any derivative made by adding to, deleting,
or substituting -- in part or in whole -- any of the components of the
Original Version, by changing formats or by porting the Font Software to a
new environment.

"Author" refers to any designer, engineer, programmer, technical
writer or other person who contributed to the Font Software.

PERMISSION & CONDITIONS
Permission is hereby granted, free of charge, to any person obtaining
a copy of the Font Software, to use, study, copy, merge, embed, modify,
redistribute, and sell modified and unmodified copies of the Font
Software, subject to the following conditions:

1) Neither the Font Software nor any of its individual components,
in Original or Modified Versions, may be sold by itself.

2) Original or Modified Versions of the Font Software may be bundled,
redistributed and/or sold with any software, provided that each copy
contains the above copyright notice and this license. These can be
included either as stand-alone text files, human-readable headers or
in the appropriate machine-readable metadata fields within text or
binary files as long as those fields can be easily viewed by the user.

3) No Modified Version of the Font Software may use the Reserved Font
Name(s) unless explicit written permission is granted by the corresponding
Copyright Holder. This restriction only applies to the primary font name as
presented to the users.

4) The name(s) of the Copyright Holder(s) or the Author(s) of the Font
Software shall not be used to promote, endorse or advertise any
Modified Version, except to acknowledge the contribution(s) of the
Copyright Holder(s) and the Author(s) or with their explicit written
permission.

5) The Font Software, modified or unmodified, in part or in whole,
must be distributed entirely under this license, and must not be
distributed under any other license. The requirement for fonts to
remain under this license does not apply to any document created
using the Font Software.

TERMINATION
This license becomes null and void if any of the above conditions are
not met.

DISCLAIMER
THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO ANY WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT
OF COPYRIGHT, PATENT, TRADEMARK, OR OTHER RIGHT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
INCLUDING ANY GENERAL, SPECIAL, INDIRECT, INCIDENTAL, OR CONSEQUENTIAL
DAMAGES, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF THE USE OR INABILITY TO USE THE FONT SOFTWARE OR FROM
OTHER DEALINGS IN THE FONT SOFTWARE.
```
