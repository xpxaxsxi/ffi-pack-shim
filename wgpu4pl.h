/* wgpu4pl.h -- declarations for the wgpu-native v29 shim (see wgpu4pl.c) */
#ifndef WGPU4PL_H
#define WGPU4PL_H

#include "wgpu.h"
#include <stdint.h>

typedef void (*pl_adapter_cb)(uint32_t status, WGPUAdapter adapter, void *ud1, void *ud2);
typedef void (*pl_device_cb)(uint32_t status, WGPUDevice device, void *ud1, void *ud2);
typedef void (*pl_map_cb)(uint32_t status, void *ud1, void *ud2);

void pl_wgpu_request_adapter(WGPUInstance instance,
                             WGPURequestAdapterOptions const *options,
                             pl_adapter_cb cb, void *ud1, void *ud2,
                             WGPUFuture *out);

void pl_wgpu_request_device(WGPUAdapter adapter,
                            WGPUDeviceDescriptor const *descriptor,
                            pl_device_cb cb, void *ud1, void *ud2,
                            WGPUFuture *out);

void pl_wgpu_buffer_map_async(WGPUBuffer buffer, WGPUMapMode mode,
                              size_t offset, size_t size,
                              pl_map_cb cb, void *ud1, void *ud2,
                              WGPUFuture *out);

#endif
