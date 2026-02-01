# SMLMRender API Overview

AI-parseable API reference for SMLMRender.jl.

## Main Interface

### render(smld; kwargs...) -> (image, info)

Render SMLM localization data to an image.

**Returns:** Tuple of `(image::Matrix{RGB{Float64}}, info::RenderInfo)`

**Keywords:**
- `strategy::RenderingStrategy = GaussianRender()` - Rendering algorithm
- `zoom::Real` - Output pixels per camera pixel (use this OR pixel_size)
- `pixel_size::Real` - Output pixel size in nm (use this OR zoom)
- `target::Image2DTarget` - Explicit render target (advanced)
- `colormap::Symbol` - Colormap for intensity mode (:inferno, :hot, :viridis, etc.)
- `color_by::Symbol` - Field for coloring (:z, :photons, :frame, :σ_x, etc.)
- `color::RGB` - Manual fixed color
- `clip_percentile::Real = 0.999` - Intensity clipping percentile
- `field_range::Union{Tuple,Symbol} = :auto` - Field value range or :auto
- `field_clip_percentiles::Tuple = (0.01, 0.99)` - Field percentile clipping
- `backend::Symbol = :cpu` - Compute backend (:cpu, :cuda, :metal, :auto)
- `filename::String` - Save image directly to file

**Example:**
```julia
(img, info) = render(smld, colormap=:inferno, zoom=20)
(img, info) = render(smld, color_by=:z, colormap=:turbo, zoom=20)
img, _ = render(smld, zoom=20, filename="output.png")
```

### render(smlds::Vector; colors, kwargs...) -> (image, info)

Multi-channel overlay rendering.

**Returns:** Tuple of `(image::Matrix{RGB{Float64}}, info::RenderInfo)`

**Keywords:**
- `colors::Vector` - Colors for each dataset (:red, :green, RGB values, etc.)
- `normalize_each::Bool = true` - Normalize channels independently
- Other kwargs same as single-channel render()

**Example:**
```julia
(img, info) = render([smld1, smld2], colors=[:red, :green], zoom=20)
```

## RenderInfo

Metadata from a render operation. Follows ecosystem convention.

**Common fields (ecosystem standard):**
- `elapsed_ns::UInt64` - Execution time in nanoseconds
- `backend::Symbol` - Compute backend used (:cpu, :cuda, :metal)
- `device_id::Int` - Device identifier (0 for CPU)

**Render-specific fields:**
- `n_emitters_rendered::Int` - Number of emitters actually rendered
- `output_size::Tuple{Int,Int}` - (height, width) of output image
- `pixel_size_nm::Float64` - Output pixel size in nanometers
- `strategy::Symbol` - Rendering strategy (:gaussian, :histogram, :circle)
- `color_mode::Symbol` - Color mapping mode (:intensity, :field, :manual, :grayscale)
- `field_range::Union{Nothing,Tuple{Float64,Float64}}` - Value range for colorbar

**Example:**
```julia
(img, info) = render(smld, zoom=20)
println("Rendered $(info.n_emitters_rendered) emitters")
println("Time: $(info.elapsed_ns / 1e6) ms")
println("Size: $(info.output_size)")
println("Strategy: $(info.strategy)")
```

## Rendering Strategies

### GaussianRender

Smooth Gaussian blob rendering. Default strategy.

```julia
GaussianRender(;
    n_sigmas = 3.0,
    use_localization_precision = true,
    fixed_sigma = nothing,
    normalization = :integral  # or :maximum
)
```

### HistogramRender

Fast binning-based rendering.

```julia
HistogramRender()
```

### CircleRender

Circle outline rendering for uncertainty visualization.

```julia
CircleRender(;
    radius_factor = 2.0,
    line_width = 1.0,
    use_localization_precision = true,
    fixed_radius = nothing
)
```

## Color Mapping Types

### IntensityColorMapping

Accumulate intensity, apply colormap.

```julia
IntensityColorMapping(colormap::Symbol, clip_percentile::Real = 0.999)
```

### FieldColorMapping

Color by emitter field value.

```julia
FieldColorMapping(field::Symbol, colormap::Symbol, range, clip_percentiles)
```

### ManualColorMapping

Fixed color for all localizations.

```julia
ManualColorMapping(color::RGB{Float64})
```

### GrayscaleMapping

No colormap, grayscale output.

```julia
GrayscaleMapping()
```

## Utility Functions

### save_image(filename, image)

Save rendered image to file.

### export_colorbar(colormap, range, label, filename; kwargs...)

Export colorbar for field-colored images.

```julia
(img, info) = render(smld, color_by=:z, zoom=20)
export_colorbar(:turbo, info.field_range, "Z-depth (nm)", "colorbar.png")
```

### create_target_from_smld(smld; pixel_size, zoom)

Create Image2DTarget from SMLD data.

### list_recommended_colormaps()

Get categorized list of recommended colormaps.

## Deprecated

### RenderResult2D

**Deprecated.** Use tuple unpacking instead:

```julia
# Old (deprecated)
result = render(smld, zoom=20)
img = result.image

# New
(img, info) = render(smld, zoom=20)
```
