# SMLMRender.jl

Rendering for Single Molecule Localization Microscopy (SMLM) data.

**Part of the [JuliaSMLM](https://github.com/JuliaSMLM) ecosystem.**

SMLMRender.jl transforms SMLM localization data from [SMLMData.jl](https://github.com/JuliaSMLM/SMLMData.jl) into images. It provides multiple rendering strategies, intensity-weighted field coloring, and PNG export.

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

This tutorial simulates a small super-resolution structure and demonstrates key rendering features.

```@example quickstart
using SMLMData, SMLMRender, SMLMSim, MicroscopePSFs

# Simulate a small octamer structure (16×16 pixel FOV, ~1.6μm)
params = StaticSMLMParams(
    density = 50.0,      # High density for clear structure
    σ_psf = 0.13,        # 130nm PSF (typical STORM)
    nframes = 5,         # Short acquisition
    framerate = 20.0
)

camera = IdealCamera(16, 16, 0.1)  # 16×16 pixels, 100nm/px
pattern = Nmer2D(n=8, d=0.5)       # Octamer, 500nm diameter
fluor = GenericFluor(photons=2000.0, k_off=10.0, k_on=0.5)

smld_true, smld_model, smld = simulate(params; pattern, molecule=fluor, camera)
println("Simulated $(length(smld.emitters)) localizations")
```

### Rendering Strategies

```@example quickstart
# Histogram: Fast binning (pixelated but fast)
hist_result = render(smld, strategy=HistogramRender(), zoom=10)

# Gaussian: Smooth blobs
gauss_result = render(smld, strategy=GaussianRender(), zoom=10)

# Circle: Visualize localization precision
circle_result = render(smld, strategy=CircleRender(), zoom=20)

println("Histogram: $(size(hist_result.image))")
println("Gaussian: $(size(gauss_result.image))")
println("Circle: $(size(circle_result.image))")
```

### Color Mapping

```@example quickstart
# Intensity-based coloring (traditional SMLM)
intensity_result = render(smld, colormap=:inferno, zoom=10)

# Field-based coloring (color by photon count)
field_result = render(smld, color_by=:photons, colormap=:viridis, zoom=10)

println("Rendered with intensity and field-based coloring")
```

## Documentation Structure

- [Examples](@ref) - Detailed usage examples for all rendering modes
- [API Reference](@ref) - Complete API documentation

## Main Interface

```@example quickstart
# Single-channel rendering
result = render(smld, zoom=10)

# Multi-channel rendering (no Colors import needed)
# result = render([smld1, smld2], colors=[:red, :green], zoom=10)

# Export utilities
# export_colorbar(result, "colorbar.png")
# save_image("output.png", result.image)
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
