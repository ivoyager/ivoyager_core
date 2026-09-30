// cloud_shell.gdshader
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

// A lit, translucent cloud deck, sampled from an equirect map. The body is
// _cloud_shell.gdshaderinc, which cloud_shell.airless.gdshader shares for a body with no
// atmosphere and cloud_shell.min.gdshader for the Min tier of Atmosphere Quality.
#include "_cloud_shell.gdshaderinc"
