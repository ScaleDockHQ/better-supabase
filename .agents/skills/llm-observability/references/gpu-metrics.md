# GPU metrics: DCGM exporter, nvidia-smi, unified memory

> Verified against NVIDIA dcgm-exporter docs, DGX Spark and GB10 documentation, 2026-10-11

Stack notes only. Exporter install, metric reading and troubleshooting live in the `dcgm-exporter` skill.

## How it plugs into the stack

- Endpoint `http://<gpu-host>:9400/metrics`, no auth by default; `--web-config-file` adds TLS or basic auth. Keep the port private.
- Join GPU and engine panels by relabelling both jobs to a common `host` label.
- Busy means `DCGM_FI_PROF_GR_ENGINE_ACTIVE`, not `DCGM_FI_DEV_GPU_UTIL` (time-based, 100% is not saturated).
- Engines pre-allocate KV cache, so high framebuffer use is normal; alert on engine KV-cache usage or OOM/restart.
- Unified memory (DGX Spark / GB10): `nvidia-smi` shows "Memory-Usage: Not Supported" by design and DCGM `FB_*` fields are unverified there; monitor host `node_memory_MemAvailable_bytes` and swap instead.

Depth:

- `dcgm-exporter`: `npx skills add ScaleDockHQ/llm-skills --skill dcgm-exporter`
- `sparkdash`: `npx skills add ScaleDockHQ/llm-skills --skill sparkdash`
