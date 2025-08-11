package main

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:strings"
import sapp "shared:sokol/app"
import sa "shared:sokol/audio"
import sg "shared:sokol/gfx"
import sglue "shared:sokol/glue"
import slog "shared:sokol/log"
import stbi "vendor:stb/image"

// ANSI escape codes for colors
FAIL :: "\x1b[31mfail >>\x1b[0m"
DONE :: "\x1b[32mdone >>\x1b[0m"

// NOTE: ----------------------------------------------
// NOTE: move to it's own module / package

/*
[Master RIFF chunk]
   FileTypeBlocID  (4 bytes) : Identifier « RIFF »  (0x52, 0x49, 0x46, 0x46)
   FileSize        (4 bytes) : Overall file size minus 8 bytes
   FileFormatID    (4 bytes) : Format = « WAVE »  (0x57, 0x41, 0x56, 0x45)

[Chunk describing the data format]
   FormatBlocID    (4 bytes) : Identifier « fmt␣ »  (0x66, 0x6D, 0x74, 0x20)
   BlocSize        (4 bytes) : Chunk size minus 8 bytes, which is 16 bytes here  (0x10)
   AudioFormat     (2 bytes) : Audio format (1: PCM integer, 3: IEEE 754 float)
   NbrChannels     (2 bytes) : Number of channels
   Frequency       (4 bytes) : Sample rate (in hertz)
   BytePerSec      (4 bytes) : Number of bytes to read per second (Frequency * BytePerBloc).
   BytePerBloc     (2 bytes) : Number of bytes per block (NbrChannels * BitsPerSample / 8).
   BitsPerSample   (2 bytes) : Number of bits per sample

[Chunk containing the sampled data]
   DataBlocID      (4 bytes) : Identifier « data »  (0x64, 0x61, 0x74, 0x61)
   DataSize        (4 bytes) : SampledData size
   SampledData
*/

// https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html
RiffHeader :: struct #packed {
	file_type_bloc_id: [4]u8, // (4 bytes) : Identifier « RIFF »  (0x52, 0x49, 0x46, 0x46)
	file_size:         i32, // (4 bytes) : Overall file size minus 8 bytes
	file_format_id:    [4]u8, // (4 bytes) : Format = « WAVE »  (0x57, 0x41, 0x56, 0x45)
}

PcmFormatHeader :: struct #packed {
	chunk_id:        [4]u8, // (4 bytes) : Identifier « fmt␣ »  (0x66, 0x6D, 0x74, 0x20)
	chunk_size:      i32, // (4 bytes) : Chunk size minus 8 bytes, which is 16 bytes here  (0x10) 
	audio_format:    i16, // (2 bytes) : Audio format (1: PCM integer, 3: IEEE 754 float)
	channels:        i16, // (2 bytes) : Number of channels
	frequency:       i32, // (4 bytes) : Sample rate (in hertz)
	byte_per_sec:    i32, // (4 bytes) : Number of bytes to read per second (Frequency * BytePerBloc).
	byte_per_bloc:   i16, // (2 bytes) : Number of bytes per block (NbrChannels * BitsPerSample / 8).
	bits_per_sample: i16, // (2 bytes) : Number of bits per sample
}

ExtFormatHeader :: struct #packed {
	chunk_id:              [4]u8, // (4 bytes) : Identifier « fmt␣ »  (0x66, 0x6D, 0x74, 0x20)
	chunk_size:            i32, // (4 bytes) : Chunk size minus 8 bytes, which is 16 bytes here  (0x10) 
	audio_format:          i16, // (2 bytes) : Audio format (1: PCM integer, 3: IEEE 754 float)
	channels:              i16, // (2 bytes) : Number of channels
	frequency:             i32, // (4 bytes) : Sample rate (in hertz)
	byte_per_sec:          i32, // (4 bytes) : Number of bytes to read per second (Frequency * BytePerBloc).
	byte_per_bloc:         i16, // (2 bytes) : Number of bytes per block (NbrChannels * BitsPerSample / 8).
	bits_per_sample:       i16, // (2 bytes) : Number of bits per sample
	ext_size:              i16,
	valid_bits_per_sample: i16, // 8 * M
	channel_mask:          i32, // speaker position mask
	sub_format:            [16]u8, // GUID
}

IeeeFormatHeader :: struct #packed {
	chunk_id:        [4]u8, // (4 bytes) : Identifier « fmt␣ »  (0x66, 0x6D, 0x74, 0x20)
	chunk_size:      i32, // (4 bytes) : Chunk size minus 8 bytes, which is 16 bytes here  (0x10) 
	audio_format:    i16, // (2 bytes) : Audio format (1: PCM integer, 3: IEEE 754 float)
	channels:        i16, // (2 bytes) : Number of channels
	frequency:       i32, // (4 bytes) : Sample rate (in hertz)
	byte_per_sec:    i32, // (4 bytes) : Number of bytes to read per second (Frequency * BytePerBloc).
	byte_per_bloc:   i16, // (2 bytes) : Number of bytes per block (NbrChannels * BitsPerSample / 8).
	bits_per_sample: i16, // (2 bytes) : Number of bits per sample
	ext_size:        i16, // 0
}


ChunkHeader :: struct #packed {
	chunk_id:   [4]u8, // (4 bytes) : Identifier « data »  (0x64, 0x61, 0x74, 0x61)
	chunk_size: i32, // (4 bytes) : SampledData size
}

FactHeader :: struct #packed {
	chunk_id:      [4]u8,
	chunk_size:    i32,
	sample_length: i32,
}

WAVE_FORMAT_PCM :: i16(1)
WAVE_FORMAT_IEEE_FLOAT :: i16(3)
WAVE_FORMAT_ALAW :: i16(6)
WAVE_FORMAT_MULAW :: i16(7)
//WAVE_FORMAT_EXTENSIBLE :: i16(0xFFFE)

WaveDataHeader :: struct #packed {
	chunk_id:   [4]u8, // (4 bytes) : Identifier « data »  (0x64, 0x61, 0x74, 0x61)
	chunk_size: i32, // (4 bytes) : SampledData size
}

WavContents :: struct {
	// config
	channels:    i16,
	frequency:   i32,
	// data
	samples_raw: []f32,
	samples:     ^f32,
	// metadata
	file_path:   string,
	sample_idx:  int,
	is_playing:  bool,
	loop:        bool,
	is_music:    bool,
}
AUDIO_FREQ := i32(44100)
AUDIO_CHANNELS := i16(2)

// NOTE: ----------------------------------------------

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

Audio :: enum {
	//music_ocean_beats,
	music_bounce,
	effect_phaser,
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
	audio:       map[Audio]^WavContents,
}
g: ^Globals

validate_audio :: proc() {
	for audio, index in Audio {
		_, ok := g.audio[audio]
		log.assertf(ok, "%s audio: validate: registry missing audio: %s", FAIL, audio)
	}

	freq: i32
	for key, value in g.audio {
		if freq == 0 {
			log.infof("frequency: %d", value.frequency)
			freq = value.frequency
		}

		log.assertf(
			freq == value.frequency,
			"%s audio: validate: freq mismatch: %d != %d: %s",
			FAIL,
			freq,
			value.frequency,
			value.file_path,
		)
	}

	channels: i16
	for key, value in g.audio {
		if channels == 0 {
			log.infof("# channels: %d", value.channels)
			channels = value.channels
		}

		log.assertf(
			channels == value.channels,
			"%s audio: validate: channel mismatch: %d != %d: %s",
			FAIL,
			channels,
			value.channels,
			value.file_path,
		)
	}

	log.assertf(sa.isvalid(), "%s sokol audio setup is not valid", FAIL)
}

load_wav :: proc(contents: ^WavContents) {
	file_data, ok := os.read_entire_file(contents.file_path)
	if !ok {
		log.fatal("could not read: ", contents.file_path)
		return
	}

	log.debugf("wav file: %s", contents.file_path)

	offset := 0

	riff: RiffHeader
	format: PcmFormatHeader
	ieee_format: IeeeFormatHeader
	fact: FactHeader
	data: WaveDataHeader

	intrinsics.mem_copy(&riff, &file_data[offset], size_of(RiffHeader))
	offset += size_of(RiffHeader)

	log.assert(
		strings.clone_from_bytes(riff.file_type_bloc_id[:]) == "RIFF", // RIFF header
		"Invalid .wav file, bytes 0-3 should spell 'RIFF'",
	)
	log.assert(
		strings.clone_from_bytes(riff.file_format_id[:]) == "WAVE",
		"Invalid .wav file, bytes 8-11 should spell 'WAVE'",
	)
	log.assert(
		offset < len(file_data),
		fmt.aprint("offset %d >= len(file_data) %d", offset, len(file_data)),
	)

	for offset < len(file_data) {
		// TODO: get this to read the file properly
		chunk: ChunkHeader
		intrinsics.mem_copy(&chunk, &file_data[offset], size_of(ChunkHeader))

		log.debugf(
			"%c%c%c%c header",
			cast(rune)chunk.chunk_id[0],
			cast(rune)chunk.chunk_id[1],
			cast(rune)chunk.chunk_id[2],
			cast(rune)chunk.chunk_id[3],
		)
		log.debugf("- chunk size: %d", chunk.chunk_size)

		switch chunk.chunk_id {
		case "fmt ":
			// Format section
			intrinsics.mem_copy(&format, &file_data[offset], size_of(PcmFormatHeader))

			log.debugf("- audio_format: %d", format.audio_format)
			log.debugf("- channels: %d", format.channels)
			log.debugf("- frequency: %d", format.frequency)
			log.debugf("- byte per sec: %d", format.byte_per_sec)
			log.debugf("- byte per bloc: %d", format.byte_per_bloc)
			log.debugf("- bits per sample: %d", ieee_format.bits_per_sample)

			switch format.audio_format {
			case WAVE_FORMAT_IEEE_FLOAT:
				log.debug("IEEE FLOAT format detected")
				intrinsics.mem_copy(&ieee_format, &file_data[offset], size_of(IeeeFormatHeader))

				log.assert(
					ieee_format.audio_format == WAVE_FORMAT_IEEE_FLOAT,
					"ieee format audio format != 3",
				)

				/*
				log.assertf(
					ieee_format.chunk_size == 18,
					"ieee format size %d != 18",
					ieee_format.chunk_size,
				)
				*/

				contents.frequency = ieee_format.frequency
				contents.channels = ieee_format.channels

				log.debugf("- ext size: %d", ieee_format.ext_size)

			case WAVE_FORMAT_PCM:
				log.debug("PCM format detected")
				log.assert(format.audio_format == WAVE_FORMAT_PCM, "pcm format audio format != 1")

				contents.frequency = format.frequency
				contents.channels = format.channels
			case:
				log.panicf("uknown format: %d", format.audio_format)
			}

			offset += size_of(ChunkHeader)
			offset += int(chunk.chunk_size)


		/*log.assert(
				format.frequency == AUDIO_FREQ,
				fmt.aprintf("sample_rate, got %d - expected %d", format.sample_rate, AUDIO_FREQ),
			)*/
		/*log.assert(
				format.channel_count == AUDIO_CHANNELS,
				fmt.aprintf(
					"channel_count, got %d - expected %d",
					format.channel_count,
					AUDIO_CHANNELS,
				),
			)*/
		/*log.assert(
				format.bits_per_sample == i16(32),
				fmt.aprintf("bits per sample, got %d - expected %d", format.bits_per_sample, 32),
			)*/

		case "fact":
			intrinsics.mem_copy(&fact, &file_data[offset], size_of(FactHeader))
			offset += size_of(ChunkHeader)
			offset += int(chunk.chunk_size)

		// TODO: should I do anything with this?
		// TODO: any calculations / extra fields on 'contents' ?

		case "data":
			intrinsics.mem_copy(&data, &file_data[offset], size_of(WaveDataHeader))
			offset += size_of(ChunkHeader)

			// Data section
			log.assertf(data.chunk_size != 0, "data size: %d", data.chunk_size)
			log.assertf(
				int(chunk.chunk_size) + offset <= len(file_data),
				"data size (%d) + offset (%d) goes beyond length of file (%d)",
				int(chunk.chunk_size),
				offset,
				len(file_data),
			)

			samples := data.chunk_size / i32((format.bits_per_sample / 8))
			log.debugf("- total samples: %d", samples)

			contents.samples_raw = make([]f32, samples)
			intrinsics.mem_copy(&contents.samples_raw[0], &file_data[offset], data.chunk_size)
			offset += int(chunk.chunk_size)
			if offset % 2 == 1 {
				offset += 1 // NOTE: account for pad-byte
			}

			contents.samples = &contents.samples_raw[0]

		case "bext":
			offset += size_of(ChunkHeader)
			offset += int(chunk.chunk_size)
		case "junk":
			offset += size_of(ChunkHeader)
			offset += int(chunk.chunk_size)
		case "JUNK":
			offset += size_of(ChunkHeader)
			offset += int(chunk.chunk_size)
		case:
			offset += size_of(ChunkHeader)
			offset += int(chunk.chunk_size)
		}
	}

	log.assert(contents.frequency != 0, "contents.freqency is 0")
	log.assert(contents.channels != 0, "contents.channels is 0")
	log.assert(len(contents.samples_raw) != 0, "contents.samples_raw length is 0")
}

effect_phaser := WavContents {
	file_path = "assets/audio/phaser.wav",
}
music_bounce := WavContents {
	file_path = "assets/audio/bounce.wav",
}

init :: proc "c" () {
	context = default_context

	g = new(Globals)

	g.camera = {
		position = {0, 0, 2},
		target   = {0, 0, 1},
	}

	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})
	log.assert(sg.isvalid(), "sokol graphics setup is not valid")

	g.audio[.effect_phaser] = &effect_phaser
	load_wav(g.audio[.effect_phaser])

	/*
	g.audio[.music_ocean_beats] = &WavContents{file_path = "assets/audio/ocean-beats.wav"}
	load_wav(g.audio[.music_ocean_beats])
	g.audio[.music_ocean_beats].loop = true
	g.audio[.music_ocean_beats].is_playing = true
	g.audio[.music_ocean_beats].is_music = true
	*/

	g.audio[.music_bounce] = &music_bounce
	load_wav(g.audio[.music_bounce])
	g.audio[.music_bounce].loop = true
	g.audio[.music_bounce].is_music = true
	g.audio[.music_bounce].is_playing = true


	sa.setup({logger = {func = slog.func}})
	log.debugf("%s setup audio", DONE)

	validate_audio()
	log.debugf("%s validate audio", DONE)

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

	update_physics(dt)
	update_camera(dt)
	update_grapple(dt)
	update_bullets(dt)
	update_audio(dt)

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
		{{0, 0, 5}, {0, 0, 0}, g.image},
		{{0, 1, 5}, {0, 0, 0}, g.image},
		{{0, 2, 5}, {0, 0, 0}, g.image},
		{{0, 3, 5}, {0, 0, 0}, g.image},
		{{0, 4, 5}, {0, 0, 0}, g.image},
		{{0, 5, 5}, {0, 0, 0}, g.image},
		{{0, 6, 5}, {0, 0, 0}, g.image},
		{{0, 7, 5}, {0, 0, 0}, g.image},
		{{0, 0, -5}, {0, 0, 0}, g.image},
		{{0, 1, -5}, {0, 0, 0}, g.image},
		{{0, 2, -5}, {0, 0, 0}, g.image},
		{{0, 3, -5}, {0, 0, 0}, g.image},
		{{0, 4, -5}, {0, 0, 0}, g.image},
		{{0, 5, -5}, {0, 0, 0}, g.image},
		{{0, 6, -5}, {0, 0, 0}, g.image},
		{{0, 7, -5}, {0, 0, 0}, g.image},
		{{5, 0, 0}, {0, 90, 0}, g.image},
		{{5, 1, 0}, {0, 90, 0}, g.image},
		{{5, 0, 0}, {0, 90, 0}, g.image},
		{{5, 1, 0}, {0, 90, 0}, g.image},
		{{5, 2, 0}, {0, 90, 0}, g.image},
		{{5, 3, 0}, {0, 90, 0}, g.image},
		{{5, 4, 0}, {0, 90, 0}, g.image},
		{{5, 5, 0}, {0, 90, 0}, g.image},
		{{5, 6, 0}, {0, 90, 0}, g.image},
		{{5, 7, 0}, {0, 90, 0}, g.image},
		{{-5, 0, 0}, {0, 90, 0}, g.image},
		{{-5, 1, 0}, {0, 90, 0}, g.image},
		{{-5, 2, 0}, {0, 90, 0}, g.image},
		{{-5, 3, 0}, {0, 90, 0}, g.image},
		{{-5, 4, 0}, {0, 90, 0}, g.image},
		{{-5, 5, 0}, {0, 90, 0}, g.image},
		{{-5, 6, 0}, {0, 90, 0}, g.image},
		{{-5, 7, 0}, {0, 90, 0}, g.image},
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

GRAVITY: f32 = -0.03
JUMP_VELOCITY: f32 = 0.3

GROUND_LEVEL: f32 = 0.0

in_air := false
velocity: f32 = 0.0
jump_start: f32 = 0.0
jump_time: f32 = 0.0

calculate_jump :: proc(dt: f32) {
	jump_time += dt
	t := jump_time - jump_start
	velocity = velocity + GRAVITY * t // TODO: change dt to seconds
	g.camera.position += Vec3{0, velocity, 0}
	log.debugf("dt: %f, velocity: %f", t, velocity)
}

update_physics :: proc(dt: f32) {
	if in_air && g.camera.position.y <= GROUND_LEVEL {
		in_air = false
		velocity = 0.0
		g.camera.position.y = GROUND_LEVEL
		return
	}

	if in_air {
		calculate_jump(dt)
	} else if key_down[.SPACE] {
		in_air = true
		velocity = JUMP_VELOCITY
		jump_start = 0.0
		jump_time = 0.0
		calculate_jump(dt)
	}

}

SHOOT_SPEED :: 0.1

MOVE_SPEED :: 3
LOOK_SENSITIVITY :: 0.3

update_camera :: proc(dt: f32) {
	move_input := Vec3{0, 0, 0}
	if key_down[.W] do move_input.y = 1
	else if key_down[.S] do move_input.y = -1
	if key_down[.A] do move_input.x = -1
	else if key_down[.D] do move_input.x = 1
	if key_down[.LEFT_CONTROL] do move_input.z = -1
	else if key_down[.LEFT_SHIFT] do move_input.z = 1

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
	up := (look_mat * Vec4{0, 1, 0, 1}).xyz

	move_dir := forward * move_input.y + right * move_input.x + up * move_input.z

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

update_audio :: proc(dt: f32) {
	log.debug("pushing audio...")

	num_frames := int(sa.expect())
	if num_frames > 0 {

		buf := make([]f32, num_frames)
		for frame in 0 ..< num_frames {
			track: for key, audio in g.audio {
				log.assert(audio.channels == 2, "audio is zero-state")
				if !audio.is_playing do continue

				log.assertf(
					audio.channels == 2,
					"audio channels %d != 2: %s",
					audio.channels,
					audio.file_path,
				)

				for channel in 0 ..< audio.channels {
					if audio.sample_idx >= len(audio.samples_raw) {
						audio.sample_idx = 0
						if !audio.loop {
							audio.is_playing = false
							continue track
						}
					}

					buf[frame] += audio.samples_raw[audio.sample_idx]
					audio.sample_idx += 1
				}
			}
		}
		sa.push(&buf[0], num_frames)
	}

	log.debugf("%s push audio", DONE)
}

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

GRAPPLE_DISTANCE: f32 = 15.0
GRAPPLE_SPEED: f32 = 0.2
grappling := false
grappling_dir: Vec3 = Vec3{0, 0, 0}
grapple_start: Vec3 = Vec3{0, 0, 0}

update_grapple :: proc(dt: f32) {
	if grappling {
		g.camera.position += grappling_dir * GRAPPLE_SPEED

		distance := math.abs(linalg.distance(g.camera.position, grapple_start))
		if distance >= GRAPPLE_DISTANCE do grappling = false
	} else if key_down[.E] {
		grappling = true
		grapple_start = g.camera.position
		grappling_dir = g.camera.target - g.camera.position
		g.camera.position += grappling_dir * GRAPPLE_SPEED

		// TODO: make function for this
		g.audio[.effect_phaser].is_playing = true
		g.audio[.effect_phaser].sample_idx = 0
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
	sa.shutdown()
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
