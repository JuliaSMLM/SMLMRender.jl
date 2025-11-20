# SMLMRender.jl

Rendering for Single Molecule Localization Microscopy (SMLM) data.

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaSMLM.github.io/SMLMRender.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaSMLM.github.io/SMLMRender.jl/dev/)
[![Build Status](https://github.com/JuliaSMLM/SMLMRender.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaSMLM/SMLMRender.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaSMLM/SMLMRender.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaSMLM/SMLMRender.jl)

Part of the [JuliaSMLM](https://github.com/JuliaSMLM) ecosystem.

## Installation

```julia
using Pkg
Pkg.add("SMLMRender")
```

## Usage

```julia
using SMLMData, SMLMRender

# Load data
smld = load_smld("data.h5")

# Render with intensity colormap (zoom=20 means 20 output pixels per camera pixel)
render(smld, colormap=:inferno, zoom=20, filename="output.png")

# Render colored by z-depth
render(smld, color_by=:z, colormap=:turbo, zoom=20, filename="depth.png")

# Multi-channel overlay
render([smld1, smld2], colors=[:red, :green], zoom=20, filename="overlay.png")
```

### Output Resolution

Two ways to specify output resolution:

```julia
# zoom: Renders exact camera FOV with subdivided pixels
# - 128×128 camera with zoom=10 → exactly 1280×1280 output
# - Output range matches camera FOV exactly
render(smld, zoom=10)

# pixel_size: Uses data bounds with margin (variable output size)
# - Output size depends on where localizations fell
# - Useful for cropping to specific regions
render(smld, pixel_size=10.0)  # 10nm per pixel
```

### Rendering Strategies

```julia
# Histogram (binning)
render(smld, strategy=HistogramRender(), zoom=10)

# Gaussian (smooth blobs)
render(smld, strategy=GaussianRender(), zoom=20)

# Circles (localization precision)
render(smld, strategy=CircleRender(radius_factor=1.0, line_width=1.0), zoom=50)
```

### Color Mapping

```julia
# Intensity-based
render(smld, colormap=:inferno)

# Field-based (z-depth, photons, frame, etc.)
render(smld, color_by=:z, colormap=:turbo)
render(smld, color_by=:photons, colormap=:plasma)
render(smld, color_by=:frame, colormap=:twilight)
```

## Documentation

See the [documentation](https://JuliaSMLM.github.io/SMLMRender.jl/dev/) for details.

## Related Packages

- [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) - SMLM data structures
- [SMLMVis.jl](https://github.com/JuliaSMLM/SMLMVis.jl) - Interactive visualization
- [SMLMMetrics.jl](https://github.com/JuliaSMLM/SMLMMetrics.jl) - Analysis and metrics

## License

MIT License
