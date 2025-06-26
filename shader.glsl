@header package main

@vs vs
in vec2 pos;

void main() {
	gl_Position = vec4(pos, 0, 1);
}
@end

@fs fs
out vec4 color;

void main() {
	color = vec4(1, 0, 0, 1);
}
@end

@program main vs fs
