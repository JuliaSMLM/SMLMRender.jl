# SMLMRender Tuple-Pattern Implementation Spec

## Current API

```julia
# Returns RenderResult2D struct
result = render(smld, strategy=GaussianRender(), color_by=:frame, zoom=20)

# Access fields
result.image              # Matrix{RGB{Float64}}
result.target             # Image2DTarget
result.options            # RenderOptions
result.render_time        # Float64 (seconds)
result.n_localizations    # Int
result.field_value_range  # Union{Nothing, Tuple{Float64,Float64}}
```

**RenderResult2D definition (current):**
```julia
struct RenderResult2D
    image::Matrix{RGB{Float64}}
    target::Image2DTarget
    options::RenderOptions
    render_time::Float64
    n_localizations::Int
    field_value_range::Union{Nothing, Tuple{Float64, Float64}}
end
```

## Target API

```julia
# Returns (image, info) tuple
(image, info) = render(smld, strategy=GaussianRender(), color_by=:frame, zoom=20)

# image is the primary product
image::Matrix{RGB{Float64}}

# info contains metadata
info.elapsed_ns          # UInt64
info.backend             # Symbol (:cpu, :cuda, :metal)
info.device_id           # Int
info.n_emitters_rendered # Int
info.output_size         # Tuple{Int,Int}
info.pixel_size_nm       # Float64
info.strategy            # Symbol
info.color_mode          # Symbol
info.field_range         # Union{Nothing, Tuple{Float64,Float64}}
```

## RenderInfo Struct

```julia
"""
    RenderInfo

Metadata from a render operation. Follows ecosystem convention for info structs.

# Common fields (ecosystem convention)
- `elapsed_ns::UInt64`: Execution time in nanoseconds
- `backend::Symbol`: Compute backend used (:cpu, :cuda, :metal)
- `device_id::Int`: Device identifier (0 for CPU)

# Render-specific fields
- `n_emitters_rendered::Int`: Number of emitters actually rendered
- `output_size::Tuple{Int,Int}`: (height, width) of output image
- `pixel_size_nm::Float64`: Output pixel size in nanometers
- `strategy::Symbol`: Rendering strategy used (:gaussian, :histogram, :circle, :ellipse)
- `color_mode::Symbol`: Color mapping mode (:intensity, :field, :categorical, :manual, :grayscale)
- `field_range::Union{Nothing, Tuple{Float64,Float64}}`: Value range for colorbar (field/categorical modes)
"""
struct RenderInfo
    # Common fields (ecosystem convention)
    elapsed_ns::UInt64
    backend::Symbol
    device_id::Int

    # Render-specific fields
    n_emitters_rendered::Int
    output_size::Tuple{Int,Int}
    pixel_size_nm::Float64
    strategy::Symbol
    color_mode::Symbol
    field_range::Union{Nothing, Tuple{Float64,Float64}}
end
```

## Implementation Steps

### Phase 1: Add RenderInfo struct
1. Define `RenderInfo` in `src/types.jl`
2. Export from `SMLMRender.jl`
3. Add helper constructor for convenience

### Phase 2: Update render internals
1. Modify `_render_dispatch` to use `time_ns()` for timing
2. Build `RenderInfo` from render metadata
3. Return `(image, info)` tuple instead of `RenderResult2D`

### Phase 3: Update interface functions
1. Update `render(smld; kwargs...)` signature
2. Update `render(smlds::Vector; kwargs...)` for multi-channel
3. Update `render(smld, x_edges, y_edges; kwargs...)` for custom grids

### Phase 4: Deprecation
1. Keep `RenderResult2D` with deprecation warning
2. Add conversion: `RenderResult2D(image, info)` constructor
3. Document migration path

### Phase 5: Cleanup (next minor version)
1. Remove `RenderResult2D`
2. Remove deprecation warnings
3. Update all examples and docs

## Migration Guide

```julia
# Old code
result = render(smld, zoom=20)
img = result.image
time = result.render_time

# New code
(img, info) = render(smld, zoom=20)
time = info.elapsed_ns / 1e9  # Convert to seconds

# Or if you just want the image
img, _ = render(smld, zoom=20)
```

## Files to Modify

1. `src/types.jl` - Add RenderInfo, deprecate RenderResult2D
2. `src/interface.jl` - Update render() return type
3. `src/SMLMRender.jl` - Export RenderInfo
4. `docs/src/index.md` - Update examples
5. `docs/src/examples.md` - Update all code samples
6. `examples/*.jl` - Update all example scripts
7. `test/runtests.jl` - Add tests for new API

## Testing Checklist

- [ ] `(image, info) = render(smld, zoom=20)` works
- [ ] `info.elapsed_ns` is reasonable (> 0, < 60s worth)
- [ ] `info.backend == :cpu` for CPU rendering
- [ ] `info.n_emitters_rendered == length(smld.emitters)`
- [ ] `info.output_size == size(image)`
- [ ] `info.strategy` matches requested strategy
- [ ] `info.color_mode` matches requested coloring
- [ ] `info.field_range` populated for field/categorical modes
- [ ] Deprecation warning fires for old API usage
- [ ] All existing examples still work (with warnings)

## Dependencies

- **Upstream**: SMLMData (no changes needed - we just consume emitter types)
- **Downstream**: SMLMAnalysis (will need to update render calls)

## Timeline

Phase 3 in ecosystem rollout (after GaussMLE, BoxerCore templates available).
