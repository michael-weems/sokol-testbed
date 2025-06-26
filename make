#!/usr/bin/env bash

shaders=$(find . -name '*.glsl')
for shader in "${shaders[@]}"; do
	name=$(basename -- "$shader" .glsl)
	dir=$(dirname $shader)
	sokol-shdc -i "$shader" -o "${dir}/${name}_glsl.odin" -f sokol_odin -l glsl430
	if [ $? != 0 ];then
		echo "[error]: $shader"
		exit 1
	fi
done

odin run . -debug
