# Main interface for SMLMRender.jl

using Colors

"""
    render(smld; kwargs...)

Main rendering interface using keyword arguments for convenient usage.

# Keyword Arguments
- `strategy`: RenderingStrategy (default: GaussianRender())
- `pixel_size`: Pixel size in nm (overrides zoom)
- `zoom`: Zoom factor relative to camera pixels
- `colormap`: Symbol for colormap name (for intensity mapping)
- `color_by`: Field symbol for field-based coloring
- `color`: Manual RGB color
- `clip_percentile`: Percentile for intensity clipping (default: 0.999)
- `backend`: :cpu, :cuda, :metal, or :auto (default: :cpu)
- `output_type`: :rgb or :array (default: :rgb)

# Examples
```julia
# Simple intensity render with inferno colormap
img = render(smld, colormap=:inferno, zoom=20)

# Color by z-depth
img = render(smld, color_by=:z, colormap=:viridis, pixel_size=10.0)

# Manual red color
img = render(smld, color=colorant"red", zoom=15)

# Circle rendering
img = render(smld, strategy=CircleRender(2.0, 1.0, true, nothing),
            color_by=:photons, colormap=:plasma)
```
"""
function render(smld;
                # Rendering strategy
                strategy::RenderingStrategy = GaussianRender(),

                # Target specification
                pixel_size::Union{Real, Nothing} = nothing,
                zoom::Union{Real, Nothing} = nothing,
                target::Union{Image2DTarget, Nothing} = nothing,

                # Color mapping (mutually exclusive)
                colormap::Union{Symbol, Nothing} = nothing,
                color_by::Union{Symbol, Nothing} = nothing,
                color::Union{RGB, Nothing} = nothing,

                # Color mapping options
                clip_percentile::Real = 0.999,
                field_range::Union{Tuple{Real, Real}, Symbol} = :auto,
                field_clip_percentiles::Union{Tuple{Real, Real}, Nothing} = (0.01, 0.99),

                # Backend and output
                backend::Symbol = :cpu,
                output_type::Symbol = :rgb,

                # Optional file save
                filename::Union{String, Nothing} = nothing)

    # Create target if not provided
    if target === nothing
        @assert pixel_size !== nothing || zoom !== nothing "Must specify pixel_size, zoom, or target"
        target = create_target_from_smld(smld; pixel_size=pixel_size, zoom=zoom)
    end

    # Determine color mapping
    color_mapping = _determine_color_mapping(colormap, color_by, color,
                                            clip_percentile, field_range,
                                            field_clip_percentiles)

    # Create render options
    options = RenderOptions(strategy, color_mapping;
                          backend=backend, output_type=output_type)

    # Dispatch to appropriate rendering function
    img = _render_dispatch(smld, target, options)

    # Save to file if requested
    if filename !== nothing
        save_image(filename, img)
    end

    return img
end

"""
    render(smld, x_edges, y_edges; kwargs...)

Render with explicit pixel edges.
"""
function render(smld, x_edges::AbstractVector, y_edges::AbstractVector;
                strategy::RenderingStrategy = GaussianRender(),
                colormap::Union{Symbol, Nothing} = nothing,
                color_by::Union{Symbol, Nothing} = nothing,
                color::Union{RGB, Nothing} = nothing,
                clip_percentile::Real = 0.999,
                field_range::Union{Tuple{Real, Real}, Symbol} = :auto,
                field_clip_percentiles::Union{Tuple{Real, Real}, Nothing} = (0.01, 0.99),
                backend::Symbol = :cpu,
                output_type::Symbol = :rgb,
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

    # Use main render function
    return render(smld; target=target, strategy=strategy, colormap=colormap,
                 color_by=color_by, color=color, clip_percentile=clip_percentile,
                 field_range=field_range, field_clip_percentiles=field_clip_percentiles,
                 backend=backend, output_type=output_type, filename=filename)
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
        # Use first dataset to determine bounds, but include all datasets
        @assert pixel_size !== nothing || zoom !== nothing "Must specify pixel_size, zoom, or target"
        target = create_target_from_smld(smlds[1]; pixel_size=pixel_size, zoom=zoom)
    end

    # Render each dataset
    images = []
    for (smld, color) in zip(smlds, rgb_colors)
        color_mapping = ManualColorMapping(RGB{Float64}(color))
        options = RenderOptions(strategy, color_mapping; backend=backend, output_type=:rgb)
        img = _render_dispatch(smld, target, options)
        push!(images, img)
    end

    # Normalize each independently if requested
    if normalize_each
        for i in eachindex(images)
            images[i] = _normalize_rgb_image(images[i])
        end
    end

    # Combine additively
    result = zeros(RGB{Float64}, size(images[1]))
    for img in images
        result .+= img
    end

    # Clip to white (need to clamp each channel separately)
    for i in eachindex(result)
        pixel = result[i]
        result[i] = RGB(clamp(pixel.r, 0.0, 1.0),
                       clamp(pixel.g, 0.0, 1.0),
                       clamp(pixel.b, 0.0, 1.0))
    end

    # Save to file if requested
    if filename !== nothing
        save_image(filename, result)
    end

    return result
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
    _determine_color_mapping(colormap, color_by, color, clip_percentile,
                            field_range, field_clip_percentiles)

Determine color mapping from keyword arguments.
"""
function _determine_color_mapping(colormap, color_by, color,
                                  clip_percentile, field_range,
                                  field_clip_percentiles)
    # Check for invalid combinations
    if color !== nothing && (colormap !== nothing || color_by !== nothing)
        error("color cannot be combined with colormap or color_by")
    end

    # Determine which mapping to use
    if color_by !== nothing
        # Field-based coloring
        # Use specified colormap or default to turbo (high contrast, napari standard)
        field_colormap = colormap !== nothing ? colormap : :turbo
        return FieldColorMapping(color_by, field_colormap, field_range,
                                field_clip_percentiles)
    elseif colormap !== nothing
        # Intensity-based coloring
        return IntensityColorMapping(colormap, clip_percentile)
    elseif color !== nothing
        # Manual color
        return ManualColorMapping(RGB{Float64}(color))
    else
        # Default: intensity with inferno
        return IntensityColorMapping(:inferno, clip_percentile)
    end
end

"""
    _render_dispatch(smld, target, options)

Dispatch to appropriate rendering function based on strategy and color mapping.
"""
function _render_dispatch(smld, target::Image2DTarget, options::RenderOptions)
    t_start = time()

    # Extract field value range if using field-based coloring (for colorbar metadata)
    field_value_range = nothing
    if options.color_mapping isa FieldColorMapping
        field_value_range = prepare_field_range(smld, options.color_mapping)
    end

    # Dispatch on strategy type
    if options.strategy isa HistogramRender
        img = render_histogram(smld, target, options.color_mapping)
    elseif options.strategy isa GaussianRender
        img = render_gaussian(smld, target, options.strategy, options.color_mapping)
    elseif options.strategy isa CircleRender
        img = render_circle(smld, target, options.strategy, options.color_mapping)
    else
        error("Unsupported rendering strategy: $(typeof(options.strategy))")
    end

    # Apply contrast if specified
    if options.contrast !== nothing
        img = apply_contrast(img, options.contrast)
    end

    t_end = time()
    render_time = t_end - t_start

    # Create result with field metadata
    n_locs = length(smld.emitters)
    result = RenderResult2D(img, target, options, render_time, n_locs, field_value_range)

    # Return based on output_type
    if options.output_type == :rgb
        return result.image
    elseif options.output_type == :result
        return result  # Return full RenderResult2D with metadata
    else  # :array
        return result
    end
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

"""
    apply_contrast(img::Matrix{RGB{Float64}}, options::ContrastOptions)

Apply contrast enhancement to RGB image.
"""
function apply_contrast(img::Matrix{RGB{Float64}}, options::ContrastOptions)
    # For now, just return img (contrast enhancement can be added in future)
    # This would involve converting RGB to intensity, applying contrast,
    # then mapping back to RGB
    @warn "Contrast enhancement not yet implemented" maxlog=1
    return img
end
