# Gaussian blob rendering for SMLMRender.jl

using Colors

"""
    render_gaussian(smld, target::Image2DTarget, strategy::GaussianRender,
                   color_mapping::ColorMapping)

Render SMLD data as Gaussian blobs.

Each localization is rendered as a 2D Gaussian distribution.
Provides smooth, publication-quality images with sub-pixel accuracy.

# Arguments
- `smld`: SMLD dataset with .emitters field
- `target`: Image2DTarget specifying output dimensions
- `strategy`: GaussianRender strategy parameters
- `color_mapping`: ColorMapping specification

Returns Matrix{RGB{Float64}}
"""
function render_gaussian(smld, target::Image2DTarget, strategy::GaussianRender,
                        color_mapping::ColorMapping)
    if color_mapping isa IntensityColorMapping
        return render_gaussian_intensity(smld, target, strategy, color_mapping)
    elseif color_mapping isa FieldColorMapping
        return render_gaussian_field(smld, target, strategy, color_mapping)
    elseif color_mapping isa ManualColorMapping
        return render_gaussian_manual(smld, target, strategy, color_mapping)
    elseif color_mapping isa GrayscaleMapping
        return render_gaussian_grayscale(smld, target, strategy)
    else
        error("Unsupported color mapping type for Gaussian render")
    end
end

"""
    render_gaussian_intensity(smld, target, strategy, mapping::IntensityColorMapping)

Gaussian render with intensity colormap.

Process: accumulate grayscale Gaussian blobs → normalize → apply colormap
"""
function render_gaussian_intensity(smld, target::Image2DTarget,
                                  strategy::GaussianRender,
                                  mapping::IntensityColorMapping)
    # Accumulate intensity
    intensity = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        # Get covariance values
        sigma_x, sigma_y, sigma_xy = get_emitter_covariance(emitter, strategy)

        # Skip if sigma is too small or too large
        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        # Render this blob
        render_gaussian_blob!(intensity, emitter, target, sigma_x, sigma_y,
                            strategy.n_sigmas, strategy.normalization, 1.0;
                            sigma_xy=sigma_xy)
    end

    # Apply intensity colormap
    return apply_intensity_colormap(intensity, mapping)
end

"""
    render_gaussian_field(smld, target, strategy, mapping::FieldColorMapping)

Gaussian render with field-based coloring.

Each blob is colored according to its field value.
"""
function render_gaussian_field(smld, target::Image2DTarget,
                              strategy::GaussianRender,
                              mapping::FieldColorMapping)
    # Use intensity-weighted color algorithm
    # Track both intensity and color numerators for proper weighting

    intensity = zeros(Float64, target.height, target.width)  # Total intensity (S)
    r_num = zeros(Float64, target.height, target.width)      # Red numerator
    g_num = zeros(Float64, target.height, target.width)      # Green numerator
    b_num = zeros(Float64, target.height, target.width)      # Blue numerator

    # Determine value range and frame_offsets (for :absolute_frame support)
    value_range, frame_offsets = prepare_field_range(smld, mapping)

    for emitter in smld.emitters
        # Get covariance values
        sigma_x, sigma_y, sigma_xy = get_emitter_covariance(emitter, strategy)

        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        # Get color for this emitter
        color = get_emitter_color(emitter, mapping; value_range=value_range,
                                  frame_offsets=frame_offsets)

        # Render blob, accumulating both intensity and color
        render_gaussian_blob_weighted!(intensity, r_num, g_num, b_num,
                                       emitter, target, sigma_x, sigma_y,
                                       strategy.n_sigmas, strategy.normalization,
                                       color; sigma_xy=sigma_xy)
    end

    # Compute intensity-weighted color with gamma correction
    return apply_intensity_weighted_color(intensity, r_num, g_num, b_num)
end

"""
    render_gaussian_manual(smld, target, strategy, mapping::ManualColorMapping)

Gaussian render with single manual color.
"""
function render_gaussian_manual(smld, target::Image2DTarget,
                                strategy::GaussianRender,
                                mapping::ManualColorMapping)
    result = zeros(RGB{Float64}, target.height, target.width)

    for emitter in smld.emitters
        sigma_x, sigma_y, sigma_xy = get_emitter_covariance(emitter, strategy)

        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        render_gaussian_blob_colored!(result, emitter, target, sigma_x, sigma_y,
                                     strategy.n_sigmas, strategy.normalization,
                                     mapping.color; sigma_xy=sigma_xy)
    end

    return result
end

"""
    render_gaussian_grayscale(smld, target, strategy)

Gaussian render returning grayscale image (as RGB for consistency).
"""
function render_gaussian_grayscale(smld, target::Image2DTarget,
                                  strategy::GaussianRender)
    intensity = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        sigma_x, sigma_y, sigma_xy = get_emitter_covariance(emitter, strategy)

        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        render_gaussian_blob!(intensity, emitter, target, sigma_x, sigma_y,
                            strategy.n_sigmas, strategy.normalization, 1.0;
                            sigma_xy=sigma_xy)
    end

    # Convert to RGB grayscale
    intensity_norm = normalize_to_01(intensity)
    result = similar(intensity, RGB{Float64})
    for i in eachindex(intensity_norm)
        gray_val = intensity_norm[i]
        result[i] = RGB{Float64}(gray_val, gray_val, gray_val)
    end

    return result
end

"""
    get_emitter_sigma(emitter, strategy::GaussianRender)

Get sigma_x, sigma_y for an emitter based on strategy settings.

Returns (sigma_x_nm, sigma_y_nm)
"""
function get_emitter_sigma(emitter, strategy::GaussianRender)
    if strategy.use_localization_precision
        # Use σ_x, σ_y from emitter data (in μm)
        # Convert to nm
        sigma_x = emitter.σ_x * 1000.0
        sigma_y = emitter.σ_y * 1000.0
    else
        # Use fixed sigma
        sigma_x = strategy.fixed_sigma
        sigma_y = strategy.fixed_sigma
    end

    return (sigma_x, sigma_y)
end

"""
    get_emitter_covariance(emitter, strategy::GaussianRender)

Get full covariance (σ_x, σ_y, σ_xy) for an emitter based on strategy settings.

Returns (sigma_x_nm, sigma_y_nm, sigma_xy_nm²) where σ_xy is covariance (not correlation).
"""
function get_emitter_covariance(emitter, strategy::GaussianRender)
    if strategy.use_localization_precision
        # Use σ_x, σ_y from emitter data (in μm), convert to nm
        sigma_x = emitter.σ_x * 1000.0
        sigma_y = emitter.σ_y * 1000.0

        # Get σ_xy if available (in μm²), convert to nm²
        if hasproperty(emitter, :σ_xy)
            val = getproperty(emitter, :σ_xy)
            sigma_xy = (val === nothing ? 0.0 : Float64(val)) * 1e6  # μm² to nm²
        else
            sigma_xy = 0.0
        end
    else
        # Use fixed sigma, no covariance
        sigma_x = strategy.fixed_sigma
        sigma_y = strategy.fixed_sigma
        sigma_xy = 0.0
    end

    return (sigma_x, sigma_y, sigma_xy)
end

"""
    render_gaussian_blob!(img::Matrix{Float64}, emitter, target, sigma_x, sigma_y,
                         n_sigmas, normalization, weight; sigma_xy=0.0)

Render a single Gaussian blob to grayscale accumulator.

Supports rotated Gaussians when σ_xy (covariance) is non-zero.

# Arguments
- `img`: Accumulator (modified in-place)
- `emitter`: Emitter with x, y position
- `target`: Image2DTarget
- `sigma_x, sigma_y`: Standard deviations in nm
- `n_sigmas`: How many σ to render
- `normalization`: :integral or :maximum
- `weight`: Multiplicative weight (default: 1.0)
- `sigma_xy`: Covariance in nm² (default: 0.0 for axis-aligned)
"""
function render_gaussian_blob!(img::Matrix{Float64}, emitter, target::Image2DTarget,
                               sigma_x::Float64, sigma_y::Float64,
                               n_sigmas::Float64, normalization::Symbol,
                               weight::Float64; sigma_xy::Float64=0.0)
    # Convert emitter position to continuous pixel coordinates
    x_pixel, y_pixel = physical_to_pixel(emitter.x, emitter.y, target)

    # Convert sigma from nm to pixels
    sigma_x_pix = sigma_x / target.pixel_size
    sigma_y_pix = sigma_y / target.pixel_size
    sigma_xy_pix = sigma_xy / target.pixel_size^2  # nm² to pix²

    # Determine bounding box (use larger sigma for rotated case)
    max_sigma = max(sigma_x_pix, sigma_y_pix)
    half_width = ceil(Int, n_sigmas * max_sigma)

    j_min = max(1, floor(Int, x_pixel) - half_width)
    j_max = min(target.width, ceil(Int, x_pixel) + half_width)
    i_min = max(1, floor(Int, y_pixel) - half_width)
    i_max = min(target.height, ceil(Int, y_pixel) + half_width)

    # Covariance matrix: Σ = [σ_x²   σ_xy]
    #                        [σ_xy   σ_y²]
    var_x = sigma_x_pix^2
    var_y = sigma_y_pix^2
    det = var_x * var_y - sigma_xy_pix^2

    # Check for valid covariance (positive definite)
    if det <= 0
        # Fall back to axis-aligned if covariance is invalid
        sigma_xy_pix = 0.0
        det = var_x * var_y
    end

    # Inverse covariance matrix elements (scaled by 0.5 for exponent)
    # Σ⁻¹ = (1/det) * [σ_y²   -σ_xy]
    #                  [-σ_xy   σ_x²]
    inv_det_half = 0.5 / det
    a = var_y * inv_det_half      # coefficient for dx²
    b = -sigma_xy_pix * inv_det_half  # coefficient for dx*dy (×2)
    c = var_x * inv_det_half      # coefficient for dy²

    # Normalization factor
    if normalization == :integral
        # 1 / (2π * sqrt(det))
        norm_factor = weight / (2π * sqrt(det))
    else  # :maximum
        norm_factor = weight
    end

    # Render blob
    for i in i_min:i_max, j in j_min:j_max
        # Distance from blob center
        dx = Float64(j) - x_pixel
        dy = Float64(i) - y_pixel

        # Gaussian value: exp(-0.5 * [dx,dy] * Σ⁻¹ * [dx,dy]')
        exponent = -(a * dx^2 + 2.0 * b * dx * dy + c * dy^2)
        value = exp(exponent) * norm_factor

        # Accumulate
        img[i, j] += value
    end
end

"""
    render_gaussian_blob_colored!(img::Matrix{RGB{Float64}}, emitter, target,
                                  sigma_x, sigma_y, n_sigmas, normalization, color;
                                  sigma_xy=0.0)

Render a single Gaussian blob to RGB accumulator with specified color.

Supports rotated Gaussians when σ_xy (covariance) is non-zero.
"""
function render_gaussian_blob_colored!(img::Matrix{RGB{Float64}}, emitter,
                                      target::Image2DTarget,
                                      sigma_x::Float64, sigma_y::Float64,
                                      n_sigmas::Float64, normalization::Symbol,
                                      color::RGB{Float64}; sigma_xy::Float64=0.0)
    x_pixel, y_pixel = physical_to_pixel(emitter.x, emitter.y, target)

    sigma_x_pix = sigma_x / target.pixel_size
    sigma_y_pix = sigma_y / target.pixel_size
    sigma_xy_pix = sigma_xy / target.pixel_size^2

    max_sigma = max(sigma_x_pix, sigma_y_pix)
    half_width = ceil(Int, n_sigmas * max_sigma)

    j_min = max(1, floor(Int, x_pixel) - half_width)
    j_max = min(target.width, ceil(Int, x_pixel) + half_width)
    i_min = max(1, floor(Int, y_pixel) - half_width)
    i_max = min(target.height, ceil(Int, y_pixel) + half_width)

    var_x = sigma_x_pix^2
    var_y = sigma_y_pix^2
    det = var_x * var_y - sigma_xy_pix^2

    if det <= 0
        sigma_xy_pix = 0.0
        det = var_x * var_y
    end

    inv_det_half = 0.5 / det
    a = var_y * inv_det_half
    b = -sigma_xy_pix * inv_det_half
    c = var_x * inv_det_half

    if normalization == :integral
        norm_factor = 1.0 / (2π * sqrt(det))
    else
        norm_factor = 1.0
    end

    for i in i_min:i_max, j in j_min:j_max
        dx = Float64(j) - x_pixel
        dy = Float64(i) - y_pixel

        exponent = -(a * dx^2 + 2.0 * b * dx * dy + c * dy^2)
        value = exp(exponent) * norm_factor

        img[i, j] += color * value
    end
end

"""
    render_gaussian_blob_weighted!(intensity, r_num, g_num, b_num, emitter, target,
                                   sigma_x, sigma_y, n_sigmas, normalization, color;
                                   sigma_xy=0.0)

Render Gaussian blob accumulating both intensity and color numerators.
This enables intensity-weighted color rendering.

Supports rotated Gaussians when σ_xy (covariance) is non-zero.
"""
function render_gaussian_blob_weighted!(intensity::Matrix{Float64},
                                       r_num::Matrix{Float64},
                                       g_num::Matrix{Float64},
                                       b_num::Matrix{Float64},
                                       emitter, target::Image2DTarget,
                                       sigma_x::Float64, sigma_y::Float64,
                                       n_sigmas::Float64, normalization::Symbol,
                                       color::RGB{Float64}; sigma_xy::Float64=0.0)
    x_pixel, y_pixel = physical_to_pixel(emitter.x, emitter.y, target)

    sigma_x_pix = sigma_x / target.pixel_size
    sigma_y_pix = sigma_y / target.pixel_size
    sigma_xy_pix = sigma_xy / target.pixel_size^2

    max_sigma = max(sigma_x_pix, sigma_y_pix)
    half_width = ceil(Int, n_sigmas * max_sigma)

    j_min = max(1, floor(Int, x_pixel) - half_width)
    j_max = min(target.width, ceil(Int, x_pixel) + half_width)
    i_min = max(1, floor(Int, y_pixel) - half_width)
    i_max = min(target.height, ceil(Int, y_pixel) + half_width)

    var_x = sigma_x_pix^2
    var_y = sigma_y_pix^2
    det = var_x * var_y - sigma_xy_pix^2

    if det <= 0
        sigma_xy_pix = 0.0
        det = var_x * var_y
    end

    inv_det_half = 0.5 / det
    a = var_y * inv_det_half
    b = -sigma_xy_pix * inv_det_half
    c = var_x * inv_det_half

    if normalization == :integral
        norm_factor = 1.0 / (2π * sqrt(det))
    else
        norm_factor = 1.0
    end

    for i in i_min:i_max, j in j_min:j_max
        dx = Float64(j) - x_pixel
        dy = Float64(i) - y_pixel

        exponent = -(a * dx^2 + 2.0 * b * dx * dy + c * dy^2)
        w = exp(exponent) * norm_factor

        intensity[i, j] += w
        r_num[i, j] += w * color.r
        g_num[i, j] += w * color.g
        b_num[i, j] += w * color.b
    end
end
