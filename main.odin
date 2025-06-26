package main

import "base:intrinsics"
import "base:runtime"
import "core:math/linalg"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import sglue "shared:sokol/glue"
import slog "shared:sokol/log"
import stbi "vendor:stb/image"

ROTATION_SPEED :: 90

Globals :: struct {
	pip:         sg.Pipeline,
	bind:        sg.Bindings,
	pass_action: sg.Pass_Action,
	image:       sg.Image,
	sampler:     sg.Sampler,
	rotation:    f32,
}
g: ^Globals

Vec2 :: [2]f32
Vec3 :: [3]f32

Mat4 :: matrix[4, 4]f32

Vertex :: struct {
	pos:   Vec3,
	color: sg.Color,
	uv:    Vec2,
}

init :: proc "c" () {
	context = runtime.default_context()

	g = new(Globals)

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})


	WHITE :: sg.Color{1, 1, 1, 1}
	RED :: sg.Color{1, 0, 0, 1}
	BLUE :: sg.Color{0, 0, 1, 1}
	PURP :: sg.Color{1, 0, 1, 1}

	// a vertex buffer with 3 vertices
	vertices := []Vertex {
		{pos = {-0.5, -0.5, 0.0}, color = WHITE, uv = {0, 0}},
		{pos = {0.5, -0.5, 0.0}, color = RED, uv = {1, 0}},
		{pos = {-0.5, 0.5, 0.0}, color = BLUE, uv = {0, 1}},
		{pos = {0.5, 0.5, 0.0}, color = PURP, uv = {1, 1}},
	}
	g.bind.vertex_buffers[0] = sg.make_buffer({data = sg_range(vertices)})
	
	// odinfmt: disable
	indices := []u16 {
		0, 1, 2,
		2, 1, 3,
	}
	// odinfmt: enable
	g.bind.index_buffer = sg.make_buffer({usage = {index_buffer = true}, data = sg_range(indices)})

	w, h: i32
	pixels := stbi.load("assets/senjou-starry.png", &w, &h, nil, 4)
	assert(pixels != nil)

	g.image = sg.make_image(
	{
		width = w,
		height = h,
		pixel_format = .RGBA8,
		data = {
			subimage = {
				0 = {
					0 = {
						ptr  = pixels,
						size = uint(w * h * 4), // 4 bytes per pixel
					},
				},
			},
		},
	},
	)
	stbi.image_free(pixels)

	g.bind.images = {
		IMG_tex = g.image,
	}

	g.sampler = sg.make_sampler({})
	g.bind.samplers = {
		SMP_smp = g.sampler,
	}

	// create a shader and pipeline object (default render states are fine for triangle)
	g.pip = sg.make_pipeline(
		{
			shader = sg.make_shader(triangle_shader_desc(sg.query_backend())),
			index_type = .UINT16,
			layout = {
				attrs = {
					ATTR_triangle_position = {format = .FLOAT3},
					ATTR_triangle_color0 = {format = .FLOAT4},
					ATTR_triangle_uv = {format = .FLOAT2},
				},
			},
		},
	)

	// a pass action to clear framebuffer to black
	g.pass_action = {
		colors = {0 = {load_action = .CLEAR, clear_value = {r = 0.5, g = 0.3, b = 0.6, a = 0.1}}},
	}
}

frame :: proc "c" () {
	context = runtime.default_context()

	dt := f32(sapp.frame_duration())
	g.rotation += linalg.to_radians(ROTATION_SPEED * dt)

	p := linalg.matrix4_perspective_f32(70, sapp.widthf() / sapp.heightf(), 0.0001, 1000)
	m :=
		linalg.matrix4_translate_f32({0, 0, -1.5}) *
		linalg.matrix4_from_yaw_pitch_roll_f32(g.rotation, 0, 0) *
		linalg.matrix4_rotate_f32(linalg.to_radians(f32(180)), {1, 0, 0})

	sg.begin_pass({action = g.pass_action, swapchain = sglue.swapchain()})

	// multiplication order matters
	vs_params := Vs_Params {
		mvp = p * m,
	}

	sg.apply_pipeline(g.pip)
	sg.apply_bindings(g.bind) // move vertices / images etc.. to be bound here? I assume that would be better if they change frame to frame?
	sg.apply_uniforms(UB_Vs_Params, sg_range(&vs_params))
	sg.draw(0, 6, 1)
	sg.end_pass()
	sg.commit()

}

cleanup :: proc "c" () {
	context = runtime.default_context()
	// todo destroy others?
	free(g)
	sg.shutdown()
}


sg_range :: proc {
	sg_range_from_struct,
	sg_range_from_slice,
}

sg_range_from_struct :: proc(s: ^$T) -> sg.Range where intrinsics.type_is_struct(T) {
	return {ptr = s, size = size_of(T)}
}
sg_range_from_slice :: proc(s: []$T) -> sg.Range {
	return {ptr = raw_data(s), size = len(s) * size_of(s[0])}
}

main :: proc() {
	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			cleanup_cb = cleanup,
			width = 800,
			height = 600,
			window_title = "triangle",
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}
