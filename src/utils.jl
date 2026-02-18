# Utility functions for SMLMRender.jl

using Statistics
using ColorSchemes
import FileIO  # For save_image function
import CairoMakie  # For export_colorbar function

# ============================================================================
# Frame offset computation for absolute_frame support
# ============================================================================

"""
    compute_frame_offsets(smld)

Compute cumulative frame offsets per dataset for absolute frame calculation.

When rendering multiple datasets where each dataset's `frame` starts at 1,
this computes offsets so `absolute_frame = frame + offset[dataset]` gives
a continuous frame number across all datasets.

Returns `Dict{Int, Int}` mapping `dataset_id => frame_offset`.

# Example
```julia
# Dataset 1: frames 1-100, Dataset 2: frames 1-50
offsets = compute_frame_offsets(smld)  # {1 => 0, 2 => 100}
# Emitter in dataset 2, frame 25 → absolute_frame = 25 + 100 = 125
```
"""
function compute_frame_offsets(smld)
    # Find max frame per dataset
    max_frames = Dict{Int, Int}()
    for e in smld.emitters
        ds = e.dataset
        max_frames[ds] = max(get(max_frames, ds, 0), e.frame)
    end

    # Compute cumulative offsets (sorted by dataset id)
    datasets = sort(collect(keys(max_frames)))
    offsets = Dict{Int, Int}()
    cumulative = 0
    for ds in datasets
        offsets[ds] = cumulative
        cumulative += max_frames[ds]
    end
    return offsets
end

"""
    get_field_value(emitter, field::Symbol; frame_offsets=nothing)

Get field value from emitter, handling computed fields like `:absolute_frame`.

# Arguments
- `emitter`: Emitter object
- `field`: Field name (`:z`, `:photons`, `:frame`, `:absolute_frame`, etc.)
- `frame_offsets`: Required when `field === :absolute_frame`, from `compute_frame_offsets()`

# Example
```julia
offsets = compute_frame_offsets(smld)
abs_frame = get_field_value(emitter, :absolute_frame; frame_offsets=offsets)
photons = get_field_value(emitter, :photons)
```
"""
function get_field_value(emitter, field::Symbol; frame_offsets=nothing)
    if field === :absolute_frame
        if frame_offsets === nothing
            error(":absolute_frame requires frame_offsets to be precomputed via compute_frame_offsets()")
        end
        return emitter.frame + frame_offsets[emitter.dataset]
    else
        return getfield(emitter, field)
    end
end

"""
    physical_to_pixel(x_phys, y_phys, target::Image2DTarget)

Convert physical coordinates (μm) to continuous pixel coordinates.

Returns (x_pixel, y_pixel) where (1.0, 1.0) is the center of the top-left pixel.
"""
function physical_to_pixel(x_phys::Real, y_phys::Real, target::Image2DTarget)
    # Convert μm to nm
    x_nm = x_phys * 1000
    y_nm = y_phys * 1000

    # Get range in nm
    x_min_nm = target.x_range[1] * 1000
    y_min_nm = target.y_range[1] * 1000

    # Pixel centers are at (i-0.5)*pixel_size offset from origin
    # So pixel 1 center is at 0.5*pixel_size
    # If x_nm = 0.5*pixel_size, we want x_pixel = 1.0
    x_pixel = (x_nm - x_min_nm) / target.pixel_size + 0.5
    y_pixel = (y_nm - y_min_nm) / target.pixel_size + 0.5

    return (x_pixel, y_pixel)
end

"""
    physical_to_pixel_index(x_phys, y_phys, target::Image2DTarget)

Convert physical coordinates (μm) to integer pixel indices.

Returns (i, j) where valid indices are in [1, height] × [1, width].
"""
function physical_to_pixel_index(x_phys::Real, y_phys::Real, target::Image2DTarget)
    x_pixel, y_pixel = physical_to_pixel(x_phys, y_phys, target)
    i = round(Int, y_pixel)
    j = round(Int, x_pixel)
    return (i, j)
end

"""
    in_bounds(i, j, target::Image2DTarget)

Check if pixel indices (i, j) are within image bounds.
"""
function in_bounds(i::Int, j::Int, target::Image2DTarget)
    return 1 <= i <= target.height && 1 <= j <= target.width
end

"""
    create_target_from_smld(smld; pixel_size=nothing, zoom=nothing, roi=nothing, margin=0.05)

Create an Image2DTarget for rendering.

When `zoom` is specified with camera data, renders the EXACT camera FOV with
subdivided pixels (camera_pixels × zoom). When `pixel_size` is specified,
uses data bounds with margin.

# Arguments
- `smld`: SMLD dataset (must have .emitters field)
- `pixel_size`: Pixel size in nm (uses data bounds + margin)
- `zoom`: Zoom factor - renders exact camera FOV with camera_pixels × zoom output
- `roi`: Camera pixel ROI as `(x_range, y_range)`. Use `:` for full range.
  Example: `roi=(430:860, 1:256)` or `roi=(430:860, :)` for full y.
  Only used with `zoom` mode.
- `margin`: Fractional margin for data bounds mode (default: 5%)

Either `pixel_size` or `zoom` must be specified.
"""
function create_target_from_smld(smld; pixel_size=nothing, zoom=nothing, roi=nothing, margin=0.05)
    @assert pixel_size !== nothing || zoom !== nothing "Must specify either pixel_size or zoom"

    # Mode 1: zoom specified - use EXACT camera FOV (or ROI subset)
    if zoom !== nothing
        @assert hasfield(typeof(smld), :camera) "zoom requires smld.camera"

        camera = smld.camera
        camera_pixel_size = get_camera_pixel_size(camera)  # nm
        pixel_size = camera_pixel_size / zoom

        # Determine pixel ranges (handle roi parameter)
        n_camera_px_x = length(camera.pixel_edges_x) - 1
        n_camera_px_y = length(camera.pixel_edges_y) - 1

        if roi === nothing
            # Full camera FOV
            x_range = 1:n_camera_px_x
            y_range = 1:n_camera_px_y
        else
            # ROI specified - handle Colon for full range
            x_range = roi[1] isa Colon ? (1:n_camera_px_x) : roi[1]
            y_range = roi[2] isa Colon ? (1:n_camera_px_y) : roi[2]
        end

        # Get physical bounds from camera pixel edges
        # pixel_edges_x[i] is the left edge of pixel i, pixel_edges_x[i+1] is right edge
        x_min = camera.pixel_edges_x[first(x_range)]
        x_max = camera.pixel_edges_x[last(x_range) + 1]
        y_min = camera.pixel_edges_y[first(y_range)]
        y_max = camera.pixel_edges_y[last(y_range) + 1]

        # Output dimensions: roi_pixels × zoom
        width = round(Int, length(x_range) * zoom)
        height = round(Int, length(y_range) * zoom)

    # Mode 2: pixel_size specified - use data bounds + margin
    else
        emitters = smld.emitters
        x_coords = [e.x for e in emitters]
        y_coords = [e.y for e in emitters]

        x_min, x_max = extrema(x_coords)
        y_min, y_max = extrema(y_coords)

        # Add margin
        x_span = x_max - x_min
        y_span = y_max - y_min
        x_min -= margin * x_span
        x_max += margin * x_span
        y_min -= margin * y_span
        y_max += margin * y_span

        # Calculate image dimensions
        width = ceil(Int, (x_max - x_min) * 1000 / pixel_size)
        height = ceil(Int, (y_max - y_min) * 1000 / pixel_size)
    end

    return Image2DTarget(width, height, pixel_size, (x_min, x_max), (y_min, y_max))
end

"""
    get_camera_pixel_size(camera)

Get pixel size in nm from camera object.
"""
function get_camera_pixel_size(camera)
    # For IdealCamera and SCMOSCamera, assume square pixels
    # Pixel size = difference between first two pixel edges
    if length(camera.pixel_edges_x) >= 2
        return (camera.pixel_edges_x[2] - camera.pixel_edges_x[1]) * 1000  # μm to nm
    else
        error("Cannot determine pixel size from camera")
    end
end

"""
    calculate_field_range(smld, field::Symbol, clip_percentiles; frame_offsets=nothing)

Calculate range of field values, optionally with percentile clipping.

# Arguments
- `smld`: SMLD dataset
- `field`: Field name (`:z`, `:photons`, `:absolute_frame`, etc.)
- `clip_percentiles`: Tuple `(low, high)` for percentile clipping, or `nothing`
- `frame_offsets`: Required when `field === :absolute_frame`

Returns `(min_val, max_val)`
"""
function calculate_field_range(smld, field::Symbol, clip_percentiles; frame_offsets=nothing)
    # Precompute frame offsets if needed and not provided
    if field === :absolute_frame && frame_offsets === nothing
        frame_offsets = compute_frame_offsets(smld)
    end

    values = [get_field_value(e, field; frame_offsets=frame_offsets) for e in smld.emitters]

    if clip_percentiles === nothing
        return extrema(values)
    else
        low, high = clip_percentiles
        min_val = quantile(values, low)
        max_val = quantile(values, high)
        return (min_val, max_val)
    end
end

"""
    clip_at_percentile(img::Matrix{T}, percentile::Real) where T<:Real

Clip image values at specified percentile of NON-ZERO pixels.

For sparse SMLM data, most pixels are zero/background. Computing percentiles
on all pixels would give misleading results. This function computes the
percentile only on pixels with signal (value > 0).

Returns the clipping value used.
"""
function clip_at_percentile(img::Matrix{T}, percentile::Real) where T<:Real
    if percentile >= 1.0
        return maximum(img)
    end

    # Count non-zero pixels and collect them without allocating via filter(vec(...))
    n_nonzero = 0
    @inbounds for v in img
        n_nonzero += (v > 0)
    end
    if n_nonzero == 0
        return zero(T)
    end

    # Collect non-zero values into pre-sized buffer
    nonzero = Vector{T}(undef, n_nonzero)
    idx = 0
    @inbounds for v in img
        if v > 0
            idx += 1
            nonzero[idx] = v
        end
    end

    clip_val = quantile(nonzero, percentile)
    @inbounds for i in eachindex(img)
        img[i] = min(img[i], clip_val)
    end
    return clip_val
end

"""
    normalize_to_01(img::Matrix{T}) where T<:Real

Normalize image to [0, 1] range based on current min/max.
"""
function normalize_to_01(img::Matrix{T}) where T<:Real
    min_val = minimum(img)
    max_val = maximum(img)

    if max_val ≈ min_val
        return fill(T(0.5), size(img))
    end

    scale = one(T) / (max_val - min_val)
    result = similar(img)
    @inbounds for i in eachindex(img)
        result[i] = (img[i] - min_val) * scale
    end
    return result
end

"""
    estimate_memory_usage(n_localizations, width, height, strategy)

Estimate memory usage in bytes for rendering.
"""
function estimate_memory_usage(n_localizations::Int, width::Int, height::Int,
                               strategy::RenderingStrategy)
    # Base image size (RGB Float64)
    image_bytes = width * height * 3 * 8

    if strategy isa GaussianRender
        # Estimate blob patch sizes
        avg_sigma = 20.0  # nm, rough estimate
        patch_size = 2 * strategy.n_sigmas * avg_sigma  # nm
        # Assume we process in batches to limit memory
        batch_bytes = min(8 * 1024^3, n_localizations * patch_size^2 * 8)  # 8 GB limit
        return image_bytes + batch_bytes
    elseif strategy isa CircleRender
        # Circles are rendered on-the-fly, minimal extra memory
        return image_bytes + width * height * 8  # One working buffer
    else  # HistogramRender
        # Minimal memory for histogram
        return image_bytes + width * height * 16  # Intensity + field accumulators
    end
end

"""
    gaussian_2d(x, y, center_x, center_y, sigma_x, sigma_y, normalization)

Evaluate 2D Gaussian at point (x, y).

# Arguments
- `x, y`: Evaluation point
- `center_x, center_y`: Gaussian center
- `sigma_x, sigma_y`: Standard deviations
- `normalization`: :integral (sum to 1) or :maximum (peak to 1)
"""
function gaussian_2d(x::Real, y::Real, center_x::Real, center_y::Real,
                    sigma_x::Real, sigma_y::Real, normalization::Symbol)
    dx = x - center_x
    dy = y - center_y

    # Precompute for efficiency
    inv_2sigma_x2 = 1.0 / (2.0 * sigma_x^2)
    inv_2sigma_y2 = 1.0 / (2.0 * sigma_y^2)

    exponent = -(dx^2 * inv_2sigma_x2 + dy^2 * inv_2sigma_y2)
    value = exp(exponent)

    if normalization == :integral
        # Normalize so integral = 1
        # Integral of 2D Gaussian = 2π σ_x σ_y
        norm_factor = 1.0 / (2π * sigma_x * sigma_y)
        return value * norm_factor
    else  # :maximum
        # Peak value = 1
        return value
    end
end

"""
    draw_antialiased_point!(img::Matrix{RGB{Float64}}, x, y, color, thickness)

Draw an anti-aliased point at continuous coordinates (x, y).

Primary pixel gets full intensity, neighbors get AA fringe for smooth edges.
"""
function draw_antialiased_point!(img::Matrix{RGB{Float64}}, x::Real, y::Real,
                                 color::RGB{Float64}, thickness::Real)
    # Get nearest pixel coordinates
    i0 = round(Int, y)
    j0 = round(Int, x)

    thickness_factor = min(1.0, thickness)

    # Primary pixel gets full intensity
    if 1 <= i0 <= size(img, 1) && 1 <= j0 <= size(img, 2)
        img[i0, j0] += color * thickness_factor
    end

    # AA fringe to neighbors based on sub-pixel position
    # Distance from point to pixel center determines fringe intensity
    fy = y - i0  # ranges from -0.5 to 0.5
    fx = x - j0

    # Add small contribution to neighbors for anti-aliasing
    aa_strength = 0.3 * thickness_factor  # fringe intensity

    # Horizontal neighbors
    if abs(fx) > 0.1
        j_neighbor = fx > 0 ? j0 + 1 : j0 - 1
        if 1 <= i0 <= size(img, 1) && 1 <= j_neighbor <= size(img, 2)
            img[i0, j_neighbor] += color * aa_strength * abs(fx)
        end
    end

    # Vertical neighbors
    if abs(fy) > 0.1
        i_neighbor = fy > 0 ? i0 + 1 : i0 - 1
        if 1 <= i_neighbor <= size(img, 1) && 1 <= j0 <= size(img, 2)
            img[i_neighbor, j0] += color * aa_strength * abs(fy)
        end
    end
end

"""
    save_image(filename::String, img::Matrix{RGB})

Save rendered image directly to file.

Supports PNG, TIFF, and other formats via FileIO/ImageIO.
The image is saved with proper orientation for SMLM visualization.

# Arguments
- `filename`: Output file path (extension determines format)
- `img`: RGB image matrix from render()

# Example
```julia
img = render(smld, zoom=10)
save_image("output.png", img)
```
"""
function save_image(filename::String, img::AbstractMatrix{<:Colorant})
    # Clamp RGB values to [0,1] to avoid overflow errors
    # TODO: Fix this in rendering functions instead
    img_clamped = map(img) do pixel
        RGB(clamp(pixel.r, 0.0, 1.0),
            clamp(pixel.g, 0.0, 1.0),
            clamp(pixel.b, 0.0, 1.0))
    end

    # Save directly using FileIO (will dispatch to ImageIO)
    FileIO.save(filename, img_clamped)

    return nothing
end

"""
    export_colorbar(result::RenderResult2D, filename::String; kwargs...)
    export_colorbar(colormap::Symbol, value_range::Tuple, label::String, filename::String; kwargs...)

Export a colorbar legend showing the field value to color mapping.

# Arguments
- `result::RenderResult2D`: Render result with field metadata (easiest way)
- OR manually specify: `colormap`, `value_range`, `label`
- `filename`: Output file path

# Keyword Arguments
- `orientation::Symbol`: :vertical (default) or :horizontal
- `size::Tuple{Int,Int}`: (width, height) in pixels, default (80, 400) for vertical
- `fontsize::Int`: Label font size, default 14
- `tickfontsize::Int`: Tick label font size, default 12

# Examples
```julia
# Easy way: from render result
result = render(smld, color_by=:z, colormap=:turbo, output_type=:result)
export_colorbar(result, "colorbar.png")

# Manual way
export_colorbar(:turbo, (-500, 500), "Z-depth (nm)", "colorbar.png")
```
"""
function export_colorbar(result::RenderResult2D, filename::String; kwargs...)
    # Extract metadata from result
    if !(result.options.color_mapping isa FieldColorMapping)
        error("Colorbar export only supported for field-based coloring (use color_by=...)")
    end

    mapping = result.options.color_mapping
    colormap = mapping.colormap
    value_range = result.field_value_range

    if value_range === nothing
        error("No field value range available in result")
    end

    # Create label from field name
    label = string(mapping.field)

    return export_colorbar(colormap, value_range, label, filename; kwargs...)
end

function export_colorbar(colormap::Symbol, value_range::Tuple{Real, Real},
                        label::String, filename::String;
                        orientation::Symbol = :vertical,
                        size::Tuple{Int,Int} = (80, 400),
                        fontsize::Int = 14,
                        tickfontsize::Int = 12)

    # Get colormap (ColorSchemes imported at top of file)
    cmap = colorschemes[colormap]

    # Create figure
    fig = CairoMakie.Figure(size=size, backgroundcolor=:white)

    if orientation == :vertical
        # Vertical colorbar
        ax = CairoMakie.Axis(fig[1, 1],
            ylabel = label,
            ylabelsize = fontsize,
            yticklabelsize = tickfontsize
        )

        # Create colorbar as heatmap
        data = reshape(range(value_range[1], value_range[2], length=100), 1, :)
        CairoMakie.heatmap!(ax, [0, 1], range(value_range[1], value_range[2], length=100),
                           data, colormap=colormap)
        CairoMakie.hidedecorations!(ax, label=false, ticklabels=false, ticks=false)
        CairoMakie.hidexdecorations!(ax)
    else
        # Horizontal colorbar
        ax = CairoMakie.Axis(fig[1, 1],
            xlabel = label,
            xlabelsize = fontsize,
            xticklabelsize = tickfontsize
        )

        data = reshape(range(value_range[1], value_range[2], length=100), :, 1)
        CairoMakie.heatmap!(ax, range(value_range[1], value_range[2], length=100), [0, 1],
                           data, colormap=colormap)
        CairoMakie.hidedecorations!(ax, label=false, ticklabels=false, ticks=false)
        CairoMakie.hideydecorations!(ax)
    end

    # Save
    CairoMakie.save(filename, fig)

    return nothing
end
