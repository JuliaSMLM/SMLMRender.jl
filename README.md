# SMLMRender

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaSMLM.github.io/SMLMRender.jl/stable/)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaSMLM.github.io/SMLMRender.jl/dev/)
[![Build Status](https://github.com/JuliaSMLM/SMLMRender.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/JuliaSMLM/SMLMRender.jl/actions/workflows/CI.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/JuliaSMLM/SMLMRender.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaSMLM/SMLMRender.jl)

Rendering single molecule localization microscopy (SMLM) data into images. Converts point-cloud localizations into 2D images using histogram binning, Gaussian blob rendering, or circle/ellipse outlines, with flexible color mapping by intensity, emitter field values, or categorical labels.

## Installation

```julia
using Pkg
Pkg.add("SMLMRender")
```

## Concepts

SMLM experiments produce lists of localization coordinates (x, y, and optionally z) with associated uncertainties (σ_x, σ_y) and metadata (photons, frame, id). Rendering converts these sparse point clouds into dense images for visualization and publication.

### Rendering Strategies

Four strategies control *how* each localization appears in the image:

- **Histogram** bins localizations into pixels. Fast, no sub-pixel accuracy. Best for quick previews and dense datasets.
- **Gaussian** renders each localization as a smooth 2D Gaussian blob. When `use_localization_precision=true`, the blob width comes from the emitter's σ_x and σ_y fields (from `EmitterFit` types), giving narrower blobs for high-photon localizations. This is the default strategy.
- **Circle** draws a circle outline at each localization, with radius derived from the localization precision (σ_x). Useful for visualizing uncertainty per localization.
- **Ellipse** draws an ellipse outline using σ_x, σ_y, and σ_xy (covariance) from `EmitterFit` types, showing anisotropic localization precision.

### Color Mapping

Two fundamentally different approaches to color:

- **Intensity-based**: Accumulate Gaussian (or histogram) intensity into a grayscale image, then apply a colormap (`:inferno`, `:hot`, `:viridis`, etc.). Brightness encodes localization density. This is the traditional SMLM rendering approach.
- **Field-based**: Color each localization by a field value *before* rendering. Any numeric field on the emitter type works: `:z` for depth, `:photons` for brightness, `:frame` for temporal dynamics, `:σ_x` for precision, etc. The field value maps through a colormap (e.g., `:turbo`) to produce per-emitter RGB colors, which are then accumulated with intensity weighting.

Additionally: **categorical** coloring assigns distinct palette colors to integer fields like `:id` or cluster labels (e.g., `color_by=:id, categorical=true` to visualize clustering results), and **manual** coloring renders all localizations in a single fixed color (for multi-channel overlays).

### Camera and Resolution

The SMLD dataset carries a camera model that defines the physical field of view. Resolution is specified one of two ways:

- **Zoom mode** (`zoom=N`): Subdivides each camera pixel into N output pixels. A 64x64 camera at `zoom=20` produces exactly 1280x1280 output pixels covering the full camera FOV. This gives predictable, reproducible image sizes. Supports **ROI** to render a subregion: `roi=(x_range, y_range)` specifies camera pixel ranges (e.g., `roi=(20:44, :)` for columns 20-44, full rows).
- **Pixel size mode** (`pixel_size=N`): Sets the output pixel size in nanometers and computes image dimensions from the data bounding box plus margin. Output size varies with data extent.

## Quick Start

```julia
using SMLMRender

# Render with config struct (primary form)
config = RenderConfig(colormap=:inferno, zoom=20)
(img, info) = render(smld, config)

# Render with keyword arguments (convenience form)
(img, info) = render(smld, colormap=:inferno, zoom=20)

# Both forms return (image::Matrix{RGB{Float64}}, info::RenderInfo)
println("$(info.n_emitters_rendered) localizations → $(info.output_size)")
```

For complete SMLM workflows (detection + fitting + frame-connection + rendering), see [SMLMAnalysis.jl](https://github.com/JuliaSMLM/SMLMAnalysis.jl).

## Configuration

`render()` accepts a `RenderConfig` struct or keyword arguments. Config fields match kwargs exactly:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `strategy` | `GaussianRender()` | Rendering algorithm |
| `zoom` | `nothing` | Camera pixel subdivision factor |
| `pixel_size` | `nothing` | Output pixel size in nm |
| `roi` | `nothing` | Camera pixel ROI as `(x_range, y_range)` |
| `colormap` | `nothing` | Intensity colormap (`:inferno`, `:hot`, `:viridis`, etc.) |
| `color_by` | `nothing` | Field for per-emitter coloring (`:z`, `:photons`, `:frame`, etc.) |
| `color` | `nothing` | Manual fixed color (`:red`, `RGB(...)`) |
| `categorical` | `false` | Use categorical palette for integer fields |
| `clip_percentile` | `0.99` | Intensity clipping (percentile of non-zero pixels) |
| `field_range` | `:auto` | Value range for field coloring, or explicit `(min, max)` |
| `field_clip_percentiles` | `(0.01, 0.99)` | Percentile clipping for field range |
| `filename` | `nothing` | Save to file if provided |

```julia
# Config struct (reusable, composable)
config = RenderConfig(
    strategy = GaussianRender(use_localization_precision=true),
    color_by = :z,
    colormap = :turbo,
    zoom = 20
)
(img, info) = render(smld, config)

# Keyword form (most common for one-off renders)
(img, info) = render(smld, color_by=:z, colormap=:turbo, zoom=20)
```

### Strategy Options

| Strategy | Key Parameters | Description |
|----------|---------------|-------------|
| `HistogramRender()` | none | Bin localizations per pixel |
| `GaussianRender()` | `use_localization_precision`, `n_sigmas`, `normalization` | 2D Gaussian blobs from σ_x, σ_y |
| `CircleRender()` | `radius_factor`, `line_width`, `use_localization_precision` | Circle outlines at σ_x radius |
| `EllipseRender()` | `radius_factor`, `line_width`, `use_localization_precision` | Ellipse outlines from σ_x, σ_y, σ_xy |

```julia
# Gaussian blobs using localization precision from EmitterFit fields
(img, info) = render(smld, strategy=GaussianRender(use_localization_precision=true), zoom=20)

# Fixed 20nm sigma for all localizations
(img, info) = render(smld, strategy=GaussianRender(use_localization_precision=false, fixed_sigma=20.0), zoom=20)

# 2-sigma circle outlines
(img, info) = render(smld, strategy=CircleRender(radius_factor=2.0), color_by=:z, zoom=50)

# Ellipse outlines showing anisotropic precision
(img, info) = render(smld, strategy=EllipseRender(), color_by=:frame, colormap=:turbo, zoom=50)
```

## Output Format

`render()` returns `(image::Matrix{RGB{Float64}}, info::RenderInfo)`.

| RenderInfo Field | Description |
|-----------------|-------------|
| `elapsed_s` | Wall time (seconds) |
| `n_emitters_rendered` | Number of emitters rendered |
| `output_size` | `(height, width)` of output image |
| `pixel_size_nm` | Output pixel size in nanometers |
| `strategy` | Rendering algorithm (`:gaussian`, `:histogram`, `:circle`, `:ellipse`) |
| `color_mode` | Color mapping (`:intensity`, `:field`, `:categorical`, `:manual`) |
| `field_range` | Value range for colorbar (field/categorical modes) |

```julia
(img, info) = render(smld, color_by=:z, colormap=:turbo, zoom=20)
save_image("output.png", img)

# Use field_range for colorbar annotation
export_colorbar(:turbo, info.field_range, "Z-depth (um)", "colorbar.png")
```

## Multi-Channel Rendering

Render multiple datasets with different colors and overlay them additively:

```julia
# Two-color overlay (no Colors import needed)
(img, info) = render([smld1, smld2],
                     colors = [:red, :green],
                     strategy = GaussianRender(),
                     zoom = 20)

# Three-color with custom RGB
using Colors
(img, info) = render([smld1, smld2, smld3],
                     colors = [RGB(1,0,0), RGB(0,1,0), RGB(0,0,1)],
                     zoom = 20)
```

Each channel is rendered independently, normalized, and combined. Saturated regions clip to white.

## Coordinate System

Physical coordinates in micrometers (um). Pixel sizes specified in nanometers (nm). Pixel (1.0, 1.0) is center of top-left pixel.

## Related Packages

- **[SMLMAnalysis.jl](https://github.com/JuliaSMLM/SMLMAnalysis.jl)** - Complete SMLM workflow (detection + fitting + frame-connection + rendering)
- **[SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl)** - Core data types for SMLM (emitter types, camera models)
- **[SMLMFrameConnection.jl](https://github.com/JuliaSMLM/SMLMFrameConnection.jl)** - Frame-connection for repeated localizations
- **[GaussMLE.jl](https://github.com/JuliaSMLM/GaussMLE.jl)** - GPU-accelerated Gaussian PSF fitting
- **[SMLMSim.jl](https://github.com/JuliaSMLM/SMLMSim.jl)** - SMLM data simulation
- **[MicroscopePSFs.jl](https://github.com/JuliaSMLM/MicroscopePSFs.jl)** - PSF models

## License

MIT License - see [LICENSE](LICENSE) file for details.
