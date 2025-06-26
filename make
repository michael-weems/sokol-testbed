#!/usr/bin/env bash

shaders=$(find . -name '*.glsl')
for shader in "${shaders[@]}"; do
	name=$(basename -- "$shader" .glsl)
	dir=$(dirname $shader)
	sokol-shdc -i "$shader" -o "${dir}/${name}_gen_shdr.odin" -f sokol_odin -l hlsl5
done

odin run .
