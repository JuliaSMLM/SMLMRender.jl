# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Package Overview

SMLMRender is a Julia package for rendering single molecule localization microscopy (SMLM) data into images. Part of the JuliaSMLM ecosystem. Depends on SMLMData 0.7 for emitter types, camera types, and abstract config/info base types.

## Commands

```bash
# Run tests
julia --project=. -e 'using Pkg; Pkg.test()'

# Run tests with output
julia --project=. test/runtests.jl

# Run examples (from repo root)
julia --project=examples examples/render_strategies_demo.jl

# Build documentation
julia --project=docs docs/make.jl
```

## Architecture

### Source Organization

- `src/types.jl` - All type definitions: strategies, color mappings, targets, RenderConfig, RenderInfo
- `src/interface.jl` - All `render()` method signatures and dispatch logic
- `src/utils.jl` - Coordinate transforms, field handling, image processing helpers
- `src/color/mapping.jl` - Color mapping implementations (intensity, field, categorical, manual, grayscale)
- `src/render/{gaussian,histogram,circle,ellipse}.jl` - Per-strategy rendering implementations
- `src/api.jl` - Loads `api_overview.md` for programmatic API access

### Key Design Patterns

**Tuple return pattern:** All `render()` calls return `(image::Matrix{RGB{Float64}}, info::RenderInfo)`. The old `RenderResult2D` is deprecated.

**Flat RenderConfig:** Fields match `render()` kwargs exactly — no nested structs. Users can pass kwargs directly or construct a RenderConfig.

**Ecosystem inheritance:** `RenderConfig <: AbstractSMLMConfig` and `RenderInfo <: AbstractSMLMInfo` (from SMLMData).

**Dispatch hierarchy for render():**
1. `render(smld; kwargs...)` — convenience, constructs RenderConfig
2. `render(smld, config::RenderConfig)` — builds target from config/smld
3. `render(smld, target::Image2DTarget, config::RenderConfig)` — primary form, dispatches to strategy+color rendering
4. `render(smlds::Vector; colors, kwargs...)` — multi-channel overlay

**Strategy × ColorMapping dispatch:** Internal `render_image` methods dispatch on `(strategy, color_mapping)` pairs. Each strategy file implements rendering for relevant color mapping types.

### Resolution Modes (mutually exclusive)

- **Zoom mode:** `zoom=N` subdivides camera pixels. 128×128 camera at zoom=10 → 1280×1280 output. Requires camera on SMLD. Supports `roi` for camera pixel subregions.
- **Pixel size mode:** `pixel_size=N` (nm) computes output from data bounds + margin. Output size varies with data extent.

### Coordinate System

Physical coordinates in **micrometers** (μm). Pixel sizes specified in **nanometers** (nm). Pixel (1.0, 1.0) is center of top-left pixel.

### Sparse Data Optimization

Intensity percentile clipping (`clip_percentile`) is computed on **non-zero pixels only** — critical for SMLM where most pixels are empty.

## Current State

- **Branch:** `feature/tuple-pattern` — active development branch
- **Main branch:** `main` (PR target)
- Julia ≥ 1.10 required
