package main

import "base:runtime"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import sglue "shared:sokol/glue"
import slog "shared:sokol/log"

Globals :: struct {
	pip:         sg.Pipeline,
	bind:        sg.Bindings,
	pass_action: sg.Pass_Action,
}
g: ^Globals

init :: proc "c" () {
	context = runtime.default_context()

	g = new(Globals)

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})

	// a vertex buffer with 3 vertices
		// odinfmt: disable
    vertices := [?]f32 {
        // positions         // colors
         0.0,  0.5, 0.5,     1.0, 0.0, 0.0, 1.0,
         0.5, -0.5, 0.5,     0.0, 1.0, 0.0, 1.0,
        -0.5, -0.5, 0.5,     0.0, 0.0, 1.0, 1.0,
    }
		// odinfmt: enable
	g.bind.vertex_buffers[0] = sg.make_buffer({data = {ptr = &vertices, size = size_of(vertices)}})

	// create a shader and pipeline object (default render states are fine for triangle)
	g.pip = sg.make_pipeline(
		{
			shader = sg.make_shader(triangle_shader_desc(sg.query_backend())),
			layout = {
				attrs = {
					ATTR_triangle_position = {format = .FLOAT3},
					ATTR_triangle_color0 = {format = .FLOAT4},
				},
			},
		},
	)

	// a pass action to clear framebuffer to black
	g.pass_action = {
		colors = {0 = {load_action = .CLEAR, clear_value = {r = 0.5, g = 0.4, b = 0.6, a = 0.4}}},
	}
}

frame :: proc "c" () {
	context = runtime.default_context()
	sg.begin_pass({action = g.pass_action, swapchain = sglue.swapchain()})
	sg.apply_pipeline(g.pip)
	sg.apply_bindings(g.bind)
	sg.draw(0, 3, 1)
	sg.end_pass()
	sg.commit()

}

cleanup :: proc "c" () {
	context = runtime.default_context()
	free(g)
	sg.shutdown()
}

main :: proc() {
	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			cleanup_cb = cleanup,
			width = 1000,
			height = 1000,
			window_title = "triangle",
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}
