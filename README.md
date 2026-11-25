# ffi-pack-shim — WebGPU from SWI-Prolog (via Rust's wgpu-native FFI)

A beginner GPU program written in SWI-Prolog that calls the C FFI of Rust's
[wgpu](https://github.com/gfx-rs/wgpu) (`wgpu-native`, prebuilt
`libwgpu_native.so` for Linux x86_64, release v29.0.1.1) through the
[`ffi` pack](https://github.com/JanWielemaker/ffi) (libffi-based, "dynamically
call C functions" — no C glue needed for the pointer-based API).

`wgpu_hello.pl` creates a WebGPU instance, requests an adapter + device,
runs a WGSL compute shader that doubles an array of `u32`, copies the result
to a staging buffer, maps it on the CPU and prints it:

```
input:  [1,2,3,4,5,6,7,8]
output: [2,4,6,8,10,12,14,16]
```

## Layout

```
├── wgpu_hello.pl    the Prolog program (c_import + main/0)
├── wgpu4pl.h/.c/.so tiny C shim: wgpu v29 passes the *CallbackInfo structs
│                    BY VALUE, which the ffi pack cannot marshal; the shim
│                    takes a plain C callback pointer instead
└── lib/             wgpu-native release (include/webgpu/*.h, lib/libwgpu_native.so)
```
Unpack the https://github.com/gfx-rs/wgpu-native/releases/download/v29.0.1.1/wgpu-linux-x86_64-release.zip to lib directory
## Run

```
./run.sh                          # uses swipl from PATH
./run.sh ~/swipl-devel/build/src/swipl   # or the 11.1.0 PGO build
```

`run.sh` sets `LD_LIBRARY_PATH=$PWD/lib/lib` (not strictly needed — the
library paths inside `wgpu_hello.pl` are absolute — but harmless) and runs:

```
swipl -g "use_module(wgpu_hello), wgpu_hello:main, halt."
```

The many `Unknown message: ctypes(...)` lines the ffi pack prints while
parsing the header are silenced by a `message_hook` at the top of
`wgpu_hello.pl`; a clean run prints only the program output.

Requires: swipl with the `ffi` pack (`pack_install(ffi)`), gcc (to rebuild
`wgpu4pl.so`), and a Vulkan ICD (here: Mesa Intel/lavapipe).

Rebuild the shim after changing wgpu4pl.c:

```
gcc -shared -fPIC -O2 -I lib/include/webgpu wgpu4pl.c -o wgpu4pl.so \
    -L lib/lib -l:libwgpu_native.so -Wl,-rpath,$PWD/lib/lib
```

## Project state (resume notes, 2026-11-25)

- `wgpu_hello.pl` works: `main/0` (8-element demo), `bench(N, K)`
  (compute-heavy kernel; last run: 392x GPU-vs-Prolog kernel speedup,
  results identical). Verified on system swipl 10.1.21 and
  `~/swipl-devel/build/src/swipl` (11.1.0 PGO). Paths are absolute
  (`/home/pasixxxx/wg/...`) — an attempt to make them relative via
  `c_define` macros did NOT work (macros not expanded); left as-is.
- The ffi-pack fork with the **struct-by-value patch** is parked at
  `/home/pasixxxx/ffi` (uncommitted changes on `master`, builds clean,
  pack regression tests pass). NOT PR'd. Next steps if resumed:
  add `test/test_structval.c/.pl`, test calling `wgpuInstanceRequestAdapter`
  directly (no `wgpu4pl` shim), then branch + commit + PR to
  JanWielemaker/ffi.
- Ideas queued: `matmul/1` (N x N matmul on GPU + Prolog reference +
  benchmark), portable paths, native Windows (wgpu_native.dll + mingw shim).

## Notes / gotchas found

- wgpu-native v29 API: `wgpuCreateInstance`, `wgpuInstanceRequestAdapter`
  etc. take a `WGPU*CallbackInfo` **struct by value** and return a
  `WGPUFuture` by value — both unsupported by the ffi pack; hence `wgpu4pl.c`.
- In `c_import` specs, struct names in type positions must be quoted atoms
  (`*struct('WGPUAdapterImpl')`); an unquoted capitalized name is a variable.
- Enum fields: store as raw `uint` at the field offset
  (`c_store(Ptr, Off, uint, Val)`); `[Ret]` as last spec element becomes an
  extra out-argument (or is omitted for `[void]`).
- `-struct(...)` out-params must be passed **unbound** (the pack allocates).
- Callback closures only support scalar/pointer args (a by-value struct arg
  is not marshalled); the shim's callback typedefs therefore use scalar
  signatures, which also satisfies the pack's signature matching.
