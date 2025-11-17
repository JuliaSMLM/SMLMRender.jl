# SMLMRender.jl

High-performance rendering for Single Molecule Localization Microscopy (SMLM) data.

**Part of the [JuliaSMLM](https://github.com/JuliaSMLM) ecosystem.**

SMLMRender.jl transforms SMLM localization data from [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) into publication-quality images. It provides clean, Julian APIs with multiple rendering strategies, intensity-weighted field coloring, and direct PNG export.

## Features

### Rendering Strategies

- **HistogramRender** - Fast binning, saturates on overlap
- **GaussianRender** - Smooth Gaussian blobs with intensity-weighted field coloring
- **CircleRender** - Anti-aliased circles at localization precision, saturates on overlap

### Color Mapping

- **Intensity-based** - Accumulate counts, apply colormap (inferno, hot, etc.)
- **Field-based** - Color by emitter field (z-depth, photons, frame, σ_x)
  - Intensity-weighted (Gaussian): color from field, brightness from overlap
  - Saturating (Histogram/Circles): full color, saturates where dense
- **Multi-channel** - Fixed colors for channel overlays

### Colormaps

- Black backgrounds: inferno, hot, magma
- Field coloring: turbo (default), plasma, viridis, twilight
- Diverging: RdBu, coolwarm

### Output

- Direct PNG save with auto field range extraction
- Colorbar export with metadata
- Multi-channel overlays via dispatch

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

```julia
using SMLMData, SMLMRender

# Load SMLM data (from SMLMData.jl)
smld = load_smld("data.h5")  # Or from SMLMSim, analysis pipeline, etc.

# Simple rendering with direct save (returns RenderResult2D)
result = render(smld, colormap=:inferno, zoom=20, filename="output.png")

# Access image if needed
img = result.image  # Matrix{RGB{Float64}}

# Color by z-depth with custom colormap
result = render(smld, color_by=:z, colormap=:turbo, zoom=20, filename="depth.png")

# Export colorbar with auto metadata
export_colorbar(result, "colorbar.png")
```

## Documentation Structure

- [Examples](@ref) - Detailed usage examples for all rendering modes
- [API Reference](@ref) - Complete API documentation

## Main Interface

The package provides a simple, consistent interface:

**Single-channel rendering:**
```julia
result = render(smld; kwargs...)
```

**Multi-channel rendering via dispatch:**
```julia
result = render([smld1, smld2]; colors=[:red, :green], kwargs...)
```

**Export utilities:**
```julia
export_colorbar(result, filename)
save_image(filename, image)
```

## Rendering Strategies

### HistogramRender

Fastest option. Bins localizations into pixels. Saturates on overlap for bright, punchy colors.

```julia
result = render(smld, strategy=HistogramRender(), zoom=10, filename="hist.png")
```

### GaussianRender

Renders each localization as a 2D Gaussian blob with intensity-weighted field coloring. Provides smooth, publication-quality images.

```julia
# Use localization precision (σ_x, σ_y from data)
result = render(smld,
    strategy = GaussianRender(
        n_sigmas = 3.0,
        use_localization_precision = true,
        normalization = :integral
    ),
    zoom = 20,
    filename = "gaussian.png")
```

### CircleRender

Renders circles at localization precision. Best with high zoom (50x) for visibility. Saturates on overlap.

```julia
# 1σ circles (recommended)
result = render(smld,
    strategy = CircleRender(
        radius_factor = 1.0,
        line_width = 1.0,
        use_localization_precision = true
    ),
    color_by = :frame,
    colormap = :turbo,
    zoom = 50,
    filename = "circles.png")
```

## Color Mapping

### Intensity Colormaps

Traditional SMLM: accumulate intensity → apply colormap.

```julia
# Render with inferno (black background)
result = render(smld, colormap=:inferno, zoom=20, filename="img.png")

# Available: :inferno, :hot, :viridis, :plasma, :magma, :turbo, etc.
```

### Field-Based Colormaps

Color by field value with intensity-weighted coloring (vibrant, punchy colors).

```julia
# Color by z-depth (default: turbo colormap)
result = render(smld, color_by=:z, zoom=20, filename="depth.png")

# Color by photon count
result = render(smld, color_by=:photons, colormap=:viridis, zoom=20)

# Export colorbar with auto-extracted metadata
export_colorbar(result, "colorbar.png")
```

### Multi-Channel Rendering

Multi-color imaging using multiple dispatch (no Colors import needed):

```julia
# Two-color overlay using symbols
result = render([smld_channel1, smld_channel2],
                colors = [:red, :green],
                strategy = GaussianRender(),
                zoom = 20,
                filename = "overlay.png")
```

## Recommended Colormaps

### Black Backgrounds (for intensity-based)
- `:inferno` - Black → Purple → Orange → Yellow (recommended)
- `:hot` - Black → Red → Yellow → White (classic SMLM)
- `:magma` - Black → Purple → Orange → Yellow

### Field-Based (color by z, time, photons, etc.)
- `:turbo` - High contrast rainbow (default, napari standard)
- `:plasma` - Blue → Yellow (high contrast + perceptual)
- `:viridis` - Purple → Yellow (perceptual uniform)
- `:twilight` - Cyclic (good for temporal/angular data)

### Diverging (for symmetric fields)
- `:RdBu` - Red ↔ Blue (good for ±z around focal plane)
- `:coolwarm` - Red ↔ Blue alternative

Use [`list_recommended_colormaps`](@ref) to see all options.

## Related Packages

- [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) - Data structures for SMLM
- [SMLMVis.jl](https://github.com/JuliaSMLM/SMLMVis.jl) - Interactive visualization
- [SMLMMetrics.jl](https://github.com/JuliaSMLM/SMLMMetrics.jl) - Analysis and metrics

## Contributing

Contributions welcome! Please open an issue or PR at [https://github.com/JuliaSMLM/SMLMRender.jl](https://github.com/JuliaSMLM/SMLMRender.jl).

## License

MIT License - see LICENSE file
