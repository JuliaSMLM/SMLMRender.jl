# Examples

This page provides comprehensive examples for all rendering modes in SMLMRender.jl.

## Basic Usage

### Simple Intensity Rendering

The simplest way to render SMLM data is with intensity-based colormapping:

```julia
using SMLMData, SMLMRender

# Load SMLM data
smld = load_smld("data.h5")

# Render with default settings (GaussianRender, :inferno colormap)
result = render(smld, zoom=20, filename="output.png")

# Access the image
img = result.image  # Matrix{RGB{Float64}}

# Check rendering metadata
println("Rendered $(result.n_localizations) localizations in $(result.render_time) seconds")
```

### Custom Colormap

Choose from many available colormaps:

```julia
# Classic SMLM hot colormap (black → red → yellow → white)
result = render(smld, colormap=:hot, zoom=20, filename="hot.png")

# Inferno colormap (black → purple → orange → yellow)
result = render(smld, colormap=:inferno, zoom=20, filename="inferno.png")

# Magma colormap (black → purple → pink → yellow)
result = render(smld, colormap=:magma, zoom=20, filename="magma.png")
```

### Pixel Size vs Zoom

You can specify the output resolution either by pixel size (in nm) or by zoom factor:

```julia
# Specify pixel size directly (10 nm per pixel)
result = render(smld, pixel_size=10.0, colormap=:inferno, filename="10nm.png")

# Or specify zoom relative to camera pixels
result = render(smld, zoom=20, colormap=:inferno, filename="zoom20.png")
```

## Rendering Strategies

### Histogram Rendering

Fast binning-based rendering. Best for quick visualization and high-density data.

```julia
# Basic histogram rendering
result = render(smld, 
    strategy = HistogramRender(),
    colormap = :inferno,
    zoom = 10,
    filename = "histogram.png")

# Characteristics:
# - Fastest rendering
# - No sub-pixel accuracy
# - Saturates on overlap (bright, punchy colors)
# - Black background
```

### Gaussian Rendering

Renders each localization as a smooth 2D Gaussian blob. Publication-quality rendering.

```julia
# Gaussian rendering with localization precision
result = render(smld,
    strategy = GaussianRender(
        n_sigmas = 3.0,                      # Render out to 3σ
        use_localization_precision = true,   # Use σ_x, σ_y from data
        normalization = :integral            # Gaussians sum to 1
    ),
    colormap = :hot,
    zoom = 20,
    filename = "gaussian_precision.png")

# Fixed sigma rendering (all localizations same width)
result = render(smld,
    strategy = GaussianRender(
        n_sigmas = 3.0,
        use_localization_precision = false,
        fixed_sigma = 15.0,                  # 15 nm sigma
        normalization = :integral
    ),
    colormap = :inferno,
    zoom = 20,
    filename = "gaussian_fixed.png")

# Maximum normalization (peak = 1 instead of integral = 1)
result = render(smld,
    strategy = GaussianRender(
        n_sigmas = 2.5,
        use_localization_precision = true,
        normalization = :maximum             # Peak value = 1
    ),
    colormap = :hot,
    zoom = 20,
    filename = "gaussian_maximum.png")
```

### Circle Rendering

Renders each localization as a circle outline. Useful for visualizing uncertainty.

```julia
# 1σ circles (recommended)
result = render(smld,
    strategy = CircleRender(
        radius_factor = 1.0,                 # 1σ radius
        line_width = 1.0,                    # 1 pixel line width
        use_localization_precision = true    # Use σ from data
    ),
    colormap = :plasma,
    zoom = 50,                               # High zoom for visibility
    filename = "circles_1sigma.png")

# 2σ circles with thicker lines
result = render(smld,
    strategy = CircleRender(
        radius_factor = 2.0,                 # 2σ radius
        line_width = 2.5,                    # Thicker lines
        use_localization_precision = true
    ),
    colormap = :viridis,
    zoom = 40,
    filename = "circles_2sigma.png")

# Fixed radius circles
result = render(smld,
    strategy = CircleRender(
        radius_factor = 1.0,
        line_width = 1.0,
        use_localization_precision = false,
        fixed_radius = 20.0                  # 20 nm radius
    ),
    colormap = :turbo,
    zoom = 50,
    filename = "circles_fixed.png")
```

## Field-Based Coloring

Color each localization by a field value (z-depth, photons, frame, etc.).

### Color by Z-Depth

```julia
# Color by z-depth (default turbo colormap)
result = render(smld,
    color_by = :z,
    zoom = 20,
    filename = "z_depth.png")

# With custom colormap
result = render(smld,
    color_by = :z,
    colormap = :plasma,
    zoom = 20,
    filename = "z_plasma.png")

# Export colorbar with auto-extracted metadata
export_colorbar(result, "z_colorbar.png")

# Diverging colormap for ±z around focal plane
result = render(smld,
    color_by = :z,
    colormap = :RdBu,
    zoom = 20,
    filename = "z_diverging.png")
```

### Color by Photons

```julia
# Color by photon count
result = render(smld,
    color_by = :photons,
    colormap = :viridis,
    zoom = 20,
    filename = "photons.png")

# Export colorbar
export_colorbar(result, "photons_colorbar.png")
```

### Color by Frame (Temporal Dynamics)

```julia
# Color by frame number (temporal information)
result = render(smld,
    color_by = :frame,
    colormap = :twilight,                    # Cyclic colormap
    zoom = 20,
    filename = "temporal.png")
```

### Color by Localization Precision

```julia
# Color by σ_x (localization precision)
result = render(smld,
    color_by = :σ_x,
    colormap = :plasma,
    zoom = 20,
    filename = "precision.png")
```

### Advanced Field Coloring Options

```julia
# Explicit field value range
result = render(smld,
    color_by = :z,
    colormap = :turbo,
    field_range = (-500.0, 500.0),           # Fixed range in nm
    zoom = 20,
    filename = "z_fixed_range.png")

# Custom percentile clipping
result = render(smld,
    color_by = :photons,
    colormap = :viridis,
    field_clip_percentiles = (0.05, 0.95),   # Clip outliers
    zoom = 20,
    filename = "photons_clipped.png")

# Auto range with clipping (default)
result = render(smld,
    color_by = :z,
    colormap = :plasma,
    field_range = :auto,                     # Auto-detect range
    field_clip_percentiles = (0.01, 0.99),   # Default clipping
    zoom = 20,
    filename = "z_auto.png")
```

## Multi-Channel Rendering

Render multiple datasets with different colors and overlay them.

### Two-Color Overlay

```julia
# Load two channels
smld_protein1 = load_smld("channel1.h5")
smld_protein2 = load_smld("channel2.h5")

# Two-color overlay using dispatch (no Colors import needed!)
result = render([smld_protein1, smld_protein2],
                colors = [:red, :green],
                strategy = GaussianRender(),
                zoom = 20,
                filename = "two_color.png")

# Each channel is:
# 1. Rendered independently
# 2. Normalized to [0, 1]
# 3. Combined additively
# 4. Clipped to white where saturated
```

### Three-Color Overlay

```julia
# Three-color overlay
smld1 = load_smld("channel1.h5")
smld2 = load_smld("channel2.h5")
smld3 = load_smld("channel3.h5")

result = render([smld1, smld2, smld3],
                colors = [:red, :green, :blue],
                strategy = GaussianRender(),
                zoom = 20,
                filename = "three_color.png")
```

### Custom Colors

```julia
using Colors

# Custom RGB colors
result = render([smld1, smld2],
                colors = [RGB(1.0, 0.0, 0.0), RGB(0.0, 1.0, 1.0)],  # Red and cyan
                zoom = 20,
                filename = "custom_colors.png")

# Named colors (no import needed!)
result = render([smld1, smld2],
                colors = [:magenta, :yellow],
                zoom = 20,
                filename = "magenta_yellow.png")
```

### Multi-Channel with Different Strategies

```julia
# Note: Currently all channels use same strategy
# For different strategies per channel, render separately and combine manually

# Render each channel
result1 = render(smld1, color=colorant"red", strategy=GaussianRender(), zoom=20)
result2 = render(smld2, color=colorant"green", strategy=CircleRender(), zoom=20)

# Manual combination
img_combined = result1.image .+ result2.image
save_image("mixed_strategies.png", img_combined)
```

## Output and Export

### Direct File Save

```julia
# Save directly during rendering
result = render(smld, 
                colormap = :inferno,
                zoom = 20,
                filename = "output.png")

# Or save later
result = render(smld, colormap=:inferno, zoom=20)
save_image("output.png", result.image)
```

### Export Colorbar

```julia
# Easy way: from render result
result = render(smld, color_by=:z, colormap=:turbo, zoom=20)
export_colorbar(result, "colorbar.png")

# Manual way with custom parameters
export_colorbar(:turbo,                      # Colormap
                (-500.0, 500.0),             # Value range
                "Z-depth (nm)",              # Label
                "colorbar.png",              # Filename
                orientation = :vertical,     # :vertical or :horizontal
                size = (80, 400),            # (width, height) in pixels
                fontsize = 14,               # Label font size
                tickfontsize = 12)           # Tick font size

# Horizontal colorbar
export_colorbar(result, "colorbar_horiz.png",
                orientation = :horizontal,
                size = (400, 80))
```

### Access Result Metadata

```julia
result = render(smld, color_by=:z, colormap=:turbo, zoom=20)

# Access various fields
println("Image size: ", size(result.image))
println("Number of localizations: ", result.n_localizations)
println("Render time: ", result.render_time, " seconds")
println("Pixel size: ", result.target.pixel_size, " nm")
println("Field value range: ", result.field_value_range)

# Access render options used
println("Strategy: ", typeof(result.options.strategy))
println("Color mapping: ", typeof(result.options.color_mapping))
```

## Custom Targets

### Explicit Pixel Edges

```julia
# Define custom pixel edges
x_edges = range(0.0, 10.0, length=201)  # 200 pixels, 0-10 μm
y_edges = range(0.0, 10.0, length=201)

result = render(smld, x_edges, y_edges,
                strategy = GaussianRender(),
                colormap = :inferno,
                filename = "custom_edges.png")
```

### Manual Target Creation

```julia
# Create target manually
target = Image2DTarget(
    512,                        # width in pixels
    512,                        # height in pixels
    10.0,                       # pixel size in nm
    (0.0, 5.12),               # x range in μm
    (0.0, 5.12)                # y range in μm
)

result = render(smld,
                target = target,
                strategy = GaussianRender(),
                colormap = :hot,
                filename = "manual_target.png")
```

## Performance Tips

### Memory Estimation

```julia
using SMLMRender

# Estimate memory usage for rendering
n_locs = length(smld.emitters)
width = 512
height = 512
strategy = GaussianRender()

mem_bytes = estimate_memory_usage(n_locs, width, height, strategy)
mem_gb = mem_bytes / 1024^3
println("Estimated memory: ", mem_gb, " GB")
```

### Backend Selection

```julia
# CPU backend (default)
result = render(smld, backend=:cpu, zoom=20)

# Auto backend selection (future: may select GPU if available)
result = render(smld, backend=:auto, zoom=20)

# Note: CUDA and Metal backends planned for future releases
```

### Large Dataset Rendering

```julia
# For very large datasets, use HistogramRender for speed
result = render(smld,
                strategy = HistogramRender(),
                colormap = :hot,
                zoom = 10,
                filename = "large_dataset.png")

# Or reduce zoom factor to reduce output size
result = render(smld,
                strategy = GaussianRender(),
                colormap = :inferno,
                zoom = 5,                    # Lower zoom = smaller output
                filename = "large_lowzoom.png")
```

## Available Colormaps

Get a list of recommended colormaps:

```julia
colormaps = list_recommended_colormaps()

# View by category
println("Sequential: ", colormaps[:sequential])
println("Diverging: ", colormaps[:diverging])
println("Cyclic: ", colormaps[:cyclic])
println("Perceptual: ", colormaps[:perceptual])
```

Output:
```
Sequential: [:viridis, :cividis, :inferno, :magma, :plasma, :turbo, :hot]
Diverging: [:RdBu, :seismic, :coolwarm]
Cyclic: [:twilight, :phase]
Perceptual: [:viridis, :cividis, :inferno, :magma, :plasma]
```

## Common Workflows

### Quick Data Check

```julia
# Quick low-resolution preview
result = render(smld, zoom=5, colormap=:hot, filename="preview.png")
```

### Publication Figure

```julia
# High-quality Gaussian rendering for publication
result = render(smld,
                strategy = GaussianRender(
                    n_sigmas = 3.0,
                    use_localization_precision = true,
                    normalization = :integral
                ),
                colormap = :inferno,
                zoom = 30,                   # High zoom for detail
                filename = "publication.png")
```

### Uncertainty Visualization

```julia
# Show localization precision with circles
result = render(smld,
                strategy = CircleRender(
                    radius_factor = 1.0,     # 1σ circles
                    line_width = 1.0,
                    use_localization_precision = true
                ),
                color_by = :σ_x,            # Color by precision
                colormap = :plasma,
                zoom = 50,
                filename = "uncertainty.png")
```

### 3D Depth Encoding

```julia
# Encode z-depth in color
result = render(smld,
                strategy = GaussianRender(),
                color_by = :z,
                colormap = :turbo,
                zoom = 20,
                filename = "3d_depth.png")

# Export colorbar showing depth scale
export_colorbar(result, "depth_scale.png")
```

### Temporal Dynamics

```julia
# Show acquisition time via frame coloring
result = render(smld,
                strategy = GaussianRender(),
                color_by = :frame,
                colormap = :twilight,        # Cyclic for temporal
                zoom = 20,
                filename = "temporal.png")
```
