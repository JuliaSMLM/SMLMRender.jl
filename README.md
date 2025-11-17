# SMLMRender.jl

High-performance rendering for Single Molecule Localization Microscopy (SMLM) data.

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaSMLM.github.io/SMLMRender.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaSMLM.github.io/SMLMRender.jl/dev/)
[![Build Status](https://github.com/JuliaSMLM/SMLMRender.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaSMLM/SMLMRender.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaSMLM/SMLMRender.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaSMLM/SMLMRender.jl)

SMLMRender.jl is a focused, GPU-ready package for rendering SMLM localization data into 2D images and (future) 3D visualizations. It provides clean, Julian APIs with multiple rendering strategies and flexible color mapping.

## Features

### Rendering Strategies (Phase 1 ✓)

- **HistogramRender**: Fast binning-based rendering
  - Each pixel counts localizations
  - No sub-pixel accuracy, but very fast

- **GaussianRender**: Smooth Gaussian blob rendering
  - Sub-pixel accuracy
  - Publication-quality images
  - Uses localization precision (σ_x, σ_y) or fixed sigma

- **CircleRender**: Circle outline rendering
  - Visualize localization precision
  - Anti-aliased circles at 1σ, 2σ, etc.

### Color Mapping

- **Intensity colormaps**: Traditional SMLM rendering (inferno, hot, viridis, etc.)
- **Field-based coloring**: Color by any EmitterFit field (z-depth, photons, frame, σ_x, etc.)
- **Manual colors**: Fixed colors for multi-channel overlays
- **Perceptual colormaps**: Built-in support for ColorSchemes.jl

### Multi-Channel Support

- `render_overlay()` for two-color, three-color, etc. imaging
- Each channel normalized independently
- Additive blending with white saturation clipping

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/JuliaSMLM/SMLMRender.jl")
```

## Quick Start

```julia
using SMLMData, SMLMRender

# Load data
smld = load_smld("data.h5")

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

## Architecture

```
SMLMRender.jl/
├── types.jl              # Type definitions
├── utils.jl              # Coordinate transforms, utilities
├── color/
│   └── mapping.jl        # Color mapping functions
├── render/
│   ├── histogram.jl      # Histogram rendering
│   ├── gaussian.jl       # Gaussian blob rendering
│   └── circle.jl         # Circle outline rendering
└── interface.jl          # Main render() API
```

## Future Work

### Phase 2: GPU Acceleration
- CUDA backend for NVIDIA GPUs
- KernelAbstractions.jl for portable GPU code
- 10-100× speedup target

### Phase 3: 3D Rendering
- Volumetric rendering (3D Gaussian blobs)
- Projection rendering (orthographic, perspective, MIP)
- Point cloud export for Makie.jl

### Phase 4: Advanced Features
- Fly-through animations
- Interactive 3D viewer
- Tiled rendering for gigapixel images

## Design Principles

1. **Julian**: Multiple dispatch, type stability, composability
2. **Performance**: GPU-ready, multi-threaded, memory efficient
3. **Flexibility**: Multiple strategies, color mappings, output formats
4. **Extensibility**: Easy to add new rendering strategies and color schemes

## Related Packages

- [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) - Data structures for SMLM
- [SMLMVis.jl](https://github.com/JuliaSMLM/SMLMVis.jl) - Interactive visualization
- [SMLMMetrics.jl](https://github.com/JuliaSMLM/SMLMMetrics.jl) - Analysis and metrics

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT License - see LICENSE file