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

# Render returns (image, info) tuple
(img, info) = render(smld, colormap=:inferno, zoom=20)
save_image("output.png", img)

# Access metadata
@show info.elapsed_ns / 1e9  # render time in seconds
@show info.n_emitters_rendered
@show info.output_size

# Render colored by z-depth
(img, info) = render(smld, color_by=:z, colormap=:turbo, zoom=20)
@show info.field_range  # value range for colorbar

# Just get image (discard info)
img, _ = render(smld, zoom=20, filename="output.png")

# Multi-channel overlay
(img, info) = render([smld1, smld2], colors=[:red, :green], zoom=20)
```

### Output Resolution

Two ways to specify output resolution:

```julia
# zoom: Renders exact camera FOV with subdivided pixels
# - 128×128 camera with zoom=10 → exactly 1280×1280 output
# - Output range matches camera FOV exactly
(img, info) = render(smld, zoom=10)
@show info.output_size  # (1280, 1280)

# pixel_size: Uses data bounds with margin (variable output size)
# - Output size depends on where localizations fell
# - Useful for cropping to specific regions
(img, info) = render(smld, pixel_size=10.0)  # 10nm per pixel
@show info.pixel_size_nm  # 10.0

# roi: Render a subset of the camera FOV (only with zoom mode)
# - Specify camera pixel ranges as (x_range, y_range)
# - Use : for full range on an axis
(img, info) = render(smld, zoom=20, roi=(430:860, :))  # x pixels 430-860, full y
```

### Rendering Strategies

```julia
# Histogram (binning)
(img, info) = render(smld, strategy=HistogramRender(), zoom=10)
@show info.strategy  # :histogram

# Gaussian (smooth blobs)
(img, info) = render(smld, strategy=GaussianRender(), zoom=20)
@show info.strategy  # :gaussian

# Circles (localization precision)
(img, info) = render(smld, strategy=CircleRender(radius_factor=1.0, line_width=1.0), zoom=50)
@show info.strategy  # :circle
```

### Color Mapping

```julia
# Intensity-based
(img, info) = render(smld, colormap=:inferno, zoom=20)
@show info.color_mode  # :intensity

# Field-based (z-depth, photons, frame, etc.)
(img, info) = render(smld, color_by=:z, colormap=:turbo, zoom=20)
@show info.color_mode  # :field
@show info.field_range  # (min_z, max_z) for colorbar
```

## Documentation

See the [documentation](https://JuliaSMLM.github.io/SMLMRender.jl/dev/) for details.

## Related Packages

- [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) - SMLM data structures
- [SMLMVis.jl](https://github.com/JuliaSMLM/SMLMVis.jl) - Interactive visualization
- [SMLMMetrics.jl](https://github.com/JuliaSMLM/SMLMMetrics.jl) - Analysis and metrics

## License

MIT License
