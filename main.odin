package main

import "base:intrinsics"
import "base:runtime"
import "core:log"
import "core:math"
import "core:math/linalg"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import sglue "shared:sokol/glue"
import slog "shared:sokol/log"
import stbi "vendor:stb/image"

default_context: runtime.Context

ROTATION_SPEED :: 10

Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32

Mat4 :: matrix[4, 4]f32

Vertex :: struct {
	pos:   Vec3,
	color: sg.Color,
	uv:    Vec2,
}

Camera :: struct {
	position: Vec3,
	target:   Vec3,
	look:     Vec2,
}

Globals :: struct {
	pip:         sg.Pipeline,
	bind:        sg.Bindings,
	pass_action: sg.Pass_Action,
	image:       sg.Image,
	image2:      sg.Image,
	sampler:     sg.Sampler,
	rotation:    f32,
	camera:      Camera,
}
g: ^Globals

init :: proc "c" () {
	context = default_context

	g = new(Globals)

	g.camera = {
		position = {0, 0, 2},
		target   = {0, 0, 1},
	}

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})

	sapp.show_mouse(false)
	sapp.lock_mouse(true)

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

	g.image = load_image("assets/senjou-starry.png")
	g.image2 = load_image("assets/Mossy-TileSet.png")

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
		depth = {
			write_enabled = true, // always write to depth buffer
			compare       = .LESS_EQUAL, // don't render objects behind objects in view
		},
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
		colors = {0 = {load_action = .CLEAR, clear_value = {r = 0.4, g = 0.2, b = 0.7, a = 1}}},
	}
}

frame :: proc "c" () {
	context = default_context

	dt := f32(sapp.frame_duration())

	update_camera(dt)
	update_bullets(dt)

	g.rotation += linalg.to_radians(ROTATION_SPEED * dt)

	p := linalg.matrix4_perspective_f32(70, sapp.widthf() / sapp.heightf(), 0.0001, 1000)

	// translate to put the object in the right place
	// spin it with yaw_pitch_roll rotation
	// rotate it to make the image right-side up
	v := linalg.matrix4_look_at_f32(g.camera.position, g.camera.target, {0, 1, 0})

	objects := []Object {
		{{0, 0, 0}, {0, 0, 0}, g.image},
		{{1, 0, 0}, {0, 0, 0}, g.image},
		{{2, 0, 0}, {0, 0, 0}, g.image},
		{{3, 0, 0}, {0, 0, 0}, g.image},
		{{0, 1, 0}, {0, 0, 0}, g.image},
		{{1, 1, 0}, {0, 0, 0}, g.image},
		{{2, 1, 0}, {0, 0, 0}, g.image},
		{{3, 1, 0}, {0, 0, 0}, g.image},
		{{-1, 0, 0.5}, {0, 45, 0}, g.image2},
		{{-2, 0, 1}, {0, 45, 0}, g.image2},
		{{-3, 0, 1.5}, {0, 45, 0}, g.image2},
		{{-4, 0, 2}, {0, 45, 0}, g.image2},
		{{-1, 1, 0.5}, {0, 45, 0}, g.image2},
		{{-2, 1, 1}, {0, 45, 0}, g.image2},
		{{-3, 1, 1.5}, {0, 45, 0}, g.image2},
		{{-4, 1, 2}, {0, 45, 0}, g.image2},
	}

	sg.begin_pass({action = g.pass_action, swapchain = sglue.swapchain()})

	sg.apply_pipeline(g.pip)

	binding := g.bind

	for obj in objects {
		m :=
			linalg.matrix4_translate_f32(obj.pos) *
			linalg.matrix4_from_yaw_pitch_roll_f32(
				linalg.to_radians(obj.rot.y),
				linalg.to_radians(obj.rot.x),
				linalg.to_radians(obj.rot.z),
			) *
			linalg.matrix4_rotate_f32(linalg.to_radians(f32(180)), {1, 0, 0})
		// multiplication order matters
		vs_params := Vs_Params {
			mvp = p * v * m,
		}

		binding.images = {
			IMG_tex = obj.img,
		}

		sg.apply_bindings(binding) // move vertices / images etc.. to be bound here? I assume that would be better if they change frame to frame?
		sg.apply_uniforms(UB_Vs_Params, sg_range(&vs_params))
		sg.draw(0, 6, 1)
	}

	for bullet in bullets {
		m :=
			linalg.matrix4_translate_f32(bullet.pos) *
			linalg.matrix4_from_yaw_pitch_roll_f32(
				linalg.to_radians(bullet.rot.x),
				linalg.to_radians(bullet.rot.y),
				linalg.to_radians(bullet.rot.z),
			) *
			linalg.matrix4_rotate_f32(linalg.to_radians(f32(180)), {1, 0, 0})
		// multiplication order matters
		vs_params := Vs_Params {
			mvp = p * v * m,
		}

		binding.images = {
			IMG_tex = bullet.img,
		}

		sg.apply_bindings(binding) // move vertices / images etc.. to be bound here? I assume that would be better if they change frame to frame?
		sg.apply_uniforms(UB_Vs_Params, sg_range(&vs_params))
		sg.draw(0, 6, 1)
	}
	sg.end_pass()
	sg.commit()

	mouse_move = {}
}
SHOOT_SPEED :: 0.1

MOVE_SPEED :: 3
LOOK_SENSITIVITY :: 0.3

update_camera :: proc(dt: f32) {
	move_input := Vec2{0, 0}
	if key_down[.W] do move_input.y = 1
	else if key_down[.S] do move_input.y = -1
	if key_down[.A] do move_input.x = -1
	else if key_down[.D] do move_input.x = 1

	look_input: Vec2 = -mouse_move * LOOK_SENSITIVITY
	g.camera.look += look_input
	g.camera.look.x = math.wrap(g.camera.look.x, 360)
	g.camera.look.y = math.clamp(g.camera.look.y, -90, 90)

	look_mat := linalg.matrix4_from_yaw_pitch_roll_f32(
		linalg.to_radians(g.camera.look.x),
		linalg.to_radians(g.camera.look.y),
		0,
	)
	forward := (look_mat * Vec4{0, 0, -1, 1}).xyz
	right := (look_mat * Vec4{1, 0, 0, 1}).xyz

	move_dir := forward * move_input.y + right * move_input.x

	motion := linalg.normalize0(move_dir) * MOVE_SPEED * dt

	if key_down[.C] {
		// TODO: not working
		g.camera.look = {722, 300}
		g.camera.position = {0, 0, 2}
		g.camera.target = {0, 0, 2}
	} else {
		g.camera.position += motion
		g.camera.target = g.camera.position + forward
	}
}

Object :: struct {
	pos: Vec3,
	rot: Vec3,
	img: sg.Image,
}

Bullet :: struct {
	dir: Vec3,
	pos: Vec3,
	rot: Vec3,
	img: sg.Image,
}

bullets: [dynamic]Bullet

update_bullets :: proc(dt: f32) {

	if mouse_down {
		mouse_down = false
		append(
			&bullets,
			Bullet {
				dir = g.camera.target - g.camera.position,
				pos = g.camera.target,
				rot = Vec3{0.0, 0.0, 0.0},
				img = g.image,
			},
		)
	}

	for &bullet in bullets {
		bullet.rot += Vec3{0, 3, 3}
		bullet.pos += bullet.dir * SHOOT_SPEED
	}

}

mouse_down: bool = false
mouse_move: Vec2
mouse_pos: Vec2
key_down: #sparse[sapp.Keycode]bool

event :: proc "c" (ev: ^sapp.Event) {
	context = default_context

	#partial switch ev.type {
	case .MOUSE_DOWN:
		mouse_down = true
	case .MOUSE_UP:
		mouse_down = false
	case .MOUSE_MOVE:
		mouse_move += {ev.mouse_dx, ev.mouse_dy}
		mouse_pos = {ev.mouse_x, ev.mouse_y}
	case .KEY_DOWN:
		key_down[ev.key_code] = true
	case .KEY_UP:
		key_down[ev.key_code] = false
	}

}
// "assets/senjou-starry.png"
load_image :: proc(filename: cstring) -> sg.Image {
	w, h: i32
	pixels := stbi.load(filename, &w, &h, nil, 4)
	assert(pixels != nil)

	image := sg.make_image(
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

	return image
}

cleanup :: proc "c" () {
	context = default_context
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
	context.logger = log.create_console_logger()
	default_context = context

	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			event_cb = event,
			cleanup_cb = cleanup,
			width = 1920,
			height = 1080,
			window_title = "triangle",
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}
