#!/usr/bin/env bash

# TODO: dynamically compile all shaders
shaders=$(find . -name '*.glsl')
for shader in "${shaders[@]}"; do
	name=$(basename $shader)
	dir=$(dirname $shader)
	sokol-shdc -i "$shader.glsl" -o "${dir}/${name}_gen_shader.odin" -f sokol_odin -l hlsl5
done
odin run .
