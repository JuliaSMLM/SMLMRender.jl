# Main interface for SMLMRender.jl

using Colors

# ============================================================================
# Primary form: render(smld, target, config)
# ============================================================================

"""
    render(smld, target::Image2DTarget, config::RenderConfig) -> (Matrix{RGB{Float64}}, RenderInfo)

Primary rendering interface using explicit target and config.

# Arguments
- `smld`: SMLD dataset containing emitters
- `target::Image2DTarget`: Output image specification (dimensions, pixel size, physical bounds)
- `config::RenderConfig`: Rendering configuration

# Returns
Tuple of `(image, info)` where:
- `image::Matrix{RGB{Float64}}`: Rendered image
- `info::RenderInfo`: Metadata including timing, dimensions, and color range

# Example
```julia
target = create_target_from_smld(smld, zoom=20)
config = RenderConfig(colormap=:inferno)
(img, info) = render(smld, target, config)
```

See also: [`render(smld; kwargs...)`](@ref) for the convenience interface.
"""
function render(smld, target::Image2DTarget, config::RenderConfig)
    return _render_dispatch(smld, target, config)
end

# ============================================================================
# Config form: render(smld, config)
# ============================================================================

"""
    render(smld, config::RenderConfig) -> (Matrix{RGB{Float64}}, RenderInfo)

Render using a `RenderConfig` struct. Builds target from config fields
(`zoom`, `pixel_size`, `roi`, or `target`), then forwards to the primary form.
"""
function render(smld, config::RenderConfig)
    # Build target from config
    target = config.target
    if target === nothing
        @assert config.pixel_size !== nothing || config.zoom !== nothing "Must specify pixel_size, zoom, or target in RenderConfig"
        target = create_target_from_smld(smld; pixel_size=config.pixel_size, zoom=config.zoom, roi=config.roi)
    end

    (img, info) = render(smld, target, config)

    # Save to file if requested
    if config.filename !== nothing
        save_image(config.filename, img)
    end

    return (img, info)
end

# ============================================================================
# Convenience form: render(smld; kwargs...)
# ============================================================================

"""
    render(smld; kwargs...)

Convenience rendering interface. All keyword arguments match `RenderConfig` fields exactly.

# Keyword Arguments

**Resolution (choose one):**
- `zoom`: Renders exact camera FOV with `camera_pixels × zoom` output.
  Example: zoom=10 with 128×128 camera → exactly 1280×1280 pixels
- `pixel_size`: Pixel size in nm, uses data bounds + margin (variable output size)
- `target`: Explicit Image2DTarget (advanced)

**Region of Interest:**
- `roi`: Camera pixel ranges as `(x_range, y_range)`. Use `:` for full range.
  Example: `roi=(430:860, 1:256)` or `roi=(430:860, :)` for full y

**Rendering:**
- `strategy`: RenderingStrategy (default: GaussianRender())
- `backend`: :cpu, :cuda, :metal, or :auto (default: :cpu)

**Color Mapping (mutually exclusive):**
- `colormap`: Symbol for intensity-based coloring (e.g., :inferno, :hot, :viridis)
- `color_by`: Field symbol for field-based coloring (:z, :photons, :frame, :σ_x, etc.)
- `color`: Manual color as Symbol (:red, :cyan) or RGB
- `categorical`: Use categorical palette for integer fields like :id (default: false)

**Options:**
- `clip_percentile`: Percentile for intensity clipping (default: 0.99)
- `field_range`: Value range or :auto (default: :auto)
- `field_clip_percentiles`: Percentile clipping tuple (default: (0.01, 0.99))
- `filename`: Save directly to file if provided

# Examples
```julia
# Render exact camera FOV with 20× resolution
(img, info) = render(smld, colormap=:inferno, zoom=20)

# Render ROI at 20× zoom
(img, info) = render(smld, colormap=:inferno, zoom=20, roi=(430:860, :))

# Render data bounds with 10nm pixels
(img, info) = render(smld, color_by=:z, colormap=:viridis, pixel_size=10.0)

# Manual red color
(img, info) = render(smld, color=:red, zoom=15)

# Categorical coloring for cluster IDs
(img, info) = render(smld, color_by=:id, categorical=true, zoom=20)
```
"""
function render(smld;
                strategy::RenderingStrategy = GaussianRender(),
                pixel_size::Union{Real, Nothing} = nothing,
                zoom::Union{Real, Nothing} = nothing,
                roi::Union{Tuple, Nothing} = nothing,
                target::Union{Image2DTarget, Nothing} = nothing,
                colormap::Union{Symbol, Nothing} = nothing,
                color_by::Union{Symbol, Nothing} = nothing,
                color::Union{RGB, Symbol, Nothing} = nothing,
                categorical::Bool = false,
                clip_percentile::Real = 0.99,
                field_range::Union{Tuple{Real, Real}, Symbol} = :auto,
                field_clip_percentiles::Union{Tuple{Real, Real}, Nothing} = (0.01, 0.99),
                backend::Symbol = :cpu,
                filename::Union{String, Nothing} = nothing)

    config = RenderConfig(;
        strategy, pixel_size, zoom, roi, target,
        colormap, color_by, color, categorical,
        clip_percentile, field_range, field_clip_percentiles,
        backend, filename
    )
    return render(smld, config)
end

"""
    render(smld, x_edges, y_edges; kwargs...)

Render with explicit pixel edges.
"""
function render(smld, x_edges::AbstractVector, y_edges::AbstractVector;
                strategy::RenderingStrategy = GaussianRender(),
                colormap::Union{Symbol, Nothing} = nothing,
                color_by::Union{Symbol, Nothing} = nothing,
                color::Union{RGB, Symbol, Nothing} = nothing,
                categorical::Bool = false,
                clip_percentile::Real = 0.99,
                field_range::Union{Tuple{Real, Real}, Symbol} = :auto,
                field_clip_percentiles::Union{Tuple{Real, Real}, Nothing} = (0.01, 0.99),
                backend::Symbol = :cpu,
                filename::Union{String, Nothing} = nothing)

    # Create target from edges
    width = length(x_edges) - 1
    height = length(y_edges) - 1
    pixel_size_x = (x_edges[2] - x_edges[1]) * 1000  # μm to nm
    pixel_size_y = (y_edges[2] - y_edges[1]) * 1000
    @assert pixel_size_x ≈ pixel_size_y "Non-square pixels not yet supported"

    x_range = (x_edges[1], x_edges[end])
    y_range = (y_edges[1], y_edges[end])
    target = Image2DTarget(width, height, pixel_size_x, x_range, y_range)

    return render(smld; target=target, strategy=strategy, colormap=colormap,
                 color_by=color_by, color=color, categorical=categorical,
                 clip_percentile=clip_percentile,
                 field_range=field_range, field_clip_percentiles=field_clip_percentiles,
                 backend=backend, filename=filename)
end

"""
    render_overlay(smlds::Vector, colors::Vector; kwargs...)

Render multiple datasets with different colors and overlay them.

Each dataset is normalized independently, then combined additively.
Oversaturated regions clip to white.

# Arguments
- `smlds`: Vector of SMLD datasets
- `colors`: Vector of colors (RGB or Symbol)
- Additional kwargs passed to render()

# Example
```julia
img = render_overlay([smld1, smld2],
                     [colorant"red", colorant"green"],
                     strategy=GaussianRender(),
                     zoom=20)
```
"""
function render_overlay(smlds::Vector, colors::Vector;
                       strategy::RenderingStrategy = GaussianRender(),
                       pixel_size::Union{Real, Nothing} = nothing,
                       zoom::Union{Real, Nothing} = nothing,
                       target::Union{Image2DTarget, Nothing} = nothing,
                       normalize_each::Bool = true,
                       backend::Symbol = :cpu,
                       filename::Union{String, Nothing} = nothing)

    @assert length(smlds) == length(colors) "Number of datasets must match number of colors"
    @assert length(smlds) > 0 "Must provide at least one dataset"

    # Convert color symbols to RGB if needed
    rgb_colors = [c isa Symbol ? parse(Colorant, string(c)) : c for c in colors]

    # Create common target if not provided
    if target === nothing
        @assert pixel_size !== nothing || zoom !== nothing "Must specify pixel_size, zoom, or target"
        target = create_target_from_smld(smlds[1]; pixel_size=pixel_size, zoom=zoom)
    end

    # Render each dataset with manual color
    images = []
    total_emitters = 0
    t_start = time()
    for (smld, clr) in zip(smlds, rgb_colors)
        config = RenderConfig(strategy=strategy, color=RGB{Float64}(clr), backend=backend)
        (img, info) = _render_dispatch(smld, target, config)
        push!(images, img)
        total_emitters += info.n_emitters_rendered
    end

    # Normalize each independently if requested
    # Skip normalization for outline renders (Circle/Ellipse) - they draw at full intensity
    if normalize_each && !(strategy isa CircleRender || strategy isa EllipseRender)
        for i in eachindex(images)
            images[i] = _normalize_rgb_image(images[i])
        end
    end

    # Combine additively
    combined = zeros(RGB{Float64}, size(images[1]))
    for img in images
        combined .+= img
    end

    # Clip to white (need to clamp each channel separately)
    for i in eachindex(combined)
        pixel = combined[i]
        combined[i] = RGB(clamp(pixel.r, 0.0, 1.0),
                       clamp(pixel.g, 0.0, 1.0),
                       clamp(pixel.b, 0.0, 1.0))
    end

    elapsed_s = time() - t_start

    # Determine strategy symbol
    strategy_sym = _strategy_symbol(strategy)

    # Build RenderInfo for overlay
    info = RenderInfo(
        elapsed_s = elapsed_s,
        backend = backend,
        device_id = 0,
        n_emitters_rendered = total_emitters,
        output_size = (size(combined, 1), size(combined, 2)),
        pixel_size_nm = target.pixel_size,
        strategy = strategy_sym,
        color_mode = :manual  # Overlay uses manual colors
    )

    # Save to file if requested
    if filename !== nothing
        save_image(filename, combined)
    end

    return (combined, info)
end

"""
    render(smlds::Vector; colors, kwargs...)

Multi-channel rendering via multiple dispatch.

Render multiple SMLD datasets with different colors and overlay them.
This is the Julian interface using dispatch on Vector{SMLD}.

# Arguments
- `smlds::Vector`: Vector of SMLD datasets
- `colors`: Vector of colors (RGB, Symbol, or ColorType)
- All other kwargs same as single-channel render()

# Example
```julia
# Two-color overlay
render([smld1, smld2],
       colors = [colorant"red", colorant"green"],
       strategy = GaussianRender(),
       zoom = 20,
       filename = "overlay.png")
```
"""
function render(smlds::Vector;
                colors::Vector,
                strategy::RenderingStrategy = GaussianRender(),
                pixel_size::Union{Real, Nothing} = nothing,
                zoom::Union{Real, Nothing} = nothing,
                target::Union{Image2DTarget, Nothing} = nothing,
                normalize_each::Bool = true,
                backend::Symbol = :cpu,
                filename::Union{String, Nothing} = nothing)

    # Convert color names to RGB (user doesn't need to import Colors)
    rgb_colors = map(colors) do c
        if c isa String || c isa Symbol
            parse(Colorant, string(c))
        else
            c  # Already a color
        end
    end

    # Delegate to render_overlay
    return render_overlay(smlds, rgb_colors;
                         strategy=strategy,
                         pixel_size=pixel_size,
                         zoom=zoom,
                         target=target,
                         normalize_each=normalize_each,
                         backend=backend,
                         filename=filename)
end

# ============================================================================
# Internal helper functions
# ============================================================================

"""
    _determine_color_mapping(config::RenderConfig) -> ColorMapping

Construct a ColorMapping object from flat config fields.
"""
function _determine_color_mapping(config::RenderConfig)
    colormap = config.colormap
    color_by = config.color_by
    color = config.color
    categorical = config.categorical
    clip_percentile = config.clip_percentile
    field_range = config.field_range
    field_clip_percentiles = config.field_clip_percentiles

    # Check for invalid combinations
    if color !== nothing && (colormap !== nothing || color_by !== nothing)
        error("color cannot be combined with colormap or color_by")
    end

    # Determine which mapping to use
    if color_by !== nothing
        if categorical
            # Categorical coloring (e.g., cluster IDs)
            palette = colormap !== nothing ? colormap : :tab10
            return CategoricalColorMapping(color_by, palette)
        else
            # Field-based coloring
            field_colormap = colormap !== nothing ? colormap : :turbo
            return FieldColorMapping(color_by, field_colormap, field_range,
                                    field_clip_percentiles)
        end
    elseif colormap !== nothing
        # Intensity-based coloring
        return IntensityColorMapping(colormap, clip_percentile)
    elseif color !== nothing
        # Manual color - parse Symbol to RGB if needed
        rgb = color isa Symbol ? parse(Colorant, string(color)) : color
        return ManualColorMapping(RGB{Float64}(rgb))
    else
        # Default: intensity with inferno
        return IntensityColorMapping(:inferno, clip_percentile)
    end
end

"""
    _strategy_symbol(strategy::RenderingStrategy) -> Symbol

Return symbol name for a rendering strategy.
"""
function _strategy_symbol(strategy::RenderingStrategy)
    if strategy isa HistogramRender
        :histogram
    elseif strategy isa GaussianRender
        :gaussian
    elseif strategy isa CircleRender
        :circle
    elseif strategy isa EllipseRender
        :ellipse
    else
        :unknown
    end
end

"""
    _color_mode_symbol(color_mapping::ColorMapping) -> Symbol

Return symbol name for a color mapping.
"""
function _color_mode_symbol(color_mapping::ColorMapping)
    if color_mapping isa IntensityColorMapping
        :intensity
    elseif color_mapping isa FieldColorMapping
        :field
    elseif color_mapping isa CategoricalColorMapping
        :categorical
    elseif color_mapping isa ManualColorMapping
        :manual
    elseif color_mapping isa GrayscaleMapping
        :grayscale
    else
        :unknown
    end
end

"""
    _render_dispatch(smld, target, config) -> (image, info)

Dispatch to appropriate rendering function based on config.
Constructs ColorMapping from flat config fields, then renders.
"""
function _render_dispatch(smld, target::Image2DTarget, config::RenderConfig)
    t_start = time()

    # Construct color mapping from flat config fields
    color_mapping = _determine_color_mapping(config)

    # Extract field value range if using field-based coloring (for colorbar metadata)
    field_value_range = nothing
    if color_mapping isa FieldColorMapping
        field_value_range, _ = prepare_field_range(smld, color_mapping)
    elseif color_mapping isa CategoricalColorMapping
        field = color_mapping.field
        if hasproperty(smld.emitters, field)
            vals = getproperty(smld.emitters, field)
            if !isempty(vals)
                field_value_range = (Float64(minimum(vals)), Float64(maximum(vals)))
            end
        end
    end

    # Dispatch on strategy type
    strategy = config.strategy
    if strategy isa HistogramRender
        img = render_histogram(smld, target, color_mapping)
    elseif strategy isa GaussianRender
        img = render_gaussian(smld, target, strategy, color_mapping;
                             clip_percentile=config.clip_percentile)
    elseif strategy isa CircleRender
        img = render_circle(smld, target, strategy, color_mapping)
    elseif strategy isa EllipseRender
        img = render_ellipse(smld, target, strategy, color_mapping)
    else
        error("Unsupported rendering strategy: $(typeof(strategy))")
    end

    elapsed_s = time() - t_start

    # Build RenderInfo
    info = RenderInfo(
        elapsed_s = elapsed_s,
        backend = config.backend,
        device_id = 0,  # CPU = 0
        n_emitters_rendered = length(smld.emitters),
        output_size = (size(img, 1), size(img, 2)),
        pixel_size_nm = target.pixel_size,
        strategy = _strategy_symbol(strategy),
        color_mode = _color_mode_symbol(color_mapping),
        field_range = field_value_range
    )

    return (img, info)
end

"""
    _normalize_rgb_image(img::Matrix{RGB{Float64}})

Normalize RGB image to [0, 1] based on max channel value.
"""
function _normalize_rgb_image(img::Matrix{RGB{Float64}})
    max_val = maximum([maximum(c.r for c in img),
                      maximum(c.g for c in img),
                      maximum(c.b for c in img)])

    if max_val ≈ 0
        return img
    end

    return img ./ max_val
end
