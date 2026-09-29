// cloud_shell.cube.off.gdshader
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

// cloud_shell.cube.gdshader for a body with an atmosphere under the Off tier of Atmosphere Quality,
// which IVAssetPreloader binds in its place (off_shader_variants). ATM_OFF draws the air in
// front of the disc in a cheap closed form, with none of the quadrature; see THE OFF VARIANT
// in _atmosphere.gdshaderinc's header.
#define ATM_OFF
#include "_cloud_shell.cube.gdshaderinc"
