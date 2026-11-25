:- module(wgpu_hello,
          [ main/0,
            bench/2,
            on_adapter/4,
            on_device/4,
            on_mapped/3
          ]).

/** <module> wgpu_hello -- beginner GPU program via Rust's wgpu-native + SWI-Prolog ffi pack

Run with:  swipl -g "use_module(wgpu_hello), main, halt."

Creates a WebGPU instance, requests an adapter + device, runs a WGSL compute
shader that doubles an array of u32, copies the result to a staging buffer,
maps it on the CPU and prints the result.
*/

:- use_module(library(ffi)).

% Silence harmless parser noise from the ffi pack at c_import time
% (const-qualifier simplification notices and our intentional *void
% pointer-parameter fallbacks).
:- multifile user:message_hook/3.
user:message_hook(ctypes(_), _, _) :- !.
user:message_hook(ffi(F), _, _) :- !,
    functor(F, Name, _),
    atom(Name),
    sub_atom(Name, 0, _, _, 'incompatible').

:- c_import('#include "wgpu.h"
             #include "wgpu4pl.h"',
            [ '-I/home/pasixxxx/wg/lib/include/webgpu',
              '-I/home/pasixxxx/wg',
              '/home/pasixxxx/wg/wgpu4pl.so',
              '/home/pasixxxx/wg/lib/lib/libwgpu_native.so'
            ],
            [ % --- shim wrappers (callbackInfo structs are passed by value in C) ---
              pl_wgpu_request_adapter(*struct('WGPUInstanceImpl'),
                                      +struct('WGPURequestAdapterOptions'),
                                      on_adapter(int, *struct('WGPUAdapterImpl'), *void, *void),
                                      *void, *void, -struct('WGPUFuture'), [void]),
              pl_wgpu_request_device(*struct('WGPUAdapterImpl'),
                                     +struct('WGPUDeviceDescriptor'),
                                     on_device(int, *struct('WGPUDeviceImpl'), *void, *void),
                                     *void, *void, -struct('WGPUFuture'), [void]),
              pl_wgpu_buffer_map_async(*struct('WGPUBufferImpl'), int, int, int,
                                       on_mapped(int, *void, *void),
                                       *void, *void, -struct('WGPUFuture'), [void]),
              % --- direct wgpu-native functions (all pointer-based) ---
              wgpuCreateInstance(+struct('WGPUInstanceDescriptor'), [*struct('WGPUInstanceImpl')]),
              wgpuInstanceRelease(*struct('WGPUInstanceImpl'), [void]),
              wgpuInstanceProcessEvents(*struct('WGPUInstanceImpl'), [void]),
              wgpuAdapterGetInfo(*struct('WGPUAdapterImpl'), -struct('WGPUAdapterInfo'), [int]),
              wgpuAdapterRelease(*struct('WGPUAdapterImpl'), [void]),
              wgpuDevicePoll(*struct('WGPUDeviceImpl'), int, *void, [int]),
              wgpuDeviceRelease(*struct('WGPUDeviceImpl'), [void]),
              wgpuDeviceCreateBuffer(*struct('WGPUDeviceImpl'), +struct('WGPUBufferDescriptor'),
                                     [*struct('WGPUBufferImpl')]),
              wgpuDeviceCreateShaderModule(*struct('WGPUDeviceImpl'), +struct('WGPUShaderModuleDescriptor'),
                                           [*struct('WGPUShaderModuleImpl')]),
              wgpuDeviceCreateComputePipeline(*struct('WGPUDeviceImpl'), +struct('WGPUComputePipelineDescriptor'),
                                              [*struct('WGPUComputePipelineImpl')]),
              wgpuComputePipelineGetBindGroupLayout(*struct('WGPUComputePipelineImpl'), int,
                                                    [*struct('WGPUBindGroupLayoutImpl')]),
              wgpuDeviceCreateBindGroup(*struct('WGPUDeviceImpl'), +struct('WGPUBindGroupDescriptor'),
                                        [*struct('WGPUBindGroupImpl')]),
              wgpuDeviceCreateCommandEncoder(*struct('WGPUDeviceImpl'), +struct('WGPUCommandEncoderDescriptor'),
                                             [*struct('WGPUCommandEncoderImpl')]),
              wgpuCommandEncoderBeginComputePass(*struct('WGPUCommandEncoderImpl'), +struct('WGPUComputePassDescriptor'),
                                                 [*struct('WGPUComputePassEncoderImpl')]),
              wgpuComputePassEncoderSetPipeline(*struct('WGPUComputePassEncoderImpl'),
                                                *struct('WGPUComputePipelineImpl'), [void]),
              wgpuComputePassEncoderSetBindGroup(*struct('WGPUComputePassEncoderImpl'), int,
                                                 *struct('WGPUBindGroupImpl'), int, *void, [void]),
              wgpuComputePassEncoderDispatchWorkgroups(*struct('WGPUComputePassEncoderImpl'), int, int, int, [void]),
              wgpuComputePassEncoderEnd(*struct('WGPUComputePassEncoderImpl'), [void]),
              wgpuCommandEncoderCopyBufferToBuffer(*struct('WGPUCommandEncoderImpl'),
                                                   *struct('WGPUBufferImpl'), int,
                                                   *struct('WGPUBufferImpl'), int, int, [void]),
              wgpuCommandEncoderFinish(*struct('WGPUCommandEncoderImpl'), +struct('WGPUCommandBufferDescriptor'),
                                       [*struct('WGPUCommandBufferImpl')]),
              wgpuDeviceGetQueue(*struct('WGPUDeviceImpl'), [*struct('WGPUQueueImpl')]),
              wgpuQueueWriteBuffer(*struct('WGPUQueueImpl'), *struct('WGPUBufferImpl'), int, *void, int, [void]),
              wgpuQueueSubmit(*struct('WGPUQueueImpl'), int, *void, [void]),
              wgpuBufferGetMappedRange(*struct('WGPUBufferImpl'), int, int, [*void]),
              wgpuBufferUnmap(*struct('WGPUBufferImpl'), [void]),
              wgpuBufferRelease(*struct('WGPUBufferImpl'), [void])
            ]).

% ------------------------------------------------------------------
% Callbacks (invoked from C via libffi closures; scalar args only)
% ------------------------------------------------------------------

:- dynamic adapter_result/2.
:- dynamic device_result/2.
:- dynamic map_result/1.

on_adapter(Status, Adapter, _UD1, _UD2) :-
    assertz(adapter_result(Status, Adapter)).

on_device(Status, Device, _UD1, _UD2) :-
    assertz(device_result(Status, Device)).

on_mapped(Status, _UD1, _UD2) :-
    assertz(map_result(Status)).

% ------------------------------------------------------------------
% Small struct helpers (offset-based; enums stored as raw uint)
% ------------------------------------------------------------------

field(Struct, Field, Off, Ty) :-
    c_current_struct_field(Struct, Field, Off, Ty).

set(Ptr, Struct, Field, Value) :-
    field(Struct, Field, Off, Ty0),
    strip_module(Ty0, _, Ty),
    (   Ty = enum(_)
    ->  c_store(Ptr, Off, uint, Value)
    ;   c_store(Ptr[Field], Value)
    ).

get(Ptr, Struct, Field, Value) :-
    field(Struct, Field, Off, Ty0),
    strip_module(Ty0, _, Ty),
    (   Ty = enum(_)
    ->  c_load(Ptr, Off, uint, Value)
    ;   c_load(Ptr[Field], Value)
    ).

% cumulative byte offset of a (possibly nested) field path
path_off(Struct, [F], Off) :-
    !,
    field(Struct, F, Off, _).
path_off(Struct, [F|Rest], Off) :-
    field(Struct, F, Off0, Ty0),
    strip_module(Ty0, _, T),
    (   T = struct(S2)
    ;   T = struct(S2, _)
    ),
    path_off(S2, Rest, Off1),
    Off is Off0 + Off1.

set_raw(Ptr, Struct, Path, Type, Value) :-
    path_off(Struct, Path, Off),
    c_store(Ptr, Off, Type, Value).

get_raw(Ptr, Struct, Path, Type, Value) :-
    path_off(Struct, Path, Off),
    c_load(Ptr, Off, Type, Value).

set_enum(Ptr, Struct, Path, Value) :-
    set_raw(Ptr, Struct, Path, uint, Value).

set_str_at(Ptr, Struct, Path, Text) :-
    c_alloc_string(S, Text, utf8),
    c_address(S, SAddr),
    atom_length(Text, Len),
    append(Path, [data], PD), append(Path, [length], PL),
    set_raw(Ptr, Struct, PD, ulong, SAddr),
    set_raw(Ptr, Struct, PL, size_t, Len).

get_str_at(Ptr, Struct, Path, Text) :-
    append(Path, [data], PD), append(Path, [length], PL),
    get_raw(Ptr, Struct, PD, pointer(char), S),
    get_raw(Ptr, Struct, PL, size_t, Len),
    c_load_string(S, Len, Text, string, utf8).

% ------------------------------------------------------------------
% The beginner GPU program
% ------------------------------------------------------------------

wgsl_code(WGSL) :-
    WGSL = "@group(0) @binding(0) var<storage, read_write> data: array<u32>;\n@compute @workgroup_size(64)\nfn main(@builtin(global_invocation_id) id: vec3<u32>) {\n  data[id.x] = data[id.x] * 2u;\n}".

main :-
    % clear results of any previous run in this process (handles from a
    % previous run have been released; reusing them would be use-after-free)
    retractall(adapter_result(_, _)),
    retractall(device_result(_, _)),
    retractall(map_result(_)),
    Input = [1, 2, 3, 4, 5, 6, 7, 8],
    length(Input, N),
    Bytes is N * 4,

    format('== WebGPU hello from SWI-Prolog ==~n'),
    wgpuCreateInstance(null, Instance),
    format('instance: ~p~n', [Instance]),

    % -- adapter --
    c_alloc(AdapterOpts, struct('WGPURequestAdapterOptions')),
    pl_wgpu_request_adapter(Instance, AdapterOpts, null, null, _FutA),
    wait_instance(Instance, adapter_result(_, _), 20000),
    adapter_result(AStatus, Adapter),
    format('adapter status=~w~n', [AStatus]),
    wgpuAdapterGetInfo(Adapter, Info, _InfoRC),   % Info is allocated by the call
    get_str_at(Info, 'WGPUAdapterInfo', [vendor], Vendor),
    get_str_at(Info, 'WGPUAdapterInfo', [device], DeviceName),
    get_str_at(Info, 'WGPUAdapterInfo', [description], Desc),
    get(Info, 'WGPUAdapterInfo', backendType, Backend),
    format('GPU: ~w ~w (backend ~w) ~w~n', [Vendor, DeviceName, Backend, Desc]),

    % -- device --
    pl_wgpu_request_device(Adapter, null, null, null, _FutD),
    wait_instance(Instance, device_result(_, _), 20000),
    device_result(DStatus, Device),
    format('device status=~w~n', [DStatus]),

    % -- buffers: storage (GPU compute target) + staging (CPU readback) --
    c_alloc(StorageDesc, struct('WGPUBufferDescriptor')),
    set(StorageDesc, 'WGPUBufferDescriptor', usage, 140),   % Storage | CopyDst | CopySrc
    set(StorageDesc, 'WGPUBufferDescriptor', size, Bytes),
    wgpuDeviceCreateBuffer(Device, StorageDesc, StorageBuf),
    c_alloc(StagingDesc, struct('WGPUBufferDescriptor')),
    set(StagingDesc, 'WGPUBufferDescriptor', usage, 9),   % MapRead | CopyDst
    set(StagingDesc, 'WGPUBufferDescriptor', size, Bytes),
    wgpuDeviceCreateBuffer(Device, StagingDesc, StagingBuf),
    format('buffers: storage=~p staging=~p (~w bytes)~n', [StorageBuf, StagingBuf, Bytes]),

    % -- upload input data --
    wgpuDeviceGetQueue(Device, Queue),
    c_alloc(Data, uint[N]),
    fill_data(Data, 0, Input),
    wgpuQueueWriteBuffer(Queue, StorageBuf, 0, Data, Bytes),
    format('input:  ~w~n', [Input]),

    % -- shader module (WGSL via chained struct, 32-byte layout laid out manually) --
    wgsl_code(WGSL),
    c_alloc(WGSLDesc, uchar[32]),
    c_store(WGSLDesc, 8, uint, 2),                     % chain.sType = WGPUSType_ShaderSourceWGSL
    c_alloc_string(WGSLPtr, WGSL, utf8),
    c_address(WGSLPtr, WGSLAddr),
    atom_length(WGSL, WGSLLen),
    c_store(WGSLDesc, 16, ulong, WGSLAddr),            % code.data
    c_store(WGSLDesc, 24, size_t, WGSLLen),            % code.length
    c_alloc(ShaderDesc, struct('WGPUShaderModuleDescriptor')),
    c_store(ShaderDesc[nextInChain], WGSLDesc),
    wgpuDeviceCreateShaderModule(Device, ShaderDesc, ShaderModule),
    format('shader module: ~p~n', [ShaderModule]),

    % -- compute pipeline (auto layout) --
    c_alloc(CPDesc, struct('WGPUComputePipelineDescriptor')),
    c_store(CPDesc[compute][module], ShaderModule),
    set_str_at(CPDesc, 'WGPUComputePipelineDescriptor', [compute, entryPoint], "main"),
    wgpuDeviceCreateComputePipeline(Device, CPDesc, Pipeline),
    wgpuComputePipelineGetBindGroupLayout(Pipeline, 0, BindLayout),
    format('pipeline: ~p~n', [Pipeline]),

    % -- bind group: storage buffer at binding 0 --
    c_alloc(Entry, struct('WGPUBindGroupEntry')),
    set(Entry, 'WGPUBindGroupEntry', binding, 0),
    set(Entry, 'WGPUBindGroupEntry', buffer, StorageBuf),
    set(Entry, 'WGPUBindGroupEntry', offset, 0),
    set(Entry, 'WGPUBindGroupEntry', size, Bytes),
    c_alloc(BGDesc, struct('WGPUBindGroupDescriptor')),
    set(BGDesc, 'WGPUBindGroupDescriptor', layout, BindLayout),
    set(BGDesc, 'WGPUBindGroupDescriptor', entryCount, 1),
    c_store(BGDesc[entries], Entry),
    wgpuDeviceCreateBindGroup(Device, BGDesc, BindGroup),

    % -- command encoder: compute pass + copy to staging --
    wgpuDeviceCreateCommandEncoder(Device, null, Encoder),
    wgpuCommandEncoderBeginComputePass(Encoder, null, Pass),
    wgpuComputePassEncoderSetPipeline(Pass, Pipeline),
    wgpuComputePassEncoderSetBindGroup(Pass, 0, BindGroup, 0, null),
    Workgroups is (N + 63) // 64,
    wgpuComputePassEncoderDispatchWorkgroups(Pass, Workgroups, 1, 1),
    wgpuComputePassEncoderEnd(Pass),
    wgpuCommandEncoderCopyBufferToBuffer(Encoder, StorageBuf, 0, StagingBuf, 0, Bytes),
    wgpuCommandEncoderFinish(Encoder, null, CmdBuf),
    c_calloc(Cmds, ulong, 8, 1),
    c_address(CmdBuf, CmdAddr),
    c_store(Cmds, 0, ulong, CmdAddr),
    wgpuQueueSubmit(Queue, 1, Cmds),
    format('compute dispatched: ~w workgroup(s)~n', [Workgroups]),

    % -- map staging buffer and read back --
    pl_wgpu_buffer_map_async(StagingBuf, 1, 0, Bytes, null, null, _FutM),  % MapMode_Read
    wait_device(Device, map_result(_), 20000),
    map_result(MStatus),
    format('map status=~w~n', [MStatus]),
    wgpuBufferGetMappedRange(StagingBuf, 0, Bytes, MapPtr),
    read_u32s(MapPtr, 0, N, Output),
    wgpuBufferUnmap(StagingBuf),
    format('output: ~w~n', [Output]),

    % -- cleanup --
    wgpuBufferRelease(StorageBuf),
    wgpuBufferRelease(StagingBuf),
    wgpuDeviceRelease(Device),
    wgpuAdapterRelease(Adapter),
    wgpuInstanceRelease(Instance),
    format('done~n'),
    !.   % keep main deterministic (ffi define/2 leaves a choicepoint)

% ------------------------------------------------------------------
% bench(+N, +K): compute-heavy kernel -- each element runs K iterations
% of x = x*3+1 (mod 2^32).  Compares wall time of the GPU kernel
% (wgpu compute shader) against the same computation in Prolog.
% One-time GPU setup is timed separately.
% ------------------------------------------------------------------

wgsl_bench(K, WGSL) :-
    format(string(WGSL),
           "@group(0) @binding(0) var<storage, read_write> data: array<u32>;\n@compute @workgroup_size(64)\nfn main(@builtin(global_invocation_id) id: vec3<u32>) {\n  var x = data[id.x];\n  for (var i = 0u; i < ~wu; i = i + 1u) { x = x * 3u + 1u; }\n  data[id.x] = x;\n}", [K]).

% Prolog reference kernel: K iterations of x = (x*3+1) mod 2^32
kernel_k(K, X0, X) :- kernel_(X0, K, X).
kernel_(X, 0, X) :- !.
kernel_(X0, K, X) :-
    K1 is K - 1,
    X1 is (X0 * 3 + 1) mod 4294967296,
    kernel_(X1, K1, X).

bench(N, K) :-
    retractall(adapter_result(_, _)),
    retractall(device_result(_, _)),
    retractall(map_result(_)),
    numlist(1, N, Input),
    % CPU reference
    statistics(walltime, [T0|_]),
    maplist(kernel_k(K), Input, CpuOut),
    statistics(walltime, [T1|_]),
    CpuMs is T1 - T0,
    % one-time GPU setup
    statistics(walltime, [S0|_]),
    gpu_bench_setup(N, K, S),
    statistics(walltime, [S1|_]),
    SetupMs is S1 - S0,
    % fill the C array once (Prolog-side, timed separately)
    statistics(walltime, [F0|_]),
    c_alloc(Data, uint[N]),
    fill_data(Data, 0, Input),
    statistics(walltime, [F1|_]),
    FillMs is F1 - F0,
    % timed GPU rounds (R rounds, average): upload + dispatch + submit + wait
    Rounds = 3,
    statistics(walltime, [G0|_]),
    gpu_bench_rounds(S, Data, Rounds),
    statistics(walltime, [G1|_]),
    GpuMs is (G1 - G0) / Rounds,
    % untimed verification: read back and compare
    gpu_bench_readback(S, GpuOut),
    (   CpuOut == GpuOut -> Same = yes ; Same = no ),
    Speedup is (CpuMs + 0.0) / (GpuMs + 0.001),
    format('N=~w elements, K=~w iterations/element (~w element-ops)~n', [N, K, N*K]),
    format('  one-time GPU setup      : ~w ms~n', [SetupMs]),
    format('  Prolog-side array fill  : ~w ms (not part of GPU time)~n', [FillMs]),
    format('  GPU kernel+upload (avg of ~w rounds): ~1f ms~n', [Rounds, GpuMs]),
    format('  CPU (Prolog kernel)     : ~w ms~n', [CpuMs]),
    format('  speedup (kernel)        : ~1f x   results identical: ~w~n', [Speedup, Same]).

% gpu_bench_setup(+N, +K, -State): instance..pipeline, buffers sized N*4
gpu_bench_setup(N, K, S) :-
    Bytes is N * 4,
    wgpuCreateInstance(null, Instance),
    c_alloc(AdapterOpts, struct('WGPURequestAdapterOptions')),
    pl_wgpu_request_adapter(Instance, AdapterOpts, null, null, _FutA),
    wait_instance(Instance, adapter_result(_, _), 20000),
    adapter_result(_, Adapter),
    pl_wgpu_request_device(Adapter, null, null, null, _FutD),
    wait_instance(Instance, device_result(_, _), 20000),
    device_result(_, Device),
    wgpuDeviceGetQueue(Device, Queue),
    c_alloc(StorageDesc, struct('WGPUBufferDescriptor')),
    set(StorageDesc, 'WGPUBufferDescriptor', usage, 140),   % Storage|CopyDst|CopySrc
    set(StorageDesc, 'WGPUBufferDescriptor', size, Bytes),
    wgpuDeviceCreateBuffer(Device, StorageDesc, StorageBuf),
    c_alloc(StagingDesc, struct('WGPUBufferDescriptor')),
    set(StagingDesc, 'WGPUBufferDescriptor', usage, 9),     % MapRead|CopyDst
    set(StagingDesc, 'WGPUBufferDescriptor', size, Bytes),
    wgpuDeviceCreateBuffer(Device, StagingDesc, StagingBuf),
    wgsl_bench(K, WGSL),
    c_alloc(WGSLDesc, uchar[32]),
    c_store(WGSLDesc, 8, uint, 2),
    c_alloc_string(WGSLPtr, WGSL, utf8),
    c_address(WGSLPtr, WGSLAddr),
    atom_length(WGSL, WGSLLen),
    c_store(WGSLDesc, 16, ulong, WGSLAddr),
    c_store(WGSLDesc, 24, size_t, WGSLLen),
    c_alloc(ShaderDesc, struct('WGPUShaderModuleDescriptor')),
    c_store(ShaderDesc[nextInChain], WGSLDesc),
    wgpuDeviceCreateShaderModule(Device, ShaderDesc, ShaderModule),
    c_alloc(CPDesc, struct('WGPUComputePipelineDescriptor')),
    c_store(CPDesc[compute][module], ShaderModule),
    set_str_at(CPDesc, 'WGPUComputePipelineDescriptor', [compute, entryPoint], "main"),
    wgpuDeviceCreateComputePipeline(Device, CPDesc, Pipeline),
    wgpuComputePipelineGetBindGroupLayout(Pipeline, 0, BindLayout),
    c_alloc(Entry, struct('WGPUBindGroupEntry')),
    set(Entry, 'WGPUBindGroupEntry', binding, 0),
    set(Entry, 'WGPUBindGroupEntry', buffer, StorageBuf),
    set(Entry, 'WGPUBindGroupEntry', offset, 0),
    set(Entry, 'WGPUBindGroupEntry', size, Bytes),
    c_alloc(BGDesc, struct('WGPUBindGroupDescriptor')),
    set(BGDesc, 'WGPUBindGroupDescriptor', layout, BindLayout),
    set(BGDesc, 'WGPUBindGroupDescriptor', entryCount, 1),
    c_store(BGDesc[entries], Entry),
    wgpuDeviceCreateBindGroup(Device, BGDesc, BindGroup),
    S = state{instance: Instance, device: Device, queue: Queue,
              storage: StorageBuf, staging: StagingBuf,
              pipeline: Pipeline, bindgroup: BindGroup, bytes: Bytes, n: N}.

% gpu_bench_rounds(+State, +Data, +Rounds): upload, dispatch, submit, wait
gpu_bench_rounds(_, _, 0) :- !.
gpu_bench_rounds(S, Data, R) :-
    R > 0,
    gpu_bench_round(S, Data),
    R1 is R - 1,
    gpu_bench_rounds(S, Data, R1).

gpu_bench_round(S, Data) :-
    N = S.n,
    Bytes = S.bytes,
    wgpuQueueWriteBuffer(S.queue, S.storage, 0, Data, Bytes),
    wgpuDeviceCreateCommandEncoder(S.device, null, Encoder),
    wgpuCommandEncoderBeginComputePass(Encoder, null, Pass),
    wgpuComputePassEncoderSetPipeline(Pass, S.pipeline),
    wgpuComputePassEncoderSetBindGroup(Pass, 0, S.bindgroup, 0, null),
    Workgroups is (N + 63) // 64,
    wgpuComputePassEncoderDispatchWorkgroups(Pass, Workgroups, 1, 1),
    wgpuComputePassEncoderEnd(Pass),
    wgpuCommandEncoderFinish(Encoder, null, CmdBuf),
    c_calloc(Cmds, ulong, 8, 1),
    c_address(CmdBuf, CmdAddr),
    c_store(Cmds, 0, ulong, CmdAddr),
    wgpuQueueSubmit(S.queue, 1, Cmds),
    wgpuDevicePoll(S.device, 1, null, _PollRC).   % wait for completion

% gpu_bench_readback(+State, -Output): copy to staging, map, read u32 list
gpu_bench_readback(S, Output) :-
    N = S.n,
    Bytes = S.bytes,
    wgpuDeviceCreateCommandEncoder(S.device, null, Encoder),
    wgpuCommandEncoderCopyBufferToBuffer(Encoder, S.storage, 0, S.staging, 0, Bytes),
    wgpuCommandEncoderFinish(Encoder, null, CmdBuf),
    c_calloc(Cmds, ulong, 8, 1),
    c_address(CmdBuf, CmdAddr),
    c_store(Cmds, 0, ulong, CmdAddr),
    wgpuQueueSubmit(S.queue, 1, Cmds),
    pl_wgpu_buffer_map_async(S.staging, 1, 0, Bytes, null, null, _FutM),
    wait_device(S.device, map_result(_), 20000),
    wgpuBufferGetMappedRange(S.staging, 0, Bytes, MapPtr),
    read_u32s(MapPtr, 0, N, Output),
    wgpuBufferUnmap(S.staging).

fill_data(_, _, []).
fill_data(Data, I, [H|T]) :-
    c_store(Data[I], H),
    I1 is I + 1,
    fill_data(Data, I1, T).

read_u32s(_, N, N, []).
read_u32s(Ptr, I, N, [V|Vs]) :-
    I < N,
    Off is I * 4,
    c_load(Ptr, Off, uint, V),
    I1 is I + 1,
    read_u32s(Ptr, I1, N, Vs).

wait_instance(Instance, Cond, Tries) :-
    (   call(Cond)
    ->  true
    ;   Tries =< 0
    ->  format('TIMEOUT (instance events)~n'), fail
    ;   wgpuInstanceProcessEvents(Instance),
        T1 is Tries - 1,
        wait_instance(Instance, Cond, T1)
    ).

wait_device(Device, Cond, Tries) :-
    (   call(Cond)
    ->  true
    ;   Tries =< 0
    ->  format('TIMEOUT (device poll)~n'), fail
    ;   wgpuDevicePoll(Device, 1, null, _),
        T1 is Tries - 1,
        wait_device(Device, Cond, T1)
    ).
