# Utility functions for SMLMRender.jl

using Statistics
import FileIO  # For save_image function

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
    create_target_from_smld(smld; pixel_size=nothing, zoom=nothing, margin=0.05)

Automatically create an Image2DTarget from SMLD data bounds.

# Arguments
- `smld`: SMLD dataset (must have .emitters field)
- `pixel_size`: Pixel size in nm (overrides zoom)
- `zoom`: Zoom factor (pixels per camera pixel)
- `margin`: Fractional margin to add around data (default: 5%)

Either `pixel_size` or `zoom` must be specified.
"""
function create_target_from_smld(smld; pixel_size=nothing, zoom=nothing, margin=0.05)
    @assert pixel_size !== nothing || zoom !== nothing "Must specify either pixel_size or zoom"

    # Get data bounds in μm
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

    # Determine pixel size
    if pixel_size === nothing
        # Get camera pixel size from smld
        camera_pixel_size = get_camera_pixel_size(smld.camera)  # nm
        pixel_size = camera_pixel_size / zoom
    end

    # Calculate image dimensions
    width = ceil(Int, (x_max - x_min) * 1000 / pixel_size)
    height = ceil(Int, (y_max - y_min) * 1000 / pixel_size)

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
    calculate_field_range(smld, field::Symbol, clip_percentiles)

Calculate range of field values, optionally with percentile clipping.

# Arguments
- `smld`: SMLD dataset
- `field`: Field name (:z, :photons, etc.)
- `clip_percentiles`: Tuple (low, high) for percentile clipping, or nothing

Returns (min_val, max_val)
"""
function calculate_field_range(smld, field::Symbol, clip_percentiles)
    values = [getfield(e, field) for e in smld.emitters]

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

Clip image values at specified percentile.

Returns the clipping value used.
"""
function clip_at_percentile(img::Matrix{T}, percentile::Real) where T<:Real
    if percentile >= 1.0
        return maximum(img)
    end

    clip_val = quantile(vec(img), percentile)
    img .= min.(img, clip_val)
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

    return (img .- min_val) ./ (max_val - min_val)
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

Uses bilinear interpolation for sub-pixel rendering.
"""
function draw_antialiased_point!(img::Matrix{RGB{Float64}}, x::Real, y::Real,
                                 color::RGB{Float64}, thickness::Real)
    # Get integer pixel coordinates
    i0 = floor(Int, y)
    j0 = floor(Int, x)

    # Sub-pixel offsets
    fy = y - i0
    fx = x - j0

    # Bilinear weights
    weights = [
        (1 - fx) * (1 - fy),  # Top-left
        fx * (1 - fy),        # Top-right
        (1 - fx) * fy,        # Bottom-left
        fx * fy               # Bottom-right
    ]

    offsets = [(0, 0), (0, 1), (1, 0), (1, 1)]

    # Apply thickness scaling
    thickness_factor = min(1.0, thickness)

    for (w, (di, dj)) in zip(weights, offsets)
        i = i0 + di
        j = j0 + dj
        if 1 <= i <= size(img, 1) && 1 <= j <= size(img, 2)
            img[i, j] += color * w * thickness_factor
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
