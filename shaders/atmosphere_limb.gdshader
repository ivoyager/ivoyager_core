// atmosphere_limb.gdshader
// This file is part of I, Voyager
// https://ivoyager.dev
// *****************************************************************************
// Copyright 2019-2026 Charlie Whitfield
// I, Voyager is a registered trademark of Charlie Whitfield in the US
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
// *****************************************************************************
shader_type spatial;

// A body's atmosphere beyond its limb, for the IVShellsModel overlay shell that encloses it;
// name it in that shell's shells.tsv "shader" column. The body is _atmosphere_limb.gdshaderinc,
// which atmosphere_limb.min.gdshader shares for the Min tier of Atmosphere Quality.
#include "_atmosphere_limb.gdshaderinc"
