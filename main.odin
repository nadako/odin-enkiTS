package main

import "base:runtime"
import "core:c"
import "core:log"
import "core:math/noise"
import "core:mem"
import "enki"

default_context: runtime.Context

main :: proc() {
	context.logger = log.create_console_logger()
	default_context = context

	ts := enki.NewTaskScheduler()
	defer enki.DeleteTaskScheduler(ts)

	config := enki.GetTaskSchedulerConfig(ts)
	config.profilerCallbacks = {
		threadStart = proc "c" (n: u32) {
			context = default_context
			log.debug("Thread start", n)
		},
		threadStop = proc "c" (n: u32) {
			context = default_context
			log.debug("Thread stop", n)
		},
	}
	enki.InitTaskSchedulerWithConfig(ts, config)

	TaskData :: struct {
		size:     [2]u32,
		noisemap: []f32,
	}

	task := enki.CreateTaskSet(ts, proc "c" (start, end, threadnum: u32, args: rawptr) {
		context = default_context
		task_data := transmute(^TaskData)args
		for i in start ..< end {
			y := i / task_data.size.x
			x := i % task_data.size.x
			noise_val := noise.noise_2d(1, {f64(x), f64(y)})
			task_data.noisemap[i] = noise_val
		}
	})
	defer enki.DeleteTaskSet(ts, task)

	w, h: u32 = 1000, 1000
	noisemap := make([]f32, w * h)
	enki.SetSetSizeTaskSet(task, w * h)
	enki.SetMinRangeTaskSet(task, w)
	enki.SetArgsTaskSet(task, &TaskData{size = {w, h}, noisemap = noisemap})
	enki.AddTaskSet(ts, task)

	enki.WaitForTaskSet(ts, task)
}
