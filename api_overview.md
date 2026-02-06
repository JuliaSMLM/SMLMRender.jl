# SMLMRender.jl API Reference

High-performance rendering for Single Molecule Localization Microscopy (SMLM) data with multiple rendering algorithms and flexible color mapping.

## Exports Summary

Total exports: 24 (1 function, 18 types, 5 utilities)

**Main Function:** `render()` - returns `(image, info)` tuple

**Rendering Strategies:** `RenderingStrategy`, `Render2DStrategy`, `HistogramRender`, `GaussianRender`, `CircleRender`, `EllipseRender`

**Color Mapping:** `ColorMapping`, `IntensityColorMapping`, `FieldColorMapping`, `ManualColorMapping`, `GrayscaleMapping`, `CategoricalColorMapping`

**Render Configuration:** `RenderTarget`, `Image2DTarget`, `ContrastMethod`, `ContrastOptions`, `RenderConfig`, `RenderInfo`, `RenderResult2D` (deprecated)

**Utilities:** `create_target_from_smld`, `list_recommended_colormaps`, `save_image`, `export_colorbar`

## Key Concepts

### Rendering Workflow

SMLMRender converts localization data into publication-quality images through a configurable pipeline:

1. **Target Specification** - Define output image dimensions and physical bounds (zoom vs pixel_size modes)
2. **Rendering Strategy** - Choose algorithm for converting localizations to pixels (Histogram, Gaussian, Circle)
3. **Color Mapping** - Map intensity or field values to colors (intensity-based, field-based, or manual)
4. **Result** - Get `(image, info)` tuple containing the rendered image and `RenderInfo` metadata

### Resolution Modes

**Zoom Mode:** Renders the exact camera field-of-view (FOV) with subdivided pixels. A 128×128 pixel camera with `zoom=10` produces exactly 1280×1280 output pixels covering the same physical region. Output range precisely matches camera FOV. Use this for faithful camera FOV representation.

**Pixel Size Mode:** Uses data bounds (min/max of localization coordinates) plus a margin, with specified pixel size in nm. Output dimensions vary based on where localizations fell. Use this for cropping to regions of interest or when camera info is unavailable.

### Coordinate System

Physical coordinates are in micrometers (μm). Pixel sizes are in nanometers (nm). Camera FOV and localization coordinates use μm, but rendering precision uses nm internally for sub-pixel accuracy.

### Rendering Strategies

**HistogramRender:** Fast binning - counts localizations per pixel. No sub-pixel accuracy. Best for quick previews or very dense data.

**GaussianRender:** Renders each localization as a 2D Gaussian blob. Provides smooth, publication-quality images with sub-pixel accuracy. Can use localization precision (σ_x, σ_y fields) or fixed sigma.

**CircleRender:** Renders localization as circle outline. Useful for visualizing localization precision when σ represents uncertainty radius. Circle radius can be multiple of σ.

### Color Mapping Strategies

**IntensityColorMapping:** Accumulate grayscale intensity, then apply colormap. Traditional SMLM rendering - bright = many localizations. Percentile clipping is computed on non-zero pixels only (important for sparse SMLM data where most pixels are background).

**FieldColorMapping:** Color each localization by its field value (z-depth, photons, frame, etc.) before rendering. Enables visualization of additional data dimensions through RGB accumulation.

**ManualColorMapping:** All localizations rendered in same fixed color. Used for multi-channel overlays.

**GrayscaleMapping:** No colormap applied, returns grayscale intensity.

### Region of Interest (ROI)

When using zoom mode, you can specify an ROI as camera pixel ranges: `roi=(430:860, 1:256)` renders only that camera region. Use `:` for full range on an axis: `roi=(430:860, :)` renders x-pixels 430-860 with full y-range. ROI only applies to zoom mode, not pixel_size mode.

## Type Hierarchy

```
RenderingStrategy (abstract)
├── Render2DStrategy (abstract)
    ├── HistogramRender
    ├── GaussianRender
    └── CircleRender

ColorMapping (abstract)
├── IntensityColorMapping
├── FieldColorMapping
├── ManualColorMapping
└── GrayscaleMapping

RenderTarget (abstract)
└── Image2DTarget

ContrastMethod (enum)
├── LinearContrast
├── LogContrast
├── SqrtContrast
└── HistogramEqualization
```

## Essential Types

### Rendering Strategies

```julia
# Fast histogram binning (no sub-pixel accuracy)
struct HistogramRender <: Render2DStrategy end

# Gaussian blob rendering
struct GaussianRender <: Render2DStrategy
    n_sigmas::Float64                      # How many σ to render (default: 3.0)
    use_localization_precision::Bool       # Use σ_x, σ_y from data
    fixed_sigma::Union{Float64, Nothing}   # Fixed σ in nm (if not using precision)
    normalization::Symbol                  # :integral or :maximum
end

# Circle outline rendering
struct CircleRender <: Render2DStrategy
    radius_factor::Float64                 # Multiply σ by this (1.0=1σ, 2.0=2σ)
    line_width::Float64                    # Outline width in pixels
    use_localization_precision::Bool       # Use σ_x, σ_y or fixed radius
    fixed_radius::Union{Float64, Nothing}  # Fixed radius in nm
end
```

### Color Mappings

```julia
# Intensity-based coloring
struct IntensityColorMapping <: ColorMapping
    colormap::Symbol         # ColorSchemes.jl name (:inferno, :viridis, etc.)
    clip_percentile::Float64 # Clip intensity before mapping (0.99 = top 1%, computed on non-zero pixels only)
end

# Field-based coloring
struct FieldColorMapping <: ColorMapping
    field::Symbol                                   # Field name (:z, :photons, :frame, etc.)
    colormap::Symbol                                # ColorSchemes.jl name
    range::Union{Tuple{Float64, Float64}, Symbol}   # Value range or :auto
    clip_percentiles::Union{Tuple{Float64, Float64}, Nothing}  # Percentile clipping
end

# Fixed color
struct ManualColorMapping <: ColorMapping
    color::RGB{Float64}  # Fixed color for all localizations
end

# No colormap
struct GrayscaleMapping <: ColorMapping end

# Categorical coloring (for cluster IDs, molecule IDs)
struct CategoricalColorMapping <: ColorMapping
    field::Symbol    # Integer field (:id, :cluster_id, :molecule, etc.)
    palette::Symbol  # Categorical palette (:tab10, :Set1, :Dark2, etc.)
end
# Colors cycle when values exceed palette size via mod1(value, length(palette))
```

### Render Configuration

```julia
# Target specification
struct Image2DTarget <: RenderTarget
    width::Int                          # Image width in pixels
    height::Int                         # Image height in pixels
    pixel_size::Float64                 # Pixel size in nm
    x_range::Tuple{Float64, Float64}    # Physical x-range in μm
    y_range::Tuple{Float64, Float64}    # Physical y-range in μm
end

# Contrast enhancement options
struct ContrastOptions
    method::ContrastMethod     # Enhancement method
    clip_percentile::Float64   # Clip before enhancement (percentile of non-zero pixels)
    gamma::Float64             # Power-law gamma adjustment
end

# Complete rendering configuration
struct RenderConfig{S<:RenderingStrategy, C<:ColorMapping}
    strategy::S
    color_mapping::C
    contrast::Union{ContrastOptions, Nothing}
    backend::Symbol  # :cpu, :cuda, :metal, :auto
end

# Render metadata (ecosystem convention)
struct RenderInfo
    # Common fields (ecosystem convention)
    elapsed_s::Float64       # Execution time in seconds
    backend::Symbol          # Compute backend (:cpu, :cuda, :metal)
    device_id::Int           # Device identifier (0 for CPU)

    # Render-specific fields
    n_emitters_rendered::Int              # Number of emitters actually rendered
    output_size::Tuple{Int,Int}           # (height, width) of output image
    pixel_size_nm::Float64                # Output pixel size in nanometers
    strategy::Symbol                      # :gaussian, :histogram, :circle, :ellipse
    color_mode::Symbol                    # :intensity, :field, :categorical, :manual, :grayscale
    field_range::Union{Nothing, Tuple{Float64,Float64}}  # Value range for colorbar
end

# DEPRECATED: Use tuple unpacking instead
# struct RenderResult2D{T} - deprecated, use (image, info) = render(...) pattern
```

## Core Functions

### Main Rendering Interface

#### `render(smld, target::Image2DTarget, options::RenderConfig) -> (Matrix{RGB{Float64}}, RenderInfo)`

Primary rendering interface using explicit configuration structs.

**Arguments:**
- `smld` - SMLD dataset containing emitters
- `target::Image2DTarget` - Output image specification (dimensions, pixel size, physical bounds)
- `options::RenderConfig` - Rendering configuration (strategy, color mapping, backend)

**Returns:** `(image, info)` tuple

**Example:**
```julia
target = create_target_from_smld(smld, zoom=20)
options = RenderConfig(GaussianRender(), IntensityColorMapping(:inferno, 0.99))
(img, info) = render(smld, target, options)
```

#### `render(smld; kwargs...) -> (Matrix{RGB{Float64}}, RenderInfo)`

Convenience interface using keyword arguments. Constructs target and options internally, then forwards to the primary form.

**Resolution (choose one):**
- `zoom::Real` - Renders exact camera FOV with `camera_pixels × zoom` output
- `pixel_size::Real` - Pixel size in nm, uses data bounds + margin (variable output size)
- `target::Image2DTarget` - Explicit target specification (advanced)

**Region of Interest:**
- `roi::Tuple` - Camera pixel ranges as `(x_range, y_range)`. Use `:` for full range. Example: `roi=(430:860, :)`. Only applies to zoom mode.

**Rendering:**
- `strategy::RenderingStrategy` - Algorithm to use (default: `GaussianRender()`)
- `backend::Symbol` - Computation backend: `:cpu`, `:cuda`, `:metal`, `:auto` (default: `:cpu`)

**Color Mapping (mutually exclusive):**
- `colormap::Symbol` - Intensity-based coloring (`:inferno`, `:hot`, `:viridis`, etc.)
- `color_by::Symbol` - Field-based coloring (`:z`, `:photons`, `:frame`, `:σ_x`, etc.)
- `color::RGB` - Manual color (e.g., `colorant"red"`)
- `categorical::Bool` - Use categorical palette for integer fields like `:id` (default: `false`)

**Options:**
- `clip_percentile::Real` - Percentile for intensity clipping (default: 0.99)
- `field_range::Union{Tuple, Symbol}` - Value range for field coloring or `:auto` (default: `:auto`)
- `field_clip_percentiles::Union{Tuple, Nothing}` - Percentile clipping for fields (default: `(0.01, 0.99)`)
- `filename::Union{String, Nothing}` - Save directly to file if provided

**Returns:** `(image, info)` tuple where `image` is `Matrix{RGB{Float64}}` and `info` is `RenderInfo`

#### `render(smld, x_edges, y_edges; kwargs...) -> (Matrix{RGB{Float64}}, RenderInfo)`

Render with explicit pixel edges (advanced usage).

**Arguments:**
- `smld` - SMLD dataset
- `x_edges::AbstractVector` - Pixel edges in μm (length = width + 1)
- `y_edges::AbstractVector` - Pixel edges in μm (length = height + 1)
- `kwargs...` - Same as main render function

#### `render(smlds::Vector; colors::Vector, kwargs...) -> (Matrix{RGB{Float64}}, RenderInfo)`

Multi-channel rendering via dispatch on `Vector`.

**Arguments:**
- `smlds::Vector` - Vector of SMLD datasets
- `colors::Vector` - Vector of colors (RGB, Symbol like `:red`, or String like `"green"`)
- `normalize_each::Bool` - Normalize each channel independently (default: `true`)
- All other kwargs same as single-channel render

**Returns:** `(image, info)` tuple with overlaid channels image and combined RenderInfo

### Utilities

#### `create_target_from_smld(smld; kwargs...) -> Image2DTarget`

Create render target from SMLD data.

**Arguments:**
- `smld` - SMLD dataset
- `pixel_size::Union{Real, Nothing}` - Pixel size in nm (data bounds mode)
- `zoom::Union{Real, Nothing}` - Zoom factor (camera FOV mode)
- `roi::Union{Tuple, Nothing}` - Camera pixel ROI (only with zoom)
- `margin::Real` - Fractional margin for data bounds (default: 0.05)

Either `pixel_size` or `zoom` must be specified.

#### `list_recommended_colormaps() -> Dict{Symbol, Vector{Symbol}}`

Return dictionary of recommended colormaps organized by category.

**Categories:**
- `:sequential` - For continuous data (viridis, inferno, magma, plasma, turbo, hot, cividis)
- `:diverging` - For data with meaningful center (RdBu, seismic, coolwarm)
- `:cyclic` - For periodic data (twilight, phase)
- `:perceptual` - Perceptually uniform (viridis, cividis, inferno, magma, plasma)

#### `save_image(filename::String, img::Matrix{RGB}) -> Nothing`

Save rendered image to file.

**Arguments:**
- `filename` - Output path (extension determines format: .png, .tiff, etc.)
- `img` - RGB image matrix from `render()`

Supports PNG, TIFF, and other formats via FileIO/ImageIO.

#### `export_colorbar(result::RenderResult2D, filename::String; kwargs...) -> Nothing`
#### `export_colorbar(colormap::Symbol, value_range::Tuple, label::String, filename::String; kwargs...) -> Nothing`

Export colorbar legend showing field value to color mapping.

**Arguments:**
- `result::RenderResult2D` - Render result with field metadata (easiest)
- OR manually: `colormap`, `value_range`, `label`
- `filename` - Output file path

**Keyword Arguments:**
- `orientation::Symbol` - `:vertical` (default) or `:horizontal`
- `size::Tuple{Int,Int}` - Width, height in pixels (default: `(80, 400)` for vertical)
- `fontsize::Int` - Label font size (default: 14)
- `tickfontsize::Int` - Tick label font size (default: 12)

Only works for field-based coloring (when `color_by=...` was used).

## Common Workflows

### Basic Intensity Rendering

```julia
using SMLMData, SMLMRender

# Load data
smld = load_smite_2d("data.mat")

# Render with zoom=20 (20 output pixels per camera pixel)
(img, info) = render(smld, colormap=:inferno, zoom=20)

# Access metadata
println("Rendered $(info.n_emitters_rendered) emitters in $(info.elapsed_s * 1000) ms")

# Save to file
save_image("output.png", img)
```

### Field-Based Coloring

```julia
# Color by z-depth
(img, info) = render(smld, color_by=:z, colormap=:turbo, zoom=20)

# Color by photon count
(img, info) = render(smld, color_by=:photons, colormap=:viridis, zoom=20)

# Export colorbar using info.field_range
export_colorbar(:viridis, info.field_range, "Photons", "colorbar.png")
```

### Categorical Coloring (Clusters/IDs)

```julia
# Color by cluster ID - each cluster gets distinct color from palette
(img, info) = render(smld, color_by=:id, categorical=true, zoom=20)

# Custom palette (tab10 is default)
(img, info) = render(smld, color_by=:id, colormap=:Set1_9, categorical=true, zoom=20)

# Available categorical palettes (high-contrast, distinct colors):
# :tab10   - 10 colors (most popular, Matplotlib default)
# :Set1_9  - 9 high-saturation colors (ColorBrewer)
# :Set2_8  - 8 pastel colors
# :Set3_12 - 12 colors
# :tab20   - 20 colors (10 pairs)
# :tab20b  - 20 colors (alternative)
# :tab20c  - 20 colors (alternative)

# Colors cycle when cluster IDs exceed palette size
# e.g., with :tab10, cluster 11 gets same color as cluster 1
```

### Multi-Channel Overlay

```julia
# Two-color overlay
(img, info) = render([smld1, smld2],
             colors=[colorant"red", colorant"green"],
             zoom=20)

# Save directly
render([smld1, smld2],
       colors=[:red, :green],
       zoom=20,
       filename="overlay.png")
```

### Region of Interest Rendering

```julia
# Render ROI: camera pixels 430-860 in x, full y-range
(img, info) = render(smld,
                colormap=:inferno,
                zoom=20,
                roi=(430:860, :))

# Render specific x and y region
(img, info) = render(smld,
                colormap=:hot,
                zoom=15,
                roi=(100:200, 50:150))
```

### Different Rendering Strategies

```julia
# Histogram rendering (fast)
(img, info) = render(smld,
                strategy=HistogramRender(),
                colormap=:hot,
                zoom=10)

# Gaussian rendering with custom parameters
(img, info) = render(smld,
                strategy=GaussianRender(n_sigmas=4.0,
                                       use_localization_precision=true,
                                       fixed_sigma=nothing,
                                       normalization=:integral),
                colormap=:inferno,
                zoom=20)

# Circle rendering to visualize precision
(img, info) = render(smld,
                strategy=CircleRender(radius_factor=2.0,  # 2σ circles
                                     line_width=1.0,
                                     use_localization_precision=true,
                                     fixed_radius=nothing),
                color_by=:photons,
                colormap=:plasma,
                zoom=50)
```

### Using Pixel Size Mode

```julia
# 10nm pixels, output size determined by data bounds
(img, info) = render(smld, pixel_size=10.0, colormap=:viridis)

# Adjust margin around data
target = create_target_from_smld(smld, pixel_size=5.0, margin=0.1)  # 10% margin
(img, info) = render(smld, target=target, colormap=:inferno)
```

## Complete Examples

### Example 1: Basic Workflow

```julia
using SMLMData, SMLMRender
using Colors

# Create test data with localization precision
camera = IdealCamera(128, 128, 100.0)  # 128×128 pixels, 100nm pixel size
emitters = [
    Emitter2DFit{Float64}(5.0, 5.0, 1000.0, 10.0, 0.020, 0.020, 50.0, 2.0; frame=1, id=1),
    Emitter2DFit{Float64}(6.0, 6.0, 1200.0, 10.0, 0.018, 0.018, 60.0, 2.0; frame=1, id=2),
    Emitter2DFit{Float64}(7.0, 7.0, 1100.0, 10.0, 0.021, 0.021, 55.0, 2.0; frame=2, id=3)
]
smld = BasicSMLD(emitters, camera, 2, 1)

# Render with intensity colormap - returns (image, info) tuple
(img, info) = render(smld, colormap=:inferno, zoom=10)
println("Rendered $(info.n_emitters_rendered) emitters")
println("Image size: $(info.output_size)")
println("Render time: $(info.elapsed_s * 1000) ms")

# Save to file
save_image("rendered.png", img)
```

### Example 2: Field Coloring with Colorbar

```julia
using SMLMData, SMLMRender

# Load 3D data with z-coordinates
smld = load_smite_3d("3d_data.mat")

# Render colored by z-depth
(img, info) = render(smld,
                color_by=:z,
                colormap=:turbo,
                zoom=20,
                filename="depth_map.png")

# Export colorbar using the field_range from info
export_colorbar(:turbo, info.field_range, "Z-depth (μm)",
                "depth_colorbar.png",
                orientation=:vertical,
                size=(100, 400))

# Manual colorbar (if you need custom parameters)
export_colorbar(:turbo,
                (-500.0, 500.0),
                "Z-depth (nm)",
                "custom_colorbar.png")
```

### Example 3: Multi-Channel Overlay

```julia
using SMLMData, SMLMRender
using Colors

# Load two-color data
smld_ch1 = load_smite_2d("channel1.mat")
smld_ch2 = load_smite_2d("channel2.mat")

# Create overlay with normalization - returns tuple
(img, info) = render([smld_ch1, smld_ch2],
             colors=[colorant"red", colorant"green"],
             zoom=20,
             normalize_each=true)  # Normalize each channel independently

# Save result
save_image("overlay.png", img)

# Or use symbol names for colors
render([smld_ch1, smld_ch2],
       colors=[:magenta, :cyan],
       zoom=20,
       filename="overlay_mc.png")
```

### Example 4: ROI and Strategy Comparison

```julia
using SMLMData, SMLMRender

smld = load_smite_2d("dense_data.mat")

# Define ROI in camera pixels
roi = (400:600, 400:600)

# Compare different strategies on same ROI
(_, info_hist) = render(smld,
                         strategy=HistogramRender(),
                         colormap=:hot,
                         zoom=10,
                         roi=roi,
                         filename="roi_histogram.png")

(_, info_gauss) = render(smld,
                        strategy=GaussianRender(),
                        colormap=:inferno,
                        zoom=20,
                        roi=roi,
                        filename="roi_gaussian.png")

(_, info_circ) = render(smld,
                      strategy=CircleRender(radius_factor=1.0, line_width=1.5),
                      color=:red,
                      zoom=50,
                      roi=roi,
                      filename="roi_circles.png")

println("Histogram: $(info_hist.elapsed_s * 1000) ms")
println("Gaussian: $(info_gauss.elapsed_s * 1000) ms")
println("Circle: $(info_circ.elapsed_s * 1000) ms")
```

### Example 5: Exploring Colormaps

```julia
using SMLMData, SMLMRender

smld = load_smite_2d("data.mat")

# List available colormaps
cmaps = list_recommended_colormaps()
println("Sequential colormaps: ", cmaps[:sequential])

# Render with different sequential colormaps
for cmap in [:viridis, :inferno, :magma, :plasma, :turbo]
    render(smld,
           colormap=cmap,
           zoom=20,
           filename="render_$(cmap).png")
end

# Diverging colormaps work well for z-data centered at 0
render(smld,
       color_by=:z,
       colormap=:RdBu,
       field_range=(-300.0, 300.0),
       zoom=20,
       filename="z_diverging.png")
```

### Example 6: Custom Rendering Parameters

```julia
using SMLMData, SMLMRender

smld = load_smite_2d("data.mat")

# Gaussian rendering with fixed sigma (ignore localization precision)
(img, info) = render(smld,
                strategy=GaussianRender(n_sigmas=3.0,
                                       use_localization_precision=false,
                                       fixed_sigma=20.0,  # 20nm fixed sigma
                                       normalization=:integral),
                colormap=:inferno,
                zoom=20)

# Circle rendering with fixed radius
(img, info) = render(smld,
                strategy=CircleRender(radius_factor=1.0,
                                     line_width=2.0,
                                     use_localization_precision=false,
                                     fixed_radius=15.0),  # 15nm fixed radius
                color=colorant"cyan",
                zoom=30)

# Field coloring with explicit value range (no auto-scaling)
(img, info) = render(smld,
                color_by=:photons,
                colormap=:plasma,
                field_range=(500.0, 5000.0),  # Explicit range
                field_clip_percentiles=nothing,  # No clipping
                zoom=20)
```
