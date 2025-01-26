package example

import "base:runtime"
import "core:c"
import "core:log"
import "core:math"
import "core:math/noise"
import "core:mem"
import "../enki"
import rl "vendor:raylib"

// store context so we can use it "c" procs
default_context: runtime.Context

gen_noise_map :: proc(seed:i64, w, h: u32, scale: f32) -> []f32 {
	ts := enki.NewTaskScheduler()
	enki.InitTaskScheduler(ts)

	TaskData :: struct {
		result: []f32,
		width: u32,
		seed: i64,
		scale: f64,
	}

	task := enki.CreateTaskSet(ts, proc "c" (start, end, threadnum: u32, args: rawptr) {
		context = default_context
		log.debugf("Generating noise values for range %v-%v on thread %v", start, end, threadnum)

		task_data := transmute(^TaskData)args
		for i in start ..< end {
			y := i / task_data.width
			x := i % task_data.width
			noise_val := noise.noise_2d(task_data.seed, {f64(x) / task_data.scale, f64(y) / task_data.scale})
			task_data.result[i] = noise_val
		}
	})

	result := make([]f32, w * h)
	enki.SetSetSizeTaskSet(task, w * h)
	enki.SetMinRangeTaskSet(task, w)
	enki.SetArgsTaskSet(task, &TaskData{
		result = result,
		width = w,
		seed = seed,
		scale = f64(scale),
	})
	enki.AddTaskSet(ts, task)
	enki.WaitForTaskSet(ts, task)

	enki.DeleteTaskSet(ts, task)
	enki.DeleteTaskScheduler(ts)

	return result
}

load_noise_map_texture :: proc(w, h:int, noise_map: []f32) -> rl.Texture2D {
	noise_pixels := make([]rl.Color, w * h)
	for v,i in noise_map {
		h := math.unlerp(f32(-1), f32(1), v)
		c := u8(h * 255)
		noise_pixels[i] = {c,c,c,255}
	}
	noise_tex := rl.LoadTextureFromImage({
		data = raw_data(noise_pixels),
		width = i32(w),
		height = i32(h),
		mipmaps = 1,
		format = .UNCOMPRESSED_R8G8B8A8
	})
	delete(noise_pixels)
	return noise_tex
}

main :: proc() {
	context.logger = log.create_console_logger()
	default_context = context

	rl.InitWindow(800, 800, "Example")

	w, h :: 500, 500
	noise_map := gen_noise_map(50, u32(w), u32(h), 100)
	noise_tex := load_noise_map_texture(w, h, noise_map)
	delete(noise_map)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.DrawTexture(noise_tex, 0, 0, rl.WHITE)
		rl.EndDrawing()
	}
	rl.UnloadTexture(noise_tex)
	rl.CloseWindow()
}
