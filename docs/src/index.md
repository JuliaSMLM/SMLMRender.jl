# SMLMRender.jl

Rendering for Single Molecule Localization Microscopy (SMLM) data.

**Part of the [JuliaSMLM](https://github.com/JuliaSMLM) ecosystem.**

SMLMRender.jl transforms SMLM localization data from [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) into images. It provides multiple rendering strategies, intensity-weighted field coloring, and PNG export.

## Features

### Rendering Strategies

- **HistogramRender** - Fast binning with percentile-normalized intensity (saturate mode via `clip_percentile=nothing`)
- **GaussianRender** - Smooth Gaussian blobs with intensity-weighted field coloring
- **CircleRender** - Anti-aliased circles at localization precision, saturates on overlap

### Color Mapping

- **Intensity-based** - Accumulate counts, apply colormap (inferno, hot, etc.)
- **Field-based** - Color by emitter field (z-depth, photons, frame, σ_x)
  - Intensity-weighted (Gaussian): color from field, brightness from overlap
  - Percentile-normalized (Histogram): clip + normalize intensity, or saturate with `clip_percentile=nothing`
- **Multi-channel** - Fixed colors for channel overlays

### Colormaps

- Black backgrounds: inferno, hot, magma
- Field coloring: turbo (default), plasma, viridis, twilight
- Diverging: RdBu, coolwarm

### Output

- Direct PNG save with auto field range extraction
- Colorbar export with metadata
- Multi-channel overlays via dispatch

### Resolution Control

Two modes for specifying output resolution:

- **`zoom`**: Renders exact camera FOV with subdivided pixels
  - `zoom=20` with 128×128 camera → exactly 2560×2560 output
  - Output range matches camera FOV exactly
  - Predictable, reproducible sizes

- **`pixel_size`**: Uses data bounds with margin
  - Output size varies based on localization positions
  - Useful for cropping to regions of interest
  - Specify in nm (e.g., `pixel_size=10.0`)

- **`roi`**: Region of interest (zoom mode only)
  - Render a subset of the camera FOV
  - Specify camera pixel ranges: `roi=(x_range, y_range)`
  - Use `:` for full range on an axis: `roi=(430:860, :)`

## Installation

```julia
using Pkg
Pkg.add("SMLMRender")
```

For development:

```julia
using Pkg
Pkg.develop(url="https://github.com/JuliaSMLM/SMLMRender.jl")
```

## Quick Start

A Siemens star test pattern — 8 filled wedges with z-depth encoded by angular position:

```@example quickstart
using SMLMRender, SMLMData, Random
Random.seed!(42)

# Siemens star: 16 slices (8 filled, 8 empty), z varies with angle
n_slices = 16
R_min, R_max = 0.1, 3.0
cx, cy = 3.2, 3.2
density, σ_psf = 400.0, 0.13

wedge_area = (π / n_slices) * (R_max^2 - R_min^2)
n_per_wedge = round(Int, density * wedge_area)

emitters = Emitter3DFit{Float64}[]
for s in 0:(n_slices - 1)
    iseven(s) || continue
    θ_min = 2π * s / n_slices
    θ_max = 2π * (s + 1) / n_slices
    z = -1.0 + 2.0 * (θ_min + θ_max) / (2 * 2π)
    for _ in 1:n_per_wedge
        r = sqrt(rand() * (R_max^2 - R_min^2) + R_min^2)
        θ = θ_min + rand() * (θ_max - θ_min)
        photons = max(10.0, randexp() * 500.0)
        σ = σ_psf / sqrt(photons)
        push!(emitters, Emitter3DFit{Float64}(
            cx + r*cos(θ), cy + r*sin(θ), z, photons, 10.0, σ, σ, 0.050, 50.0, 2.0;
            frame=mod1(s+1, 20), id=length(emitters)+1))
    end
end
camera = IdealCamera(64, 64, 0.1)
smld = BasicSMLD(emitters, camera, 20, 1)
println("$(length(smld.emitters)) localizations (Siemens star, 8 wedges)")
```

### Rendering Strategies

```@example quickstart
# Histogram: Fast binning (pixelated but fast)
(img_hist, info_hist) = render(smld, RenderConfig(strategy=HistogramRender(), zoom=20))

# Gaussian: Smooth blobs
(img_gauss, info_gauss) = render(smld, RenderConfig(strategy=GaussianRender(), zoom=20))

# Circle: Visualize localization precision (requires color_by or color)
(img_circle, info_circle) = render(smld, RenderConfig(strategy=CircleRender(), color_by=:frame, zoom=20))

println("Histogram: $(size(img_hist))")
println("Gaussian: $(size(img_gauss))")
println("Circle: $(size(img_circle))")
```

### Color Mapping

```@example quickstart
# Intensity-based coloring (traditional SMLM)
(img_intensity, info_intensity) = render(smld, RenderConfig(colormap=:inferno, zoom=20))

# Field-based coloring (color by photon count)
(img_field, info_field) = render(smld, RenderConfig(color_by=:photons, colormap=:viridis, zoom=20))

println("Rendered with intensity and field-based coloring")
```

## Documentation Structure

- [Examples](@ref) - Detailed usage examples for all rendering modes
- [API Reference](@ref) - Complete API documentation

## Main Interface

```@example quickstart
# Single-channel rendering returns (image, info) tuple
(img, info) = render(smld, RenderConfig(zoom=20))

# Multi-channel rendering (no Colors import needed)
# (img, info) = render([smld1, smld2], colors=[:red, :green], zoom=20)

# Export utilities
# save_image("output.png", img)
nothing # hide
```

For detailed examples of rendering strategies and color mapping options, see the [Examples](@ref) page.

## Related Packages

- [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) - Data structures for SMLM
- [SMLMVis.jl](https://github.com/JuliaSMLM/SMLMVis.jl) - Interactive visualization
- [SMLMMetrics.jl](https://github.com/JuliaSMLM/SMLMMetrics.jl) - Analysis and metrics

## Contributing

Contributions welcome! Please open an issue or PR at [https://github.com/JuliaSMLM/SMLMRender.jl](https://github.com/JuliaSMLM/SMLMRender.jl).

## License

MIT License - see LICENSE file
