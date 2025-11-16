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

# Simple rendering with inferno colormap
img = render(smld, colormap=:inferno, zoom=20)

# Color by z-depth with viridis
img = render(smld, color_by=:z, colormap=:viridis, pixel_size=10.0)

# Gaussian rendering with localization precision
img = render(smld,
    strategy=GaussianRender(n_sigmas=3.0, use_localization_precision=true),
    colormap=:hot,
    zoom=15)

# Circle rendering to show localization precision
img = render(smld,
    strategy=CircleRender(radius_factor=2.0, line_width=1.0),
    color_by=:photons,
    colormap=:plasma)

# Two-color overlay (e.g., red/green STORM)
img = render_overlay([smld_protein1, smld_protein2],
                     [colorant"red", colorant"green"],
                     zoom=20)
```

## Rendering Strategies

### Histogram Rendering

Fastest option. Bins localizations into pixels.

```julia
img = render(smld, strategy=HistogramRender(), zoom=20)
```

### Gaussian Rendering

Renders each localization as a 2D Gaussian blob.

```julia
# Use localization precision (σ_x, σ_y from data)
strategy = GaussianRender(
    n_sigmas=3.0,                    # Render ±3σ
    use_localization_precision=true,
    fixed_sigma=nothing,
    normalization=:integral          # :integral or :maximum
)

# Or use fixed sigma
strategy = GaussianRender(
    n_sigmas=3.0,
    use_localization_precision=false,
    fixed_sigma=20.0,  # 20 nm
    normalization=:integral
)

img = render(smld, strategy=strategy, zoom=15)
```

### Circle Rendering

Renders circles at localization precision (useful for visualizing uncertainty).

```julia
# 2σ circles
strategy = CircleRender(
    radius_factor=2.0,  # Multiply σ by 2
    line_width=1.0,     # Line thickness in pixels
    use_localization_precision=true,
    fixed_radius=nothing
)

img = render(smld, strategy=strategy, color_by=:z, colormap=:viridis)
```

## Color Mapping

### Intensity Colormaps

Traditional SMLM: accumulate intensity → apply colormap.

```julia
# Just specify colormap
img = render(smld, colormap=:inferno, zoom=20)

# Available colormaps: :inferno, :hot, :viridis, :plasma, :magma, :turbo, etc.
# See ColorSchemes.jl for full list
```

### Field-Based Colormaps

Color each localization by a field value (z, photons, frame, etc.).

```julia
# Color by z-depth
img = render(smld, color_by=:z, colormap=:viridis, zoom=20)

# Color by photon count
img = render(smld, color_by=:photons, colormap=:inferno, pixel_size=10.0)

# Color by frame number (time series)
img = render(smld, color_by=:frame, colormap=:twilight, zoom=15)

# Color by localization precision (quality)
img = render(smld, color_by=:σ_x, colormap=:plasma, zoom=20)
```

### Manual Colors

Fixed color for all localizations (useful for overlays).

```julia
img = render(smld, color=colorant"red", zoom=20)
```

## Multi-Channel Rendering

For two-color or multi-color imaging:

```julia
# Two-color overlay
img = render_overlay([smld_channel1, smld_channel2],
                     [colorant"red", colorant"green"],
                     strategy=GaussianRender(),
                     zoom=20)

# Three-color overlay
img = render_overlay([smld1, smld2, smld3],
                     [:red, :green, :blue],
                     zoom=15)
```

Each channel is:
1. Rendered independently
2. Normalized to [0, 1] based on its own intensity distribution
3. Combined additively
4. Clipped to white where saturated

## Recommended Colormaps

### Sequential (for single-valued fields)
- `:viridis` - Perceptually uniform, colorblind-safe (default)
- `:cividis` - Optimized for colorblind viewers
- `:inferno`, `:magma`, `:plasma` - Matplotlib perceptual maps
- `:turbo` - Google's improved rainbow
- `:hot` - Classic SMLM colormap

### Diverging (for fields with meaningful center)
- `:RdBu` - Red-blue
- `:seismic` - Blue-white-red

### Cyclic (for periodic fields like angles)
- `:twilight` - Perceptually uniform cyclic

Use `list_recommended_colormaps()` to see all recommendations.

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