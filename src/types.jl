# Core type definitions for SMLMRender.jl

using Colors

# ============================================================================
# Rendering Strategies (Algorithm Selection)
# ============================================================================

"""
    RenderingStrategy

Abstract type for different rendering algorithms.
"""
abstract type RenderingStrategy end

"""
    Render2DStrategy <: RenderingStrategy

Abstract type for 2D rendering strategies.
"""
abstract type Render2DStrategy <: RenderingStrategy end

"""
    HistogramRender <: Render2DStrategy

Fast binning-based rendering. Each pixel counts the number of localizations
that fall within it. No sub-pixel accuracy, but very fast.

# Examples
```julia
strategy = HistogramRender()
img = render(smld; strategy=strategy)
```
"""
struct HistogramRender <: Render2DStrategy end

"""
    GaussianRender <: Render2DStrategy

Renders each localization as a 2D Gaussian blob. Provides smooth,
publication-quality images with sub-pixel accuracy.

# Fields
- `n_sigmas::Float64`: How many standard deviations to render (default: 3.0)
- `use_localization_precision::Bool`: Use σ_x, σ_y from data or fixed sigma
- `fixed_sigma::Union{Float64, Nothing}`: Fixed sigma in nm (if not using precision)
- `normalization::Symbol`: `:integral` (sum to 1) or `:maximum` (peak to 1)

# Examples
```julia
# Use localization precision from data
strategy = GaussianRender(3.0, true, nothing, :integral)

# Use fixed 20 nm sigma
strategy = GaussianRender(3.0, false, 20.0, :integral)
```
"""
struct GaussianRender <: Render2DStrategy
    n_sigmas::Float64
    use_localization_precision::Bool
    fixed_sigma::Union{Float64, Nothing}
    normalization::Symbol

    function GaussianRender(n_sigmas::Real, use_precision::Bool,
                           fixed_sigma::Union{Real, Nothing},
                           normalization::Symbol)
        @assert n_sigmas > 0 "n_sigmas must be positive"
        @assert normalization in (:integral, :maximum) "normalization must be :integral or :maximum"
        if !use_precision
            @assert fixed_sigma !== nothing && fixed_sigma > 0 "fixed_sigma must be positive when not using localization precision"
        end
        new(Float64(n_sigmas), use_precision,
            fixed_sigma === nothing ? nothing : Float64(fixed_sigma),
            normalization)
    end
end

# Convenience constructor with defaults
GaussianRender(; n_sigmas=3.0, use_localization_precision=true,
               fixed_sigma=nothing, normalization=:integral) =
    GaussianRender(n_sigmas, use_localization_precision, fixed_sigma, normalization)

"""
    CircleRender <: Render2DStrategy

Renders each localization as a circle outline. Useful for visualizing
localization precision (circle radius = σ).

# Fields
- `radius_factor::Float64`: Multiply sigma by this (1.0=1σ, 2.0=2σ)
- `line_width::Float64`: Outline width in pixels (default: 1.0)
- `use_localization_precision::Bool`: Use σ_x, σ_y or fixed radius
- `fixed_radius::Union{Float64, Nothing}`: Fixed radius in nm

# Examples
```julia
# 2σ circles with 1-pixel lines
strategy = CircleRender(2.0, 1.0, true, nothing)

# Fixed 20nm radius circles with thick lines
strategy = CircleRender(1.0, 2.5, false, 20.0)
```
"""
struct CircleRender <: Render2DStrategy
    radius_factor::Float64
    line_width::Float64
    use_localization_precision::Bool
    fixed_radius::Union{Float64, Nothing}

    function CircleRender(radius_factor::Real, line_width::Real,
                         use_precision::Bool, fixed_radius::Union{Real, Nothing})
        @assert radius_factor > 0 "radius_factor must be positive"
        @assert line_width > 0 "line_width must be positive"
        if !use_precision
            @assert fixed_radius !== nothing && fixed_radius > 0 "fixed_radius must be positive when not using localization precision"
        end
        new(Float64(radius_factor), Float64(line_width), use_precision,
            fixed_radius === nothing ? nothing : Float64(fixed_radius))
    end
end

# Convenience constructor
CircleRender(; radius_factor=2.0, line_width=1.0,
             use_localization_precision=true, fixed_radius=nothing) =
    CircleRender(radius_factor, line_width, use_localization_precision, fixed_radius)

# ============================================================================
# Color Mapping
# ============================================================================

"""
    ColorMapping

Abstract type for different color mapping strategies.
"""
abstract type ColorMapping end

"""
    IntensityColorMapping <: ColorMapping

Accumulate grayscale intensity, then apply colormap. Traditional SMLM rendering.

# Fields
- `colormap::Symbol`: ColorSchemes.jl colormap name (e.g., :inferno, :viridis)
- `clip_percentile::Float64`: Clip intensity before mapping (0.999 = top 0.1%)

# Examples
```julia
color_mapping = IntensityColorMapping(:inferno, 0.999)
img = render(smld; color_mapping=color_mapping)
```
"""
struct IntensityColorMapping <: ColorMapping
    colormap::Symbol
    clip_percentile::Float64

    function IntensityColorMapping(colormap::Symbol, clip_percentile::Real)
        @assert 0 < clip_percentile <= 1.0 "clip_percentile must be in (0, 1]"
        new(colormap, Float64(clip_percentile))
    end
end

IntensityColorMapping(colormap::Symbol) = IntensityColorMapping(colormap, 0.999)

"""
    FieldColorMapping <: ColorMapping

Color each localization by its field value before rendering. RGB accumulation.

# Fields
- `field::Symbol`: Field name (:z, :photons, :frame, :σ_x, etc.)
- `colormap::Symbol`: ColorSchemes.jl colormap name
- `range::Union{Tuple{Float64, Float64}, Symbol}`: Value range or :auto
- `clip_percentiles::Union{Tuple{Float64, Float64}, Nothing}`: Percentile clipping

# Examples
```julia
# Auto-range with percentile clipping
color_mapping = FieldColorMapping(:z, :viridis, :auto, (0.01, 0.99))

# Explicit range, no clipping
color_mapping = FieldColorMapping(:photons, :inferno, (100.0, 10000.0), nothing)
```
"""
struct FieldColorMapping <: ColorMapping
    field::Symbol
    colormap::Symbol
    range::Union{Tuple{Float64, Float64}, Symbol}
    clip_percentiles::Union{Tuple{Float64, Float64}, Nothing}

    function FieldColorMapping(field::Symbol, colormap::Symbol,
                              range::Union{Tuple{Real, Real}, Symbol},
                              clip_percentiles::Union{Tuple{Real, Real}, Nothing})
        if range isa Tuple
            @assert range[1] < range[2] "range must be (min, max) with min < max"
            range = (Float64(range[1]), Float64(range[2]))
        else
            @assert range == :auto "range must be a tuple or :auto"
        end

        if clip_percentiles !== nothing
            @assert 0 <= clip_percentiles[1] < clip_percentiles[2] <= 1.0 "clip_percentiles must be (low, high) with 0 ≤ low < high ≤ 1"
            clip_percentiles = (Float64(clip_percentiles[1]), Float64(clip_percentiles[2]))
        end

        new(field, colormap, range, clip_percentiles)
    end
end

"""
    ManualColorMapping <: ColorMapping

All localizations rendered in the same fixed color. Used for multi-color overlays.

# Fields
- `color::RGB{Float64}`: Fixed color for all localizations

# Examples
```julia
color_mapping = ManualColorMapping(RGB(1.0, 0.0, 0.0))  # Red
img = render(smld; color_mapping=color_mapping)
```
"""
struct ManualColorMapping <: ColorMapping
    color::RGB{Float64}
end

"""
    GrayscaleMapping <: ColorMapping

No colormap applied. Returns grayscale image.
"""
struct GrayscaleMapping <: ColorMapping end

# ============================================================================
# Render Targets (What we're rendering to)
# ============================================================================

"""
    RenderTarget

Abstract type for render targets (image, volume, etc.)
"""
abstract type RenderTarget end

"""
    Image2DTarget <: RenderTarget

Specification for a 2D image render target.

# Fields
- `width::Int`: Image width in pixels
- `height::Int`: Image height in pixels
- `pixel_size::Float64`: Pixel size in nm
- `x_range::Tuple{Float64, Float64}`: Physical x-range in μm
- `y_range::Tuple{Float64, Float64}`: Physical y-range in μm
"""
struct Image2DTarget <: RenderTarget
    width::Int
    height::Int
    pixel_size::Float64  # nm per pixel
    x_range::Tuple{Float64, Float64}  # μm
    y_range::Tuple{Float64, Float64}  # μm

    function Image2DTarget(width::Int, height::Int, pixel_size::Real,
                          x_range::Tuple{Real, Real}, y_range::Tuple{Real, Real})
        @assert width > 0 && height > 0 "Dimensions must be positive"
        @assert pixel_size > 0 "pixel_size must be positive"
        @assert x_range[1] < x_range[2] && y_range[1] < y_range[2] "Invalid ranges"
        new(width, height, Float64(pixel_size),
            (Float64(x_range[1]), Float64(x_range[2])),
            (Float64(y_range[1]), Float64(y_range[2])))
    end
end

# ============================================================================
# Contrast Enhancement
# ============================================================================

"""
    ContrastMethod

Enumeration of contrast enhancement methods.

# Values
- `LinearContrast`: Linear scaling
- `LogContrast`: Logarithmic scaling
- `SqrtContrast`: Square root scaling
- `HistogramEqualization`: Histogram equalization
"""
@enum ContrastMethod begin
    LinearContrast
    LogContrast
    SqrtContrast
    HistogramEqualization
end

"""
    ContrastOptions

Options for contrast enhancement.

# Fields
- `method::ContrastMethod`: Enhancement method
- `clip_percentile::Float64`: Clip before enhancement (0.999 = top 0.1%)
- `gamma::Float64`: Power-law gamma adjustment (default: 1.0)
"""
struct ContrastOptions
    method::ContrastMethod
    clip_percentile::Float64
    gamma::Float64

    function ContrastOptions(method::ContrastMethod, clip_percentile::Real, gamma::Real)
        @assert 0 < clip_percentile <= 1.0 "clip_percentile must be in (0, 1]"
        @assert gamma > 0 "gamma must be positive"
        new(method, Float64(clip_percentile), Float64(gamma))
    end
end

ContrastOptions(method::ContrastMethod) = ContrastOptions(method, 0.999, 1.0)

# ============================================================================
# Render Options (Comprehensive Configuration)
# ============================================================================

"""
    RenderOptions{S<:RenderingStrategy, C<:ColorMapping}

Complete configuration for rendering.

# Fields
- `strategy::S`: Rendering algorithm (Histogram, Gaussian, Circle)
- `color_mapping::C`: Color mapping strategy
- `contrast::Union{ContrastOptions, Nothing}`: Contrast enhancement (optional)
- `backend::Symbol`: Computation backend (:cpu, :cuda, :metal, :auto)
- `output_type::Symbol`: Output format (:array, :rgb, :result)
"""
struct RenderOptions{S<:RenderingStrategy, C<:ColorMapping}
    strategy::S
    color_mapping::C
    contrast::Union{ContrastOptions, Nothing}
    backend::Symbol
    output_type::Symbol

    function RenderOptions(strategy::S, color_mapping::C,
                          contrast::Union{ContrastOptions, Nothing},
                          backend::Symbol, output_type::Symbol) where {S,C}
        @assert backend in (:cpu, :cuda, :metal, :auto) "Invalid backend"
        @assert output_type in (:array, :rgb, :result) "Invalid output_type"
        new{S,C}(strategy, color_mapping, contrast, backend, output_type)
    end
end

# Convenience constructor
RenderOptions(strategy::RenderingStrategy, color_mapping::ColorMapping;
              contrast=nothing, backend=:cpu, output_type=:rgb) =
    RenderOptions(strategy, color_mapping, contrast, backend, output_type)

# ============================================================================
# Results
# ============================================================================

"""
    RenderResult2D{T}

Result of a 2D rendering operation.

# Fields
- `image::Matrix{T}`: Rendered image (T can be RGB, Float64, etc.)
- `target::Image2DTarget`: Render target specification
- `options::RenderOptions`: Rendering options used
- `render_time::Float64`: Render time in seconds
- `n_localizations::Int`: Number of localizations rendered
"""
struct RenderResult2D{T}
    image::Matrix{T}
    target::Image2DTarget
    options::RenderOptions
    render_time::Float64
    n_localizations::Int
    field_value_range::Union{Tuple{Float64, Float64}, Nothing}  # Actual field range used (for colorbar)
end
