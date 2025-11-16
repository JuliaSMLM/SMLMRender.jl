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
        # Get sigma values
        sigma_x, sigma_y = get_emitter_sigma(emitter, strategy)

        # Skip if sigma is too small or too large
        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        # Render this blob
        render_gaussian_blob!(intensity, emitter, target, sigma_x, sigma_y,
                            strategy.n_sigmas, strategy.normalization, 1.0)
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
    # Accumulate RGB
    result = zeros(RGB{Float64}, target.height, target.width)

    # Determine value range
    value_range = prepare_field_range(smld, mapping)

    for emitter in smld.emitters
        # Get sigma values
        sigma_x, sigma_y = get_emitter_sigma(emitter, strategy)

        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        # Get color for this emitter
        color = get_emitter_color(emitter, mapping, value_range)

        # Render colored blob
        render_gaussian_blob_colored!(result, emitter, target, sigma_x, sigma_y,
                                     strategy.n_sigmas, strategy.normalization, color)
    end

    return result
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
        sigma_x, sigma_y = get_emitter_sigma(emitter, strategy)

        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        render_gaussian_blob_colored!(result, emitter, target, sigma_x, sigma_y,
                                     strategy.n_sigmas, strategy.normalization,
                                     mapping.color)
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
        sigma_x, sigma_y = get_emitter_sigma(emitter, strategy)

        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        render_gaussian_blob!(intensity, emitter, target, sigma_x, sigma_y,
                            strategy.n_sigmas, strategy.normalization, 1.0)
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
    render_gaussian_blob!(img::Matrix{Float64}, emitter, target, sigma_x, sigma_y,
                         n_sigmas, normalization, weight)

Render a single Gaussian blob to grayscale accumulator.

# Arguments
- `img`: Accumulator (modified in-place)
- `emitter`: Emitter with x, y position
- `target`: Image2DTarget
- `sigma_x, sigma_y`: Standard deviations in nm
- `n_sigmas`: How many σ to render
- `normalization`: :integral or :maximum
- `weight`: Multiplicative weight (default: 1.0)
"""
function render_gaussian_blob!(img::Matrix{Float64}, emitter, target::Image2DTarget,
                               sigma_x::Float64, sigma_y::Float64,
                               n_sigmas::Float64, normalization::Symbol,
                               weight::Float64)
    # Convert emitter position to continuous pixel coordinates
    x_pixel, y_pixel = physical_to_pixel(emitter.x, emitter.y, target)

    # Convert sigma from nm to pixels
    sigma_x_pix = sigma_x / target.pixel_size
    sigma_y_pix = sigma_y / target.pixel_size

    # Determine bounding box
    half_width_x = ceil(Int, n_sigmas * sigma_x_pix)
    half_width_y = ceil(Int, n_sigmas * sigma_y_pix)

    j_min = max(1, floor(Int, x_pixel) - half_width_x)
    j_max = min(target.width, ceil(Int, x_pixel) + half_width_x)
    i_min = max(1, floor(Int, y_pixel) - half_width_y)
    i_max = min(target.height, ceil(Int, y_pixel) + half_width_y)

    # Precompute for efficiency
    inv_2sigma_x2 = 1.0 / (2.0 * sigma_x_pix^2)
    inv_2sigma_y2 = 1.0 / (2.0 * sigma_y_pix^2)

    # Normalization factor
    if normalization == :integral
        norm_factor = weight / (2π * sigma_x_pix * sigma_y_pix)
    else  # :maximum
        norm_factor = weight
    end

    # Render blob
    for i in i_min:i_max, j in j_min:j_max
        # Distance from blob center
        dx = Float64(j) - x_pixel
        dy = Float64(i) - y_pixel

        # Gaussian value
        exponent = -(dx^2 * inv_2sigma_x2 + dy^2 * inv_2sigma_y2)
        value = exp(exponent) * norm_factor

        # Accumulate
        img[i, j] += value
    end
end

"""
    render_gaussian_blob_colored!(img::Matrix{RGB{Float64}}, emitter, target,
                                  sigma_x, sigma_y, n_sigmas, normalization, color)

Render a single Gaussian blob to RGB accumulator with specified color.
"""
function render_gaussian_blob_colored!(img::Matrix{RGB{Float64}}, emitter,
                                      target::Image2DTarget,
                                      sigma_x::Float64, sigma_y::Float64,
                                      n_sigmas::Float64, normalization::Symbol,
                                      color::RGB{Float64})
    x_pixel, y_pixel = physical_to_pixel(emitter.x, emitter.y, target)

    sigma_x_pix = sigma_x / target.pixel_size
    sigma_y_pix = sigma_y / target.pixel_size

    half_width_x = ceil(Int, n_sigmas * sigma_x_pix)
    half_width_y = ceil(Int, n_sigmas * sigma_y_pix)

    j_min = max(1, floor(Int, x_pixel) - half_width_x)
    j_max = min(target.width, ceil(Int, x_pixel) + half_width_x)
    i_min = max(1, floor(Int, y_pixel) - half_width_y)
    i_max = min(target.height, ceil(Int, y_pixel) + half_width_y)

    inv_2sigma_x2 = 1.0 / (2.0 * sigma_x_pix^2)
    inv_2sigma_y2 = 1.0 / (2.0 * sigma_y_pix^2)

    if normalization == :integral
        norm_factor = 1.0 / (2π * sigma_x_pix * sigma_y_pix)
    else
        norm_factor = 1.0
    end

    for i in i_min:i_max, j in j_min:j_max
        dx = Float64(j) - x_pixel
        dy = Float64(i) - y_pixel

        exponent = -(dx^2 * inv_2sigma_x2 + dy^2 * inv_2sigma_y2)
        value = exp(exponent) * norm_factor

        # Accumulate colored blob
        img[i, j] += color * value
    end
end
