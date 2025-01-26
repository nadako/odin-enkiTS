package enki

// TODO: review types, use b32 or something for boolean ints
// TODO: review doc, adjust naming
// TODO: port tests, run on CI, all that stuff

import "core:c"

// TODO: other platforms, add build scripts too
foreign import enki "enki.lib"

NO_THREAD_NUM: u32 : 0xFFFFFFFF

TaskScheduler :: struct {}

TaskSet :: struct {}

PinnedTask :: struct {}

Completable :: struct {}

Dependency :: struct {}

CompletionAction :: struct {}

TaskExecuteRange :: proc "c" (start, end, threadnum: u32, args: rawptr)
PinnedTaskExecute :: proc "c" (args: rawptr)
CompletionFunction :: proc "c" (args: rawptr, threadnum: u32)

ParamsPinnedTask :: struct {
	args:     rawptr,
	priority: c.int,
}

ParamsTaskSet :: struct {
	args:     rawptr,
	setSize:  u32,
	minRange: u32,
	priority: c.int,
}

ParamsCompletionAction :: struct {
	argsPreComplete:  rawptr,
	argsPostComplete: rawptr,
	dependency:       ^Completable, // task which when complete triggers completion function
}

AllocFunc :: proc "c" (align: c.size_t, size: c.size_t, userData: rawptr, file: cstring, line: c.int) -> rawptr
FreeFunc :: proc "c" (ptr: rawptr, size: c.size_t, userData: rawptr, file: cstring, line: c.int)

CustomAllocator :: struct {
	alloc:    AllocFunc,
	free:     FreeFunc,
	userData: rawptr,
}

// TaskScheduler implements several callbacks intended for profilers
ProfilerCallbackFunc :: proc "c" (threadnum: u32)

ProfilerCallbacks :: struct {
	threadStart:                     ProfilerCallbackFunc,
	threadStop:                      ProfilerCallbackFunc,
	waitForNewTaskSuspendStart:      ProfilerCallbackFunc, // thread suspended waiting for new tasks
	waitForNewTaskSuspendStop:       ProfilerCallbackFunc, // thread unsuspended
	waitForTaskCompleteStart:        ProfilerCallbackFunc, // thread waiting for task completion
	waitForTaskCompleteStop:         ProfilerCallbackFunc, // thread stopped waiting
	waitForTaskCompleteSuspendStart: ProfilerCallbackFunc, // thread suspended waiting task completion
	waitForTaskCompleteSuspendStop:  ProfilerCallbackFunc, // thread unsuspended
}

// TaskSchedulerConfig - configuration struct for advanced Initialize
// Always use GetTaskSchedulerConfig() to get defaults prior to altering and
// initializing with InitTaskSchedulerWithConfig().
TaskSchedulerConfig :: struct {
	// numTaskThreadsToCreate - Number of tasking threads the task scheduler will create. Must be > 0.
	// Defaults to GetNumHardwareThreads()-1 threads as thread which calls initialize is thread 0.
	numTaskThreadsToCreate: u32,

	// numExternalTaskThreads - Advanced use. Number of external threads which need to use TaskScheduler API.
	// See TaskScheduler::RegisterExternalTaskThread() for usage.
	// Defaults to 0. The thread used to initialize the TaskScheduler can also use the TaskScheduler API.
	// Thus there are (numTaskThreadsToCreate + numExternalTaskThreads + 1) able to use the API, with this
	// defaulting to the number of hardware threads available to the system.
	numExternalTaskThreads: u32,
	profilerCallbacks:      ProfilerCallbacks,
	customAllocator:        CustomAllocator,
}

@(default_calling_convention = "c", link_prefix = "enki")
foreign enki {
	DefaultAllocFunc: AllocFunc
	DefaultFreeFunc: FreeFunc

	/* ----------------------------  Task Scheduler  ---------------------------- */
	// Create a new task scheduler
	NewTaskScheduler :: proc() -> ^TaskScheduler ---

	// Create a new task scheduler using a custom allocator
	// This will use the custom allocator to allocate the task scheduler struct
	// and additionally will set the custom allocator in TaskSchedulerConfig of the task scheduler
	NewTaskSchedulerWithCustomAllocator :: proc(customAllocator: CustomAllocator) -> ^TaskScheduler ---
	// TODO: why this doesn't work?

	// Get config. Can be called before InitTaskSchedulerWithConfig to get the defaults
	GetTaskSchedulerConfig :: proc(ts: ^TaskScheduler) -> TaskSchedulerConfig ---

	// for !GetIsShutdownRequested() {} can be used in tasks which loop, to check if enkiTS has been requested to shutdown.
	// If GetIsShutdownRequested() returns true should then exit. Not required for finite tasks
	// Safe to use with WaitforAllAndShutdown() where this will be set
	// Not safe to use with WaitforAll(), use GetIsWaitforAllCalled() instead.
	GetIsShutdownRequested :: proc(ts: ^TaskScheduler) -> c.int ---

	// while( !enkiGetIsWaitforAllCalled() ) {} can be used in tasks which loop, to check if enkiWaitforAll() has been called.
	// If enkiGetIsWaitforAllCalled() returns false should then exit. Not required for finite tasks
	// This is intended to be used with code which calls enkiWaitforAll().
	// This is also set when the task manager is shutting down, so no need to have an additional check for enkiGetIsShutdownRequested()
	GetIsWaitforAllCalled :: proc(ts: ^TaskScheduler) -> c.int ---

	// Initialize task scheduler - will create GetNumHardwareThreads()-1 threads, which is
	// sufficient to fill the system when including the main thread.
	// Initialize can be called multiple times - it will wait for completion
	// before re-initializing.
	InitTaskScheduler :: proc(ts: ^TaskScheduler) ---

	// Initialize a task scheduler with numThreads_ (must be > 0)
	// will create numThreads_-1 threads, as thread 0 is
	// the thread on which the initialize was called.
	InitTaskSchedulerNumThreads :: proc(ts: ^TaskScheduler, numThreads: u32) ---

	// Initialize a task scheduler with config, see TaskSchedulerConfig for details
	InitTaskSchedulerWithConfig :: proc(ts: ^TaskScheduler, config: TaskSchedulerConfig) ---

	// Waits for all task sets to complete and shutdown threads - not guaranteed to work unless we know we
	// are in a situation where tasks aren't being continuously added.
	// ts can then be reused.
	// This function can be safely called even if Init* has not been called.
	WaitforAllAndShutdown :: proc(ts: ^TaskScheduler) ---

	// Delete a task scheduler.
	DeleteTaskScheduler :: proc(ts: ^TaskScheduler) ---

	// Waits for all task sets to complete - not guaranteed to work unless we know we
	// are in a situation where tasks aren't being continuously added.
	WaitForAll :: proc(ts: ^TaskScheduler) ---

	// Returns the number of threads created for running tasks + number of external threads
	// plus 1 to account for the thread used to initialize the task scheduler.
	// Equivalent to config values: numTaskThreadsToCreate + numExternalTaskThreads + 1.
	// It is guaranteed that enkiGetThreadNum() < enkiGetNumTaskThreads()
	GetNumTaskThreads :: proc(ts: ^TaskScheduler) -> u32 ---

	// Returns the current task threadNum.
	// Will return 0 for thread which initialized the task scheduler,
	// and ENKI_NO_THREAD_NUM for all other non-enkiTS threads which have not been registered ( see enkiRegisterExternalTaskThread() ),
	// and < enkiGetNumTaskThreads() for all registered and internal enkiTS threads.
	// It is guaranteed that enkiGetThreadNum() < enkiGetNumTaskThreads() unless it is ENKI_NO_THREAD_NUM
	GetThreadNum :: proc(ts: ^TaskScheduler) -> u32 ---

	// Call on a thread to register the thread to use the TaskScheduling API.
	// This is implicitly done for the thread which initializes the TaskScheduler
	// Intended for developers who have threads who need to call the TaskScheduler API
	// Returns true if successful, false if not.
	// Can only have numExternalTaskThreads registered at any one time, which must be set
	// at initialization time.
	RegisterExternalTaskThread :: proc(ts: ^TaskScheduler) -> c.int ---

	// As enkiRegisterExternalTaskThread() but explicitly requests a given thread number.
	// threadNumToRegister_ must be  >= GetNumFirstExternalTaskThread()
	// and < ( GetNumFirstExternalTaskThread() + numExternalTaskThreads )
	RegisterExternalTaskThreadNum :: proc(ts: ^TaskScheduler, threadNumToRegister: u32) -> c.int ---

	// Call on a thread on which RegisterExternalTaskThread has been called to deregister that thread.
	DeRegisterExternalTaskThread :: proc(ts: ^TaskScheduler) ---

	// Get the number of registered external task threads.
	GetNumRegisteredExternalTaskThreads :: proc(ts: ^TaskScheduler) -> u32 ---

	// Get the thread number of the first external task thread. This thread
	// is not guaranteed to be registered, but threads are registered in order
	// from GetNumFirstExternalTaskThread() up to ( GetNumFirstExternalTaskThread() + numExternalTaskThreads )
	// Note that if numExternalTaskThreads == 0 a for loop using this will be valid:
	// for( uint32_t externalThreadNum = GetNumFirstExternalTaskThread();
	//      externalThreadNum < ( GetNumFirstExternalTaskThread() + numExternalTaskThreads
	//      ++externalThreadNum ) { // do something with externalThreadNum }
	GetNumFirstExternalTaskThread :: proc() -> u32 ---

	/* ----------------------------     TaskSets    ---------------------------- */
	// Create a task set.
	CreateTaskSet :: proc(ts: ^TaskScheduler, taskFunc: TaskExecuteRange) -> ^TaskSet ---

	// Delete a task set.
	DeleteTaskSet :: proc(ts: ^TaskScheduler, taskSet: ^TaskSet) ---

	// Get task parameters via ParamsTaskSet
	GetParamsTaskSet :: proc(taskSet: ^TaskSet) -> ParamsTaskSet ---

	// Set task parameters via ParamsTaskSet
	SetParamsTaskSet :: proc(taskSet: ^TaskSet, params: ParamsTaskSet) ---

	// Set task priority ( 0 to ENKITS_TASK_PRIORITIES_NUM-1, where 0 is highest)
	SetPriorityTaskSet :: proc(taskSet: ^TaskSet, priority: c.int) ---

	// Set TaskSet args
	SetArgsTaskSet :: proc(taskSet: ^TaskSet, args: rawptr) ---

	// Set TaskSet set setSize
	SetSetSizeTaskSet :: proc(taskSet: ^TaskSet, setSize: u32) ---

	// Set TaskSet set min range
	SetMinRangeTaskSet :: proc(taskSet: ^TaskSet, minRange: u32) ---

	// Schedule the task, use parameters set with Set*TaskSet
	AddTaskSet :: proc(ts: ^TaskScheduler, taskSet: ^TaskSet) ---

	// Schedule the task
	// overwrites args previously set with enkiSetArgsTaskSet
	// overwrites setSize previously set with enkiSetSetSizeTaskSet
	AddTaskSetArgs :: proc(ts: ^TaskScheduler, taskSet: ^TaskSet, args: rawptr, setSize: u32) ---

	// Schedule the task with a minimum range.
	// This should be set to a value which results in computation effort of at least 10k
	// clock cycles to minimize task scheduler overhead.
	// NOTE: The last partition will be smaller than m_MinRange if m_SetSize is not a multiple
	// of m_MinRange.
	// Also known as grain size in literature.
	AddTaskSetMinRange :: proc(ts: ^TaskScheduler, taskSet: ^TaskSet, args: rawptr, setSize: u32, minRange: u32) ---

	// Check if TaskSet is complete. Doesn't wait. Returns 1 if complete, 0 if not.
	IsTaskSetComplete :: proc(ts: ^TaskScheduler, taskSet: ^TaskSet) -> c.int ---

	// Wait for a given task.
	// should only be called from thread which created the task scheduler, or within a task
	// if called with 0 it will try to run tasks, and return if none available.
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForTaskSet :: proc(ts: ^TaskScheduler, taskSet: ^TaskSet) ---

	// enkiWaitForTaskSetPriority as enkiWaitForTaskSet but only runs other tasks with priority <= maxPriority_
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForTaskSetPriority :: proc(ts: ^TaskScheduler, taskSet: ^TaskSet, maxPriority: c.int) ---

	/* ----------------------------   PinnedTasks   ---------------------------- */
	// Create a pinned task.
	CreatePinnedTask :: proc(ts: ^TaskScheduler, taskFunc: PinnedTaskExecute, threadNum: u32) -> ^PinnedTask ---

	// Delete a pinned task.
	DeletePinnedTask :: proc(ts: ^TaskScheduler, pinnedTask: ^PinnedTask) ---

	// Get task parameters via enkiParamsTaskSet
	GetParamsPinnedTask :: proc(task: ^PinnedTask) -> ParamsPinnedTask ---

	// Set task parameters via enkiParamsTaskSet
	SetParamsPinnedTask :: proc(task: ^PinnedTask, params: ParamsPinnedTask) ---

	// Set PinnedTask ( 0 to ENKITS_TASK_PRIORITIES_NUM-1, where 0 is highest)
	SetPriorityPinnedTask :: proc(task: ^PinnedTask, priority: c.int) ---

	// Set PinnedTask args
	SetArgsPinnedTask :: proc(task: ^PinnedTask, args: rawptr) ---

	// Schedule a pinned task
	// Pinned tasks can be added from any thread
	AddPinnedTask :: proc(ts: ^TaskScheduler, task: ^PinnedTask) ---

	// Schedule a pinned task
	// Pinned tasks can be added from any thread
	// overwrites args previously set with enkiSetArgsPinnedTask
	AddPinnedTaskArgs :: proc(ts: ^TaskScheduler, task: ^PinnedTask, args: rawptr) ---

	// This function will run any enkiPinnedTask* for current thread, but not run other
	// Main thread should call this or use a wait to ensure its tasks are run.
	RunPinnedTasks :: proc(ts: ^TaskScheduler) ---

	// Check if enkiPinnedTask is complete. Doesn't wait. Returns 1 if complete, 0 if not.
	IsPinnedTaskComplete :: proc(ts: ^TaskScheduler, task: ^PinnedTask) -> c.int ---

	// Wait for a given pinned task.
	// should only be called from thread which created the task scheduler, or within a task
	// if called with 0 it will try to run tasks, and return if none available.
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForPinnedTask :: proc(ts: ^TaskScheduler, task: ^PinnedTask) ---

	// enkiWaitForPinnedTaskPriority as enkiWaitForPinnedTask but only runs other tasks with priority <= maxPriority_
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForPinnedTaskPriority :: proc(ts: ^TaskScheduler, task: ^PinnedTask, maxPriority: c.int) ---

	// Waits for the current thread to receive a PinnedTask
	// Will not run any tasks - use with RunPinnedTasks()
	// Can be used with both ExternalTaskThreads or with an enkiTS tasking thread to create
	// a thread which only runs pinned tasks. If enkiTS threads are used can create
	// extra enkiTS task threads to handle non blocking computation via normal tasks.
	WaitForNewPinnedTasks :: proc(ts: ^TaskScheduler) ---

	/* ----------------------------  Completables  ---------------------------- */
	// Get a pointer to an Completable from an enkiTaskSet.
	// Do not call DeleteCompletable on the returned pointer.
	GetCompletableFromTaskSet :: proc(taskSet: ^TaskSet) -> ^Completable ---

	// Get a pointer to an Completable from an PinnedTask.
	// Do not call DeleteCompletable on the returned pointer.
	GetCompletableFromPinnedTask :: proc(pinnedTask: ^PinnedTask) -> ^Completable ---

	// Get a pointer to an Completable from an PinnedTask.
	// Do not call DeleteCompletable on the returned pointer.
	GetCompletableFromCompletionAction :: proc(completionAction: ^CompletionAction) -> ^Completable ---

	// Create an Completable
	// Can be used with dependencies to wait for their completion.
	// Delete with DeleteCompletable
	CreateCompletable :: proc(ts: ^TaskScheduler) -> ^Completable ---

	// Delete an Completable created with enkiCreateCompletable
	DeleteCompletable :: proc(ts: ^TaskScheduler, completable: ^Completable) ---

	// Wait for a given completable.
	// should only be called from thread which created the task scheduler, or within a task
	// if called with 0 it will try to run tasks, and return if none available.
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForCompletable :: proc(ts: ^TaskScheduler, task: ^Completable) ---

	// enkiWaitForCompletablePriority as enkiWaitForCompletable but only runs other tasks with priority <= maxPriority_
	// Only wait for child tasks of the current task otherwise a deadlock could occur.
	WaitForCompletablePriority :: proc(ts: ^TaskScheduler, task: ^Completable, maxPriority: c.int) ---


	/* ----------------------------   Dependencies  ---------------------------- */
	// Create an Dependency, used to set dependencies between tasks
	// Call DeleteDependency to delete.
	CreateDependency :: proc(ts: ^TaskScheduler) -> ^Dependency ---

	// Delete an enkiDependency created with enkiCreateDependency.
	DeleteDependency :: proc(ts: ^TaskScheduler, dependency: ^Dependency) ---

	// Set a dependency between dependencyTask and taskToRunOnCompletion
	// such that when all dependencies of taskToRunOnCompletion are completed it will run.
	SetDependency :: proc(dependency: ^Dependency, dependencyTask: ^Completable, taskToRunOnCompletion: ^Completable) ---


	/* -------------------------- Completion Actions --------------------------- */
	// Create a CompletionAction.
	// completionFunctionPreComplete_ - function called BEFORE the complete action task is 'complete', which means this is prior to dependent tasks being run.
	//                                  this function can thus alter any task arguments of the dependencies.
	// completionFunctionPostComplete_ - function called AFTER the complete action task is 'complete'. Dependent tasks may have already been started.
	//                                  This function can delete the completion action if needed as it will no longer be accessed by other functions.
	// It is safe to set either of these to NULL if you do not require that function
	CreateCompletionAction :: proc(ts: ^TaskScheduler, completionFunctionPreComplete: CompletionFunction, completionFunctionPostComplete: CompletionFunction) -> ^CompletionAction ---

	// Delete a CompletionAction.
	DeleteCompletionAction :: proc(ts: ^TaskScheduler, completionAction: ^CompletionAction) ---

	// Get task parameters via enkiParamsTaskSet
	GetParamsCompletionAction :: proc(completionAction: ^CompletionAction) -> ParamsCompletionAction ---

	// Set task parameters via enkiParamsTaskSet
	SetParamsCompletionAction :: proc(completionAction: ^CompletionAction, params: ParamsCompletionAction) ---
}
