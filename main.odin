package main

import "base:runtime"
import "core:log"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

default_context: runtime.Context

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
}

frame_cb :: proc "c" () {
	context = default_context

	// swapchain is most important thing: application info (window width/height, etc...)
	sg.begin_pass({swapchain = shelpers.glue_swapchain()})
	sg.end_pass()

	sg.commit()

}

cleanup_cb :: proc "c" () {
	context = default_context

	sg.shutdown()
}

event_cb :: proc "c" (ev: ^sapp.Event) {
	context = default_context
	log.debug(ev.type)
}
