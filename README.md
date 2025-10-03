# I, Voyager - Core (plugin)

This Godot Editor plugin runs a solar system simulation.

[Homepage](https://www.ivoyager.dev)  
[Forum](https://github.com/orgs/ivoyager/discussions)  
[Issues](https://github.com/ivoyager/ivoyager_core/issues)  
[Changelog](https://github.com/ivoyager/ivoyager_core/blob/master/CHANGELOG.md)  

### Requirements

* ivoyager_tables (plugin) - See [repository](https://github.com/ivoyager/ivoyager_tables) for installation instructions.
* ivoyager_units (plugin) - See [repository](https://github.com/ivoyager/ivoyager_units) for installation instructions.
* ivoyager_assets (non-Git-tracked assets) The Core plugin will download this for you! Just press "Download" at the editor prompt. Alternatively, go [here](https://github.com/ivoyager/asset_downloads).

See [changelog](https://github.com/ivoyager/ivoyager_core/blob/master/CHANGELOG.md) for current version requirements.

### Installation

Find more detailed instructions at our [Developers Page](https://www.ivoyager.dev/developers/).

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

### What is I, Voyager?

I, Voyager is

1. an open-source software planetarium 
2. a development platform for creating games and educational apps in a realistic solar system.

It is designed to be improved, modified and extended by the community. I, Voyager runs on the open-source [Godot Engine](https://godotengine.org) and primarily uses Godot’s [GDScript](http://docs.godotengine.org/en/stable/getting_started/scripting/gdscript/gdscript_basics.html#doc-gdscript) (easy to understand if you know Python). It is built as a [set of plugins](https://github.com/ivoyager). You can either add plugins as needed to an existing Godot project, or start a new project using our [Template](https://github.com/ivoyager/project_template). Godot supports project development in GDScript, C# and C++.

If you are interested in our future development, see our official [Roadmap!](https://github.com/orgs/ivoyager/discussions/5).

### What does I, Voyager cost?

I, Voyager is free to use and distribute under the permissive [Apache License 2.0](https://github.com/ivoyager/ivoyager_core/blob/master/LICENSE.txt). Projects built with I, Voyager are owned by their creators. You can sell what you make. There are no royalties or fees.

### How do I contribute to development?

Help us grow the community by following us on [X](https://x.com/IVoygr) and [Facebook](https://www.facebook.com/IVoygr/). Exchange ideas and give and receive help on our [Forum](https://github.com/orgs/ivoyager/discussions). Report bugs or astronomical inaccuracies at our issue tracker [here](https://github.com/ivoyager/ivoyager_core/issues). To see where we are going and how you might help, visit our official [Roadmap](https://github.com/orgs/ivoyager/discussions/5). Or contribute code via pull requests at our GitHub [repositories](https://github.com/ivoyager).

### How can I support this effort financially?

Please visit our [GitHub Sponsors page!](https://github.com/sponsors/charliewhitfield) Become a Mercury Patron for $2 per month! Or, if you are a company, please consider sponsoring us as a Saturn or Jupiter Patron. Our goal is to become a non-profit entity. This would allow us to apply for grants and secure our existence as a collaborative open-source project into the future.

### Where did I, Voyager come from?

Creator and lead programmer Charlie Whitfield stumbled into the Godot Engine in November, 2017. By December there were TestCubes orbiting bigger TestCubes orbiting one really big TestCube*. The name "I, Voyager" is a play on Voyager 1, the spacecraft that captured an [image of Earth](https://www.planetary.org/explore/space-topics/earth/pale-blue-dot.html) from 6.4 billion kilometers away. I, Voyager became an open-source project on Carl Sagan's birthday, November 9, 2019.

(* Godot devs, bring back the [TestCube](https://docs.godotengine.org/en/2.1/classes/class_testcube.html)!)

### Authors, credits and legal

I, Voyager is possible due to public interest in space exploration and funding of government agencies like NASA and ESA. It's also possible due to open-source software developers, and especially [Godot Engine's creators and contributors](https://github.com/godotengine/godot/blob/master/AUTHORS.md). Copyright © 2017-2025 Charlie Whitfield. I, Voyager® is a registered trademark of Charlie Whitfield in the U.S. For up-to-date authors, credits, license, and 3rd-party information, follow these links:
* [AUTHORS](https://github.com/ivoyager/ivoyager_core/blob/master/AUTHORS.md) - Direct contributors to I, Voyager code and assets.
* [CREDITS](https://github.com/ivoyager/ivoyager_core/blob/master/CREDITS.md) - Individuals and organizations whose efforts made I, Voyager possible.  
* [LICENSE](https://github.com/ivoyager/ivoyager_core/blob/master/LICENSE.txt) - The I, Voyager license.
* [3RD_PARTY](https://github.com/ivoyager/ivoyager_core/blob/master/3RD_PARTY.md) - Copyright and license information for 3rd-party software and files distributed in I, Voyager.  

### Screen captures!  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/europa-jupiter-io-ivoyager.jpg)
Jupiter and Io viewed from Europa. (Also featured in our website header at [ivoyager.dev](https://www.ivoyager.dev).)  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2025/03/saturn-rings-shadows-detail-ivoyager-0.0.24.jpg)
Saturn and its rings. **New!** Just in time for our beta release... We have shadows! Semi-transparent shadows from Saturn's rings are visible here. After considerable effort, we have shadows working at both planetary and spacecraft distance scales (see ISS below).  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2025/03/iss-shadows-ivoyager-0.0.24.jpg)
The International Space Station. This is one of only three spacecraft at this time. I'd like to add more with historical flight paths or representative orbits. We [need more 3D models](https://github.com/ivoyager/ivoyager_core/issues/2) to do that...  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2025/09/ivoyager-planetarium-gui-0.1.jpg)
Our [Planetarium's](https://www.ivoyager.dev/planetarium/) interface provides easy navigation and tons of information. Links in the panels open Wikepedia.org pages for more than a hundred solar system bodies and dozens of astronomy concepts.  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2025/10/ivoyager-asteroids-0.1.jpg)
Positions of ~70,000 asteroids. Here, the Main Belt asteroids are cyan, with the Hilda subset in yellow. The Trojans at Jupiter's L4 and L5 are magenta. (For programmers: Each point is a GPU vertex shader that knows its own orbital elements and calculates its own position.)  
<br />

![](https://t2civ.com/wp-content/uploads/2023/03/astropolis-abstract.jpg)
Asteroid orbits. Or is it an abstract painting? The "wheel" at the center are the Trojans (yellow) encompassing the Main Belt (reddish). The outer orbit lines are the sparse Centaurs (cyan) and Trans-Neptune Objects (orangish).  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/uranus-moons-ivoyager.jpg)
Uranus' moons are an interesting cast of characters (literally). The planet's 98° axial tilt puts the inner solar system almost directly to the south in this image.  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/solar-system-pluto-flyby-ivoyager.jpg)
Here's the solar system on July 14, 2015, the day of New Horizon's flyby of the dwarf planet Pluto (♇). Not coincidentally, Pluto was near the plane of the ecliptic at this time.  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/pluto-charon-ivoyager.jpg)
Pluto and its moon Charon. Both are tidally locked so their facing sides never change.  
<br />

![](https://www.ivoyager.dev/wp-content/uploads/2025/10/ivoyager-widgets-0.1.jpg)
For developers, you can quickly build GUI from a [large set of widgets](https://github.com/ivoyager/ivoyager_core/tree/master/gui_widgets). These widgets communicate with simulator internals and in some cases build themselves from simulator data (e.g., the planet/moon navigator widget above/left). See also the Planetarium GUI above, which is composed entirely of existing widgets in the Core plugin.
