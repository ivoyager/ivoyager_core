# universe_template.gd
# This file is part of I, Voyager
# https://ivoyager.dev
# *****************************************************************************
# Copyright 2017-2025 Charlie Whitfield
# I, Voyager is a registered trademark of Charlie Whitfield in the US
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# *****************************************************************************
class_name IVUniverseTemplate
extends Node3D

## Template-only root scene node. And Core plugin documentation!
##
## This "Universe" scene tree is provided as a template. It will work as a
## simulator root if made the main sceen, but shouldn't be edited since it is in
## the plugin directory. You can make a duplicate of this scene and move it to
## your project.[br][br]
##
## [b]Scene Tree Construction[/b][br][br]
##
## The schematic below shows one possible scene tree organization for a game.
## Note that much of the tree is built by code: specifically, the physical solar
## system at child index 0 and "program" nodes added at the end. The part
## constructed in the Godot Editor is mainly the UI tree. [IVUniverseTemplate]
## has the Core plugin UI nodes shown but lacks game panels, spash screen,
## exit button, and nodes from the Save plugin.[br][br]
##
## (Note: It's in our
## [url=https://github.com/orgs/ivoyager/discussions/5]roadmap[/url] to make
## the physical part editable in the Editor too. The simulator was developed
## using data tables, so that's mainly what it supports at this time.)
## 
## [codeblock] 
##
## Universe
##
##    |- STAR_SUN                    #
##          |- PLANET_MERCURY        #  IVBody instances and other
##          |- PLANET_VENUS          #  "tree_nodes" are procedurally 
##          |- PLANET_EARTH          #  built from *.tsv data tables
##                 |- SPACECRAFT_ISS #  in "data/tables" directory
##                 |- MOON_MOON      #
##          |- ...                   #
##
##    |- IVWorldEnvironment
##    |- IVFragmentIdentifier
##    |- IVTopUI
##          |- IVWorldController
##          |- IVMouseTargetLabel
##          |- IVShowHideUI
##                 |- GamePanel1     #
##                 |- GamePanel2     #  compose with "ui_widgets"
##                 |- etc...         #  and "ui_helpers"
##          |- GameSplashScreen      #
##          |- IVMainMenuBasePopup
##                 |- IVSaveAsButton [from the Save plugin]
##                 |- IVLoadButton [from the Save plugin]
##                 |- IVOptionsButton
##                 |- IVHotkeysButton
##                 |- IVExitButton
##                 |- IVQuitButton
##                 |- IVResumeButton
##          |- IVSaveDialog [from the Save plugin]
##          |- IVLoadDialog [from the Save plugin]
##          |- IVOptionsPopup
##          |- IVHotkeysPopup
##          |- IVConfirmationDialog
##
##    |- IVCameraHandler             #
##    |- IVTimekeeper                #  "program" nodes are added by 
##    |- IVBodyHUDsState             #  IVCoreInitializer (these can
##    |- IVSBGHUDsState              #  be modified)
##    |- IVInputHandler              #
##    |- etc...                      #
##
## # Note: Actual node names in the tree omit the "IV" class prefixes.
## [/codeblock][br]
##
## The simulator root node can be specified explicitly in [IVCoreInitializer] or
## simply by naming it "Universe". (If the former, the node name doesn't matter.
## In any case, we call this root node "Universe" in plugin documentation.)[br][br]
##
## [IVWorldEnvironment] is in directory "tree_nodes" with [IVUniverseTemplate]
## and Node3D classes.[br][br]
##
## UI classes above from the Core plugin are in directory "ui_main".
## See [IVFragmentIdentifier], [IVTopUI], [IVWorldController], [IVMouseTargetLabel],
## [IVShowHideUI], [IVMainMenuBasePopup], [IVOptionsPopup], [IVHotkeysPopup],
## [IVConfirmationDialog].[br][br]
##
## The "program" directory contains both [Node] and [RefCounted] program
## classes, which are essentially "small-s singletons" that support the
## simulator. These are instantiated and added to dictionary [member IVGlobal.program]
## (and nodes are added to the scene tree) as specified in [IVCoreInitializer].
## An external project can remove, replace, subclass, or add to these at project
## init.[br][br]
##
## [IVTableSystemBuilder] (with other "builder" and "finisher" classes) builds
## the physical star system(s) and inserts it (or them) before other children of
## Universe. Shown above are the [IVBody] instances (stars, planets, moons,
## spacecraft, etc.). This class and other components of the physical system
## tree are in directories "tree_nodes" and "tree_refs".[br][br]
##
## [b]Splash Screen[/b][br][br]
##
## By default, the physical system is built immediately after the program starts
## and initializes. To implement a splash screen, set [member IVCoreSettings.wait_for_start]
## = true and add the [IVStartButton] widget somewhere in your splash screen
## (the widget calls [method IVStateManager.start] when pressed). Use [signal
## IVStateManager.state_changed] and [member IVStateManager.show_splash_screen]
## to manage splash screen visibility.
## [url=https://github.com/ivoyager/project_template]Project Template[/url] has
## an example splash screen implementation.[br][br]
##
## [b]GUI Scene Tree[/b][br][br]
##
## [IVTopUI] has documentation on GUI scene tree construction. The Core plugin
## has a large set of widgets (in directory "ui_widgets") that know how to talk
## to the simulator: menu buttons, date/time label, selection data containers,
## etc.[br][br]
## 
## [b]Simulator Pause[/b][br][br]
##
## There are two main options for scene tree pause in the simulator:[br][br]
##
## 1. If [code]Universe.pause_mode == PROCESS_MODE_ALWAYS[/code] (default) or
## inherits always, time will still stop during pause because [IVTimekeeper]
## is pausable (does not inherit). However, [IVCamera] can be moved around
## the solar system, [IVWorldController] allows view zoom and rotation,
## [IVMouseTargetLabel] indicates what's under the mouse (this requires
## [IVBody] processing for bodies and [IVFragmentIdentifier] processing for
## orbit lines and asteroid points), and GUI scrollbars, foldables, and so on
## will work.[br][br]
## 
## 2. If [code]Universe.pause_mode == PROCESS_MODE_PAUSABLE[/code] or inherits
## pausable, then almost everything freezes during pause. The 
## camera can't be moved, the the view can't be zoomed or rotated, there is
## no identification feedback at the mouse position, and GUI is frozen (except
## a few special cases including the pause button). Main menu, options and
## other "main" popup panels will still work.[br][br]
##
## Some mix of the two options may be posible by setting [member Node.pause_mode]
## in individual UI and program nodes.[br][br]
##
## [b]Origin Shifting[/b][br][br]
##
## We use origin shifting to prevent "imprecision shakes" caused by vast scale
## differences, e.g, when viewing Pluto at 40 au from the Sun. To do so,
## [IVCamera] adjusts the translation of Universe every frame to keep the camera
## at the origin.

## Don't free on load. This constant only matters if the
## [url=https://github.com/ivoyager/ivoyager_save]Save plugin[/url] is used.
## Nodes have persistence only if they and all ancestors have this constant set
## to PERSIST_PROPERTIES_ONLY or PERSIST_PROCEDURAL.
const PERSIST_MODE := 1 # Godot ISSUE 4.5.1: Class doc broken w/ IVGlobal.PERSIST_PROPERTIES_ONLY 
