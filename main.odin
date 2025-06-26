package main

import "base:runtime"
import "core:log"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

default_context: runtime.Context

Globals :: struct {
	shader:        sg.Shader,
	pipeline:      sg.Pipeline,
	vertex_buffer: sg.Buffer,
}
g: ^Globals // NOTE: this is good for hot-reloading, as it enables the game to load via dll and the main program's state stays in-memory
// NOTE: for release, might want to not make this a global? not sure, need to investigate


main :: proc() {
	context.logger = log.create_console_logger()
	default_context = context

	sapp.run(
		{
			window_title = "Hello Sokol",
			width        = 800,
			height       = 600,

			// sokol app needs it's own allocator and logger
			allocator    = sapp.Allocator(shelpers.allocator(&default_context)),
			logger       = sapp.Logger(shelpers.logger(&default_context)),
			init_cb      = init_cb,
			frame_cb     = frame_cb,
			cleanup_cb   = cleanup_cb,
			event_cb     = event_cb,
		},
	)
}

init_cb :: proc "c" () {
	context = default_context

	sg.setup(
		{
			// get graphics environment info setup. Normally we'd have to do this all ourselves, but sokol helpers have this 'glue' function for us
			environment = shelpers.glue_environment(),

			// sokol gfx needs it's own allocator and logger
			allocator   = sg.Allocator(shelpers.allocator(&default_context)),
			logger      = sg.Logger(shelpers.logger(&default_context)),
		},
	)

	g = new(Globals)

	g.shader = sg.make_shader(main_shader_desc(sg.query_backend()))
	
	// odinfmt: disable
	g.pipeline = sg.make_pipeline({
		shader = g.shader,
		layout = {
			attrs = {
				ATTR_main_pos = {format = .FLOAT2},
			}
		}
	})
	// odinfmt: enable

	
	// odinfmt: disable
	vertices := []f32{
		-0.3, -0.3,
		 0.0,  0.3,
		 0.3, -0.3
	}
	// odinfmt: enable
	g.vertex_buffer = sg.make_buffer(
		{data = {ptr = raw_data(vertices), size = len(vertices) * size_of(vertices[0])}},
	)
}

frame_cb :: proc "c" () {
	context = default_context

	// swapchain is most important thing: application info (window width/height, etc...)
	sg.begin_pass({swapchain = shelpers.glue_swapchain()})

	sg.apply_pipeline(g.pipeline)
	sg.apply_bindings({vertex_buffers = {0 = g.vertex_buffer}})
	sg.draw(0, 3, 1)

	sg.end_pass()
	sg.commit()
}

cleanup_cb :: proc "c" () {
	context = default_context

	sg.destroy_pipeline(g.pipeline)
	sg.destroy_shader(g.shader)

	free(g)
	sg.shutdown()
}

event_cb :: proc "c" (ev: ^sapp.Event) {
	context = default_context
	log.debug(ev.type)
}
