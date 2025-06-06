# enkiTS Odin bindings

> For [enkiTS](https://github.com/dougbinks/enkiTS) version `771a0876f7b1b26a9c9381f476b31b08798583cf`

EnkiTS is a C/C++ library implementing a Task Scheduler for parallel task execution. You can read more about it on its [github page](https://github.com/dougbinks/enkiTS).

I've made these bindings because I'm new to Odin and I was looking for "something like Unity Jobs", with dependencies and all.

## Usage

The `enki` folder contains the binding and the lib file, so you can just use that from your project. There's also a small `example`, but also check the original library's examples (the `_c.c` versions specifically).

## Building

The original enkiTS is in the `library` submodule. Use `build-lib-windows.bat` to build the lib file out of it. Currently, windows only, sorry :)
