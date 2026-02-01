# Examples

Examples for rendering modes in SMLMRender.jl.

## Setup: Simulated Data

All examples below use this simulated dataset:

```@setup examples
using SMLMData, SMLMRender, SMLMSim, MicroscopePSFs
using Colors

# Compact FOV to see fine details
params = StaticSMLMParams(
    density = 2.0,               # 2 patterns per μm²
    σ_psf = 0.13,                # 130nm PSF width
    nframes = 20,                # 2x frames for 2x localizations per emitter
    framerate = 20.0,
    ndims = 3,                   # Enable 3D for z-depth examples
    zrange = [-0.5, 0.5]         # ±500nm z-range
)

camera = IdealCamera(16, 16, 0.1)    # 16×16 pixels, 100nm/pixel = 1.6μm FOV
pattern = Nmer3D(n=8, d=0.15)        # Octamer, 150nm diameter
fluor = GenericFluor(photons=1000.0, k_off=10.0, k_on=0.5)  # 1000 photons/localization

smld_true, smld_model, smld_noisy = simulate(params; pattern, molecule=fluor, camera)
smld = smld_noisy  # Use noisy localizations (realistic)

# Helper to clamp RGB values for saving (saturating strategies can exceed 1.0)
clamp_rgb(img) = map(px -> RGB(clamp(px.r, 0, 1), clamp(px.g, 0, 1), clamp(px.b, 0, 1)), img)
```

```@example examples
n_pixels = length(camera.pixel_edges_x) - 1
pixel_size_um = camera.pixel_edges_x[2] - camera.pixel_edges_x[1]
fov_um = n_pixels * pixel_size_um
println("Dataset: $(length(smld.emitters)) localizations")
println("Field of view: $(round(fov_um, digits=2))μm × $(round(fov_um, digits=2))μm")
```

## Basic Usage

### Simple Intensity Rendering

The simplest way to render SMLM data is with intensity-based colormapping:

```@example examples
using FileIO # hide

# Render with default settings (GaussianRender, :inferno colormap)
# Returns (image, info) tuple
(img, info) = render(smld, zoom=20)

# img is the rendered image: Matrix{RGB{Float64}}
# info is RenderInfo with metadata

# Check rendering metadata
println("Rendered $(info.n_emitters_rendered) localizations")
println("Image size: $(info.output_size)")
println("Render time: $(round(info.elapsed_ns / 1e6, digits=1)) ms")
println("Strategy: $(info.strategy), Color mode: $(info.color_mode)")

# Save and display
save("basic_render.png", img) # hide
nothing # hide
```

![Basic rendering with default settings](basic_render.png)

### Custom Colormap

Choose from many available colormaps:

```@example examples
# Classic SMLM hot colormap (black → red → yellow → white)
(img_hot, _) = render(smld, colormap=:hot, zoom=20)
save("colormap_hot.png", img_hot) # hide

# Inferno colormap (black → purple → orange → yellow)
(img_inferno, _) = render(smld, colormap=:inferno, zoom=20)
save("colormap_inferno.png", img_inferno) # hide

# Magma colormap (black → purple → pink → yellow)
(img_magma, _) = render(smld, colormap=:magma, zoom=20)
save("colormap_magma.png", img_magma) # hide

println("Rendered with 3 different colormaps")
nothing # hide
```

| Hot | Inferno | Magma |
|:---:|:---:|:---:|
| ![Hot colormap](colormap_hot.png) | ![Inferno colormap](colormap_inferno.png) | ![Magma colormap](colormap_magma.png) |

### Pixel Size vs Zoom

Two modes for controlling output resolution:

**zoom**: Renders exact camera FOV with `camera_pixels × zoom` output
- `zoom=20` with 16×16 camera → exactly 320×320 pixels
- Output range = camera FOV (no cropping)
- Predictable, reproducible sizes

**pixel_size**: Uses data bounds with margin (variable size)
- Output crops to where localizations fell
- Size depends on data distribution
- Specify in nm

```@example examples
# zoom: Exact camera FOV (16×16 camera → 320×320 output)
(img_zoom, info_zoom) = render(smld, zoom=20, colormap=:inferno)
println("Zoom (camera FOV): $(info_zoom.output_size)")
println("  Pixel size: $(info_zoom.pixel_size_nm) nm")

# pixel_size: Data bounds + margin (variable size)
(img_px, info_px) = render(smld, pixel_size=5.0, colormap=:inferno)
println("Pixel size (data bounds): $(info_px.output_size)")
println("  Pixel size: $(info_px.pixel_size_nm) nm")
```

## Rendering Strategies

### Histogram Rendering

Fast binning-based rendering.

```@example examples
# Histogram with time coloring (color by frame number)
(img_hist, info_hist) = render(smld,
    strategy = HistogramRender(),
    color_by = :frame,           # Temporal dynamics
    colormap = :turbo,           # High contrast for time
    zoom = 20)

save("strategy_histogram.png", clamp_rgb(img_hist)) # hide
println("Histogram render: $(info_hist.output_size), strategy=$(info_hist.strategy)")
nothing # hide
```

![Histogram rendering with time coloring](strategy_histogram.png)

### Gaussian Rendering

Renders each localization as a smooth 2D Gaussian blob.

```@example examples
# Gaussian with localization precision (uses σ_x, σ_y from data)
(img_gauss, info_gauss) = render(smld,
    strategy = GaussianRender(
        n_sigmas = 3.0,                      # Render out to 3σ
        use_localization_precision = true,
        normalization = :integral            # Gaussians sum to 1
    ),
    colormap = :hot,
    zoom = 20)

save("strategy_gaussian.png", img_gauss) # hide
println("Gaussian render: $(info_gauss.output_size), strategy=$(info_gauss.strategy)")
nothing # hide
```

![Gaussian rendering - smooth blobs](strategy_gaussian.png)

### Circle Rendering

Renders each localization as a circle outline. Useful for visualizing uncertainty.

```@example examples
# 1σ circles with time coloring
(img_circle, info_circle) = render(smld,
    strategy = CircleRender(
        radius_factor = 1.0,                 # 1σ radius
        line_width = 1.0,
        use_localization_precision = true
    ),
    color_by = :frame,                       # Temporal dynamics
    colormap = :turbo,                       # High contrast rainbow
    zoom = 20)

save("strategy_circle.png", clamp_rgb(img_circle)) # hide
println("Circle render: $(info_circle.output_size), strategy=$(info_circle.strategy)")
nothing # hide
```

![Circle rendering with time coloring](strategy_circle.png)

## Field-Based Coloring

Color each localization by a field value (z-depth, photons, frame, etc.).

### Color by Z-Depth

```@example examples
# Color by z-depth (default turbo colormap)
(img_z, info_z) = render(smld, color_by=:z, zoom=20)
println("Z-depth coloring: $(info_z.field_range), mode=$(info_z.color_mode)")
```

### Color by Photons

```@example examples
# Color by photon count
(img_photons, info_photons) = render(smld, color_by=:photons, colormap=:viridis, zoom=20)
println("Photon range: $(info_photons.field_range)")
```

### Color by Frame (Temporal Dynamics)

```@example examples
# Color by frame number (temporal information)
(img_frame, info_frame) = render(smld, color_by=:frame, colormap=:twilight, zoom=20)
println("Frame range: $(info_frame.field_range)")
```

### Color by Localization Precision

```@example examples
# Color by σ_x (localization precision)
(img, info) = render(smld,
    color_by = :σ_x,
    colormap = :plasma,
    zoom = 20,
    filename = "precision.png")
println("Precision range: $(info.field_range)")
```

### Field Coloring Options

```julia
# Explicit field value range
(img, info) = render(smld,
    color_by = :z,
    colormap = :turbo,
    field_range = (-500.0, 500.0),           # Fixed range in nm
    zoom = 20,
    filename = "z_fixed_range.png")

# Custom percentile clipping
(img, info) = render(smld,
    color_by = :photons,
    colormap = :viridis,
    field_clip_percentiles = (0.05, 0.95),   # Clip outliers
    zoom = 20,
    filename = "photons_clipped.png")

# Auto range with clipping (default)
(img, info) = render(smld,
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
# Returns (image, info) tuple
(img, info) = render([smld_protein1, smld_protein2],
                     colors = [:red, :green],
                     strategy = GaussianRender(),
                     zoom = 20,
                     filename = "two_color.png")

# info.n_emitters_rendered is the total from both datasets
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

(img, info) = render([smld1, smld2, smld3],
                     colors = [:red, :green, :blue],
                     strategy = GaussianRender(),
                     zoom = 20,
                     filename = "three_color.png")
```

### Custom Colors

```julia
using Colors

# Custom RGB colors
(img, info) = render([smld1, smld2],
                     colors = [RGB(1.0, 0.0, 0.0), RGB(0.0, 1.0, 1.0)],  # Red and cyan
                     zoom = 20,
                     filename = "custom_colors.png")

# Named colors (no import needed!)
(img, info) = render([smld1, smld2],
                     colors = [:magenta, :yellow],
                     zoom = 20,
                     filename = "magenta_yellow.png")
```

### Multi-Channel with Different Strategies

```julia
# Note: Currently all channels use same strategy
# For different strategies per channel, render separately and combine manually

# Render each channel
(img1, info1) = render(smld1, color=colorant"red", strategy=GaussianRender(), zoom=20)
(img2, info2) = render(smld2, color=colorant"green", strategy=CircleRender(), zoom=20)

# Manual combination
img_combined = img1 .+ img2
save_image("mixed_strategies.png", img_combined)
```

## Output and Export

### Direct File Save

```julia
# Save directly during rendering (filename kwarg)
(img, info) = render(smld,
                     colormap = :inferno,
                     zoom = 20,
                     filename = "output.png")

# Or save later
(img, info) = render(smld, colormap=:inferno, zoom=20)
save_image("output.png", img)
```

### Export Colorbar

```julia
# Easy way: from render info (uses info.field_range)
(img, info) = render(smld, color_by=:z, colormap=:turbo, zoom=20)
export_colorbar(:turbo, info.field_range, "Z-depth (nm)", "colorbar.png")

# Manual way with custom parameters
export_colorbar(:turbo,                      # Colormap
                (-500.0, 500.0),             # Value range
                "Z-depth (nm)",              # Label
                "colorbar.png",              # Filename
                orientation = :vertical,     # :vertical or :horizontal
                size = (80, 400),            # (width, height) in pixels
                fontsize = 14,               # Label font size
                tickfontsize = 12)           # Tick font size
```

### Access RenderInfo Metadata

```julia
(img, info) = render(smld, color_by=:z, colormap=:turbo, zoom=20)

# RenderInfo fields - ecosystem standard
println("Elapsed time: ", info.elapsed_ns / 1e9, " seconds")
println("Backend: ", info.backend)           # :cpu, :cuda, :metal
println("Device ID: ", info.device_id)       # 0 for CPU

# RenderInfo fields - render-specific
println("Image size: ", info.output_size)    # (height, width)
println("Number of emitters: ", info.n_emitters_rendered)
println("Pixel size: ", info.pixel_size_nm, " nm")
println("Strategy: ", info.strategy)         # :gaussian, :histogram, :circle
println("Color mode: ", info.color_mode)     # :intensity, :field, :manual
println("Field range: ", info.field_range)   # For colorbar (field modes)
```

## Custom Targets

### Explicit Pixel Edges

```julia
# Define custom pixel edges
x_edges = range(0.0, 10.0, length=201)  # 200 pixels, 0-10 μm
y_edges = range(0.0, 10.0, length=201)

(img, info) = render(smld, x_edges, y_edges,
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

(img, info) = render(smld,
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
(img, info) = render(smld, backend=:cpu, zoom=20)
@show info.backend  # :cpu

# Auto backend selection (future: may select GPU if available)
(img, info) = render(smld, backend=:auto, zoom=20)

# Note: CUDA and Metal backends planned for future releases
```

### Large Dataset Rendering

```julia
# For very large datasets, use HistogramRender for speed
(img, info) = render(smld,
                     strategy = HistogramRender(),
                     colormap = :hot,
                     zoom = 10,
                     filename = "large_dataset.png")
println("Rendered in $(info.elapsed_ns / 1e6) ms")

# Or reduce zoom factor to reduce output size
(img, info) = render(smld,
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
(img, info) = render(smld, zoom=5, colormap=:hot, filename="preview.png")
println("$(info.n_emitters_rendered) emitters in $(info.elapsed_ns / 1e6) ms")
```

### Publication Figure

```julia
# High-quality Gaussian rendering for publication
(img, info) = render(smld,
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
(img, info) = render(smld,
                     strategy = CircleRender(
                         radius_factor = 1.0,     # 1σ circles
                         line_width = 1.0,
                         use_localization_precision = true
                     ),
                     color_by = :σ_x,            # Color by precision
                     colormap = :plasma,
                     zoom = 50,
                     filename = "uncertainty.png")
println("Precision range: $(info.field_range)")
```

### 3D Depth Encoding

```julia
# Encode z-depth in color
(img, info) = render(smld,
                     strategy = GaussianRender(),
                     color_by = :z,
                     colormap = :turbo,
                     zoom = 20,
                     filename = "3d_depth.png")

# Export colorbar showing depth scale using info.field_range
export_colorbar(:turbo, info.field_range, "Z-depth (nm)", "depth_scale.png")
```

### Temporal Dynamics

```julia
# Show acquisition time via frame coloring
(img, info) = render(smld,
                     strategy = GaussianRender(),
                     color_by = :frame,
                     colormap = :twilight,        # Cyclic for temporal
                     zoom = 20,
                     filename = "temporal.png")
println("Frame range: $(info.field_range)")
```
