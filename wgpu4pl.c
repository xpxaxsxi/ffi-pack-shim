/* wgpu4pl.c -- thin C shim over wgpu-native (v29 API) for the SWI-Prolog ffi pack.
 *
 * The v29 webgpu.h API passes the *CallbackInfo structs BY VALUE, which the
 * ffi pack cannot marshal.  These wrappers take a plain C callback pointer
 * (with a simplified scalar-only signature) plus userdata, build the
 * CallbackInfo struct internally, and hand the future back through an
 * out-parameter.  Everything else in the wgpu API is passed by pointer and
 * is imported directly from webgpu.h by the Prolog side.
 */
#include "wgpu.h"
#include <stdlib.h>
#include <stdint.h>

typedef void (*pl_adapter_cb)(uint32_t status, WGPUAdapter adapter, void *ud1, void *ud2);
typedef void (*pl_device_cb)(uint32_t status, WGPUDevice device, void *ud1, void *ud2);
typedef void (*pl_map_cb)(uint32_t status, void *ud1, void *ud2);

typedef struct { void *cb; void *ud1; void *ud2; } pl_ctx;

static void pl_adapter_trampoline(WGPURequestAdapterStatus status, WGPUAdapter adapter,
                                  WGPUStringView msg, void *ud1, void *ud2)
{ (void)msg; (void)ud2;
  pl_ctx *ctx = (pl_ctx*)ud1;
  pl_adapter_cb cb = (pl_adapter_cb)ctx->cb;
  void *u1 = ctx->ud1, *u2 = ctx->ud2;
  free(ctx);
  if ( cb ) cb((uint32_t)status, adapter, u1, u2);
}

static void pl_device_trampoline(WGPURequestDeviceStatus status, WGPUDevice device,
                                 WGPUStringView msg, void *ud1, void *ud2)
{ (void)msg; (void)ud2;
  pl_ctx *ctx = (pl_ctx*)ud1;
  pl_device_cb cb = (pl_device_cb)ctx->cb;
  void *u1 = ctx->ud1, *u2 = ctx->ud2;
  free(ctx);
  if ( cb ) cb((uint32_t)status, device, u1, u2);
}

static void pl_map_trampoline(WGPUMapAsyncStatus status, WGPUStringView msg, void *ud1, void *ud2)
{ (void)msg; (void)ud2;
  pl_ctx *ctx = (pl_ctx*)ud1;
  pl_map_cb cb = (pl_map_cb)ctx->cb;
  void *u1 = ctx->ud1, *u2 = ctx->ud2;
  free(ctx);
  if ( cb ) cb((uint32_t)status, u1, u2);
}

void pl_wgpu_request_adapter(WGPUInstance instance,
                             WGPURequestAdapterOptions const *options,
                             pl_adapter_cb cb, void *ud1, void *ud2,
                             WGPUFuture *out)
{ pl_ctx *ctx = malloc(sizeof(pl_ctx));
  ctx->cb = (void*)cb; ctx->ud1 = ud1; ctx->ud2 = ud2;
  WGPURequestAdapterCallbackInfo ci = WGPU_REQUEST_ADAPTER_CALLBACK_INFO_INIT;
  ci.mode = WGPUCallbackMode_AllowProcessEvents;
  ci.callback = pl_adapter_trampoline;
  ci.userdata1 = ctx;
  *out = wgpuInstanceRequestAdapter(instance, options, ci);
}

void pl_wgpu_request_device(WGPUAdapter adapter,
                            WGPUDeviceDescriptor const *descriptor,
                            pl_device_cb cb, void *ud1, void *ud2,
                            WGPUFuture *out)
{ pl_ctx *ctx = malloc(sizeof(pl_ctx));
  ctx->cb = (void*)cb; ctx->ud1 = ud1; ctx->ud2 = ud2;
  WGPURequestDeviceCallbackInfo ci = WGPU_REQUEST_DEVICE_CALLBACK_INFO_INIT;
  ci.mode = WGPUCallbackMode_AllowProcessEvents;
  ci.callback = pl_device_trampoline;
  ci.userdata1 = ctx;
  *out = wgpuAdapterRequestDevice(adapter, descriptor, ci);
}

void pl_wgpu_buffer_map_async(WGPUBuffer buffer, WGPUMapMode mode,
                              size_t offset, size_t size,
                              pl_map_cb cb, void *ud1, void *ud2,
                              WGPUFuture *out)
{ pl_ctx *ctx = malloc(sizeof(pl_ctx));
  ctx->cb = (void*)cb; ctx->ud1 = ud1; ctx->ud2 = ud2;
  WGPUBufferMapCallbackInfo ci = WGPU_BUFFER_MAP_CALLBACK_INFO_INIT;
  ci.mode = WGPUCallbackMode_AllowProcessEvents;
  ci.callback = pl_map_trampoline;
  ci.userdata1 = ctx;
  *out = wgpuBufferMapAsync(buffer, mode, offset, size, ci);
}
