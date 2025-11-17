# SMLMRender.jl

High-performance rendering for Single Molecule Localization Microscopy (SMLM) data.

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaSMLM.github.io/SMLMRender.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaSMLM.github.io/SMLMRender.jl/dev/)
[![Build Status](https://github.com/JuliaSMLM/SMLMRender.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaSMLM/SMLMRender.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaSMLM/SMLMRender.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaSMLM/SMLMRender.jl)

**Part of the [JuliaSMLM](https://github.com/JuliaSMLM) ecosystem.**

SMLMRender.jl renders SMLM localization data (from [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl)) into publication-quality images. It provides clean, Julian APIs with multiple rendering strategies, intensity-weighted field coloring, and direct PNG export.

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

## API Reference

### Main Functions (All You Need)

**`render(smld; kwargs...)`** - Single-channel rendering
- Returns `RenderResult2D` with `.image` and metadata
- Use `filename=...` for direct PNG save

**`render(smlds::Vector; colors, kwargs...)`** - Multi-channel via dispatch
- Takes vector of SMLD datasets
- `colors` as symbols (`:red`, `:green`) or RGB

**`export_colorbar(result, filename)`** - Colorbar legends
- Auto-extracts field range and colormap from result
- Or manual: `export_colorbar(:turbo, (-500, 500), "Z (nm)", filename)`

**`save_image(filename, image)`** - Direct image save
- Usually not needed (use `filename` kwarg in `render()`)

### Rendering Strategies

- **`HistogramRender()`** - Fast binning (saturates, black bg)
- **`GaussianRender()`** - Smooth blobs (intensity-weighted)
- **`CircleRender(radius_factor, line_width)`** - Uncertainty circles (saturates)

### Result Type

- **`RenderResult2D`** - Contains `.image`, `.field_range`, `.colormap`, `.render_time`

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

# Gaussian rendering with localization precision
result = render(smld,
    strategy = GaussianRender(n_sigmas=3.0, use_localization_precision=true),
    colormap = :hot,
    zoom = 15,
    filename = "gaussian.png")

# Circle rendering (1σ circles, saturates on overlap)
result = render(smld,
    strategy = CircleRender(radius_factor=1.0, line_width=1.0),
    color_by = :photons,
    colormap = :plasma,
    zoom = 50,  # Higher zoom for thin lines
    filename = "circles.png")

# Two-color overlay using dispatch (no Colors import needed!)
result = render([smld_protein1, smld_protein2],
                colors = [:red, :green],
                zoom = 20,
                filename = "overlay.png")
```

## Rendering Strategies

### Histogram Rendering

Fastest option. Bins localizations into pixels.

```julia
result = render(smld, strategy=HistogramRender(), zoom=10, filename="hist.png")
```

### Gaussian Rendering

Renders each localization as a 2D Gaussian blob with intensity-weighted field coloring.

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

# Or use fixed sigma
result = render(smld,
    strategy = GaussianRender(fixed_sigma=15.0),
    colormap = :hot,
    zoom = 20)
```

### Circle Rendering

Renders circles at localization precision. Best with high zoom (50x) for visibility.

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
    zoom = 50,  # High zoom for thin lines
    filename = "circles.png")
```

## Color Mapping

### Intensity Colormaps

Traditional SMLM: accumulate intensity → apply colormap.

```julia
# Render with inferno (black background)
result = render(smld, colormap=:inferno, zoom=20, filename="img.png")

# Available colormaps: :inferno, :hot, :viridis, :plasma, :magma, :turbo, etc.
```

### Field-Based Colormaps

Color by field value with intensity-weighted coloring (vibrant, punchy colors).

```julia
# Color by z-depth (default: turbo colormap)
result = render(smld, color_by=:z, zoom=20, filename="depth.png")

# Color by z-depth with custom colormap
result = render(smld, color_by=:z, colormap=:plasma, zoom=20)

# Color by photon count
result = render(smld, color_by=:photons, colormap=:viridis, zoom=20)

# Color by frame number (temporal dynamics)
result = render(smld, color_by=:frame, colormap=:twilight, zoom=20)

# Export colorbar with auto-extracted metadata
export_colorbar(result, "colorbar.png")
```

**Note:** Field coloring defaults to `:turbo` (napari standard, high contrast).

## Multi-Channel Rendering

Multi-color imaging using multiple dispatch (no Colors import needed):

```julia
# Two-color overlay using symbols
result = render([smld_channel1, smld_channel2],
                colors = [:red, :green],
                strategy = GaussianRender(),
                zoom = 20,
                filename = "overlay.png")

# Three-color overlay
result = render([smld1, smld2, smld3],
                colors = [:red, :green, :blue],
                zoom = 20,
                filename = "three_color.png")
```

Each channel is:
1. Rendered independently
2. Normalized (Gaussian) or saturates (Circles/Histogram)
3. Combined additively
4. Clipped to white where saturated

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

Use `list_recommended_colormaps()` to see all options.

## Related Packages

- [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) - Data structures for SMLM
- [SMLMVis.jl](https://github.com/JuliaSMLM/SMLMVis.jl) - Interactive visualization
- [SMLMMetrics.jl](https://github.com/JuliaSMLM/SMLMMetrics.jl) - Analysis and metrics

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - see LICENSE file