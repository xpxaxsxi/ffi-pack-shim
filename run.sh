#!/bin/sh
# Run the WebGPU hello program from SWI-Prolog.
# Usage: ./run.sh [path-to-swipl]   (default: swipl from PATH)
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SWIPL=${1:-swipl}
export LD_LIBRARY_PATH="$DIR/lib/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
cd "$DIR"
exec "$SWIPL" -g "use_module(wgpu_hello)"
