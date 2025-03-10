# I, Voyager - Core (plugin)

This Godot Editor plugin runs a solar system simulation.

[Homepage](https://www.ivoyager.dev)  
[Forum](https://www.ivoyager.dev/forum)  
[Issues](https://github.com/ivoyager/ivoyager_core/issues)  
[Changelog](https://github.com/ivoyager/ivoyager_core/blob/master/CHANGELOG.md)  

### Requirements

* ivoyager_tables (plugin) - See [repository](https://github.com/ivoyager/ivoyager_tables) for installation instructions.
* ivoyager_units (plugin) - See [repository](https://github.com/ivoyager/ivoyager_units) for installation instructions.
* ivoyager_assets - **Note:** As of v0.0.18, the editor plugin will manage downloads and updates of the non-Git-tracked assets. Just press "Download" at the editor prompt.

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

Then enable "I, Voyager - Tables", "I, Voyager - Units" and "I, Voyager - Core" (Core after the other two) from editor menu Project/Project Settings/Plugins. The editor plugin will prompt you to download the non-Git-tracked assets.

### What is I, Voyager?
I, Voyager is
1. an open-source software planetarium 
2. a development platform for creating games and educational apps in a realistic solar system.

It is designed to be improved, modified and extended by the community. I, Voyager runs on the open-source [Godot Engine](https://godotengine.org) and primarily uses Godot’s easy-to-learn [GDScript](http://docs.godotengine.org/en/stable/getting_started/scripting/gdscript/gdscript_basics.html#doc-gdscript) (similar to Python). It can be extended into an independent free-standing project (a game or other software product) using GDScript, C# or C++.

If you are interested in our future development, see our official [Roadmap!](https://www.ivoyager.dev/forum/index.php?p=/discussion/41/roadmap)

### What does I, Voyager cost?
I, Voyager is free to use and distribute under the permissive [Apache License 2.0](https://github.com/ivoyager/ivoyager/blob/master/LICENSE.txt). Projects built with I, Voyager are owned by their creators. You are free to give away or sell what you make. There are no royalties or fees.

### How do I contribute to I, Voyager development?
Help us grow the community by following us on [Twitter](https://twitter.com/IVoygr) and [Facebook](https://www.facebook.com/IVoygr/). Exchange ideas and give and receive help on our [Forum](https://www.ivoyager.dev/forum). Report bugs or astronomical inaccuracies at our issue tracker [here](https://github.com/ivoyager/issues). Or contribute to code development via pull requests to our repositories at [github.com/ivoyager](https://github.com/ivoyager).

### How can I support this effort financially?
Please visit our [GitHub Sponsors page!](https://github.com/sponsors/charliewhitfield) Become a Mercury Patron for $2 per month! Or, if you are a company, please consider sponsoring us as a Saturn or Jupiter Patron. Goal #1: Make I, Voyager into a non-profit entity. This will shield us from tax liability, allow us to apply for grants, and secure our existence as a collaborative open-source project into the future.

### Where did I, Voyager come from?
Creator and lead programmer Charlie Whitfield stumbled into the Godot Engine in November, 2017. By December there were TestCubes orbiting bigger TestCubes orbiting one really big TestCube*. The name "I, Voyager" is a play on Voyager 1, the spacecraft that captured an [image of Earth](https://www.planetary.org/explore/space-topics/earth/pale-blue-dot.html) from 6.4 billion kilometers away. I, Voyager became an open-source project on Carl Sagan's birthday, November 9, 2019.

(* Godot devs, bring back the [TestCube](https://docs.godotengine.org/en/2.1/classes/class_testcube.html)!)

### Authors, credits and legal
I, Voyager is possible due to public interest in space exploration and funding of government agencies like NASA and ESA, and the scientists and engineers that they employ. I, Voyager is also possible due to open-source software developers, and especially [Godot Engine's creators and contributors](https://github.com/godotengine/godot/blob/master/AUTHORS.md). Copyright 2017-2024 Charlie Whitfield. I, Voyager is a registered trademark of Charles Whitfield in the U.S. For up-to-date lists of authors, credits, and license information, see files in our code repository [here](https://github.com/ivoyager/ivoyager) or follow these links:
* [AUTHORS.md](https://github.com/ivoyager/ivoyager/blob/master/AUTHORS.md) - contributors to I, Voyager code and assets.
* [CREDITS.md](https://github.com/ivoyager/ivoyager/blob/master/CREDITS.md) - individuals and organizations whose efforts made I, Voyager possible.  
* [LICENSE.txt](https://github.com/ivoyager/ivoyager/blob/master/LICENSE.txt) - the I, Voyager license.
* [3RD_PARTY.txt](https://github.com/ivoyager/ivoyager/blob/master/3RD_PARTY.txt) - copyright and license information for 3rd-party assets distributed in I, Voyager.

### Screen captures!

Our site header for [ivoyager.dev](https://www.ivoyager.dev) is also from the Planetarium!

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/europa-jupiter-io-ivoyager.jpg)
Jupiter and Io viewed from Europa. We've hidden the interface for one of the best views in the solar system.

![](https://www.ivoyager.dev/wp-content/uploads/2019/10/moons-of-jupiter.jpg)
Jupiter and the four Galilean moons – Io, Europa, Ganymede and Callisto – embedded in the orbital paths of many smaller moons.

![](https://www.ivoyager.dev/wp-content/uploads/2019/12/saturn-rings-moons-ivoyager.jpg)
Saturn's rings and its close-orbiting moons.

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/uranus-moons-ivoyager.jpg)
Uranus' moons are an interesting cast of characters (literally). The planet's 98° axial tilt puts the inner solar system almost directly to the south in this image.

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/solar-system-pluto-flyby-ivoyager.jpg)
Here's the solar system on July 14, 2015, the day of New Horizon's flyby of the dwarf planet Pluto (♇). Not coincidentally, Pluto was near the plane of the ecliptic at this time.

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/pluto-charon-ivoyager.jpg)
Pluto and its moon Charon to scale. Both are tidally locked so their facing sides never change.

![](https://www.ivoyager.dev/wp-content/uploads/2020/01/asteroids-ivoyager-1.jpg)
Jupiter (♃) is the shepherd of the Solar System, as is evident in the orbits of asteroids (64,738 shown here). The [Main Belt](https://en.wikipedia.org/wiki/Asteroid_belt) (the ring) and [Trojans](https://en.wikipedia.org/wiki/Jupiter_trojan) (the two lobes leading and lagging Jupiter by 60°) are the most obvious features here. [Hildas](https://en.wikipedia.org/wiki/Hilda_asteroid) are also visible. I, Voyager has orbital data for >600,000 asteroids (numbered and multiposition) but can run with a reduced set filtered by magnitude.
 
![](https://www.ivoyager.dev/wp-content/uploads/2020/01/asteroids-ivoyager-2.jpg)
Main Belt and Trojans viewed from the side. We use the GPU to calculate and update asteroid positions (each asteroid is a shader vertex that knows its own orbital parameters).

![](https://www.ivoyager.dev/wp-content/uploads/2021/02/ivoyager-planetarium-gui.jpg)
The Planetarium has easy-to-use interface panels that can be hidden.

![](https://www.ivoyager.dev/wp-content/uploads/2021/02/ivoyager-gui-widgets.jpg)
For developers, we have a large set of GUI widgets that know how to talk to the simulator. These can be easily dropped into Containers to make your custom GUI however you like.

![](https://www.ivoyager.dev/wp-content/uploads/2021/02/template-gui.jpg)
Here's our "starter GUI" in the Project Template to get you going on game development.
