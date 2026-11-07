# Gaussian blob rendering for SMLMRender.jl

using Colors
using SpecialFunctions: erfc, erfcinv

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
                        color_mapping::ColorMapping;
                        clip_percentile::Union{Float64, Nothing}=0.99)
    if color_mapping isa IntensityColorMapping
        return render_gaussian_intensity(smld, target, strategy, color_mapping)
    elseif color_mapping isa FieldColorMapping
        return render_gaussian_field(smld, target, strategy, color_mapping;
                                    clip_percentile=clip_percentile)
    elseif color_mapping isa ManualColorMapping
        return render_gaussian_manual(smld, target, strategy, color_mapping;
                                      clip_percentile=clip_percentile)
    elseif color_mapping isa GrayscaleMapping
        return render_gaussian_grayscale(smld, target, strategy)
    elseif color_mapping isa CategoricalColorMapping
        return render_gaussian_categorical(smld, target, strategy, color_mapping;
                                          clip_percentile=clip_percentile)
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
                              mapping::FieldColorMapping;
                              clip_percentile::Union{Float64, Nothing}=0.99)
    # Use intensity-weighted color algorithm
    # Track both intensity and color numerators for proper weighting

    intensity = zeros(Float64, target.height, target.width)  # Total intensity (S)
    r_num = zeros(Float64, target.height, target.width)      # Red numerator
    g_num = zeros(Float64, target.height, target.width)      # Green numerator
    b_num = zeros(Float64, target.height, target.width)      # Blue numerator

    # Determine value range and frame_offsets (for :absolute_frame support)
    value_range, frame_offsets = prepare_field_range(smld, mapping)
    value_range = value_range::Tuple{Float64, Float64}

    # Pre-build concrete LUT once for allocation-free per-emitter lookups
    lut = get_colormap_lut(mapping.colormap)

    for emitter in smld.emitters
        # Get covariance values
        sigma_x, sigma_y, sigma_xy = get_emitter_covariance(emitter, strategy)

        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        # Get color for this emitter
        color = get_emitter_color(emitter, mapping; value_range=value_range,
                                  frame_offsets=frame_offsets, lut=lut)

        # Render blob, accumulating both intensity and color
        render_gaussian_blob_weighted!(intensity, r_num, g_num, b_num,
                                       emitter, target, sigma_x, sigma_y,
                                       strategy.n_sigmas, strategy.normalization,
                                       color; sigma_xy=sigma_xy)
    end

    # Compute intensity-weighted color with gamma correction
    return apply_intensity_weighted_color(intensity, r_num, g_num, b_num;
                                         clip_percentile=clip_percentile)
end

"""
    render_gaussian_manual(smld, target, strategy, mapping::ManualColorMapping;
                           clip_percentile=0.99)

Gaussian render with single manual color.

Process: accumulate Gaussian intensity → clip at `clip_percentile` of non-zero
pixels → normalize to [0, 1] → multiply by the color, as the histogram path does.
`clip_percentile=nothing` is saturate mode: the raw accumulated intensity times
the color, which can exceed 1.
"""
function render_gaussian_manual(smld, target::Image2DTarget,
                                strategy::GaussianRender,
                                mapping::ManualColorMapping;
                                clip_percentile::Union{Float64, Nothing}=0.99)
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

    if clip_percentile !== nothing
        clip_at_percentile(intensity, clip_percentile)
        intensity = normalize_to_01(intensity)
    end

    result = Matrix{RGB{Float64}}(undef, target.height, target.width)
    @inbounds for i in eachindex(intensity)
        result[i] = mapping.color * intensity[i]
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
    render_gaussian_categorical(smld, target, strategy, mapping::CategoricalColorMapping)

Gaussian render with categorical coloring for cluster/ID visualization.

Each blob is colored by its integer field value using modular palette indexing.
"""
function render_gaussian_categorical(smld, target::Image2DTarget,
                                     strategy::GaussianRender,
                                     mapping::CategoricalColorMapping;
                                     clip_percentile::Union{Float64, Nothing}=0.99)
    # Use intensity-weighted color algorithm (same as field coloring)
    intensity = zeros(Float64, target.height, target.width)
    r_num = zeros(Float64, target.height, target.width)
    g_num = zeros(Float64, target.height, target.width)
    b_num = zeros(Float64, target.height, target.width)

    # Build the palette once, not per emitter (see get_emitter_color).
    palette = categorical_palette(mapping.palette)

    for emitter in smld.emitters
        # Get covariance values
        sigma_x, sigma_y, sigma_xy = get_emitter_covariance(emitter, strategy)

        if sigma_x < 1e-3 || sigma_y < 1e-3 || sigma_x > 1000.0 || sigma_y > 1000.0
            continue
        end

        # Get categorical color for this emitter
        color = get_emitter_color(emitter, mapping; palette=palette)

        # Render blob, accumulating both intensity and color
        render_gaussian_blob_weighted!(intensity, r_num, g_num, b_num,
                                       emitter, target, sigma_x, sigma_y,
                                       strategy.n_sigmas, strategy.normalization,
                                       color; sigma_xy=sigma_xy)
    end

    # Compute intensity-weighted color with gamma correction
    return apply_intensity_weighted_color(intensity, r_num, g_num, b_num;
                                         clip_percentile=clip_percentile)
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
        sigma_x = Float64(strategy.fixed_sigma::Float64)
        sigma_y = sigma_x
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
        # Use Float64()::Float64 to eliminate Union{Nothing, Float64} from return type
        sigma_x = Float64(strategy.fixed_sigma::Float64)
        sigma_y = sigma_x
        sigma_xy = 0.0
    end

    return (sigma_x, sigma_y, sigma_xy)
end

# ============================================================================
# Pixel-integrated Gaussian kernel (shared by every Gaussian color mode)
# ============================================================================

# Standard normal CDF, density and quantile.
@inline _normcdf(t::Float64) = 0.5 * erfc(-t * 0.7071067811865476)
@inline _normpdf(t::Float64) = 0.3989422804014327 * exp(-0.5 * t^2)
@inline _norminv(u::Float64) = -1.4142135623730951 * erfcinv(2.0 * u)

# 8-point Gauss–Legendre rule on [-1, 1].
const _GL_NODES = (-0.9602898564975363, -0.7966664774136267, -0.5255324099163290,
                   -0.1834346424956498,  0.1834346424956498,  0.5255324099163290,
                    0.7966664774136267,  0.9602898564975363)
const _GL_WEIGHTS = (0.1012285362903763, 0.2223810344533745, 0.3137066458778873,
                     0.3626837833783620, 0.3626837833783620, 0.3137066458778873,
                     0.2223810344533745, 0.1012285362903763)

# Below this |correlation| a pixel's mass uses the bivariate normal's expansion to
# first order in ρ: P = ΔΦx·ΔΦy + ρ·Δφx·Δφy (Δ = difference across the pixel's
# standardized edges; ∂Φ₂/∂ρ = φ₂). The next term, (ρ²/2)·Δ(hφ(h))·Δ(kφ(k)), is
# at most 0.12ρ², so the error stays under 1.2e-5 of the localization's mass per
# pixel. Fitted σ_xy is small but almost never exactly zero (SeqSR lab data:
# median |ρ| 1e-3, 99th percentile 0.01), so this keeps fitted data on the fast path.
const _RHO_FIRST_ORDER = 0.01

"""
    foreach_gaussian_pixel(f, emitter, target, sigma_x, sigma_y, n_sigmas,
                           normalization; sigma_xy=0.0)

Call `f(i, j, w)` for each pixel `(i, j)` in a localization's window, where `w`
is the localization's 2D Gaussian (covariance `[σx² σxy; σxy σy²]`, nm and nm²)
integrated over that pixel. The window spans `n_sigmas` of the larger sigma
beyond the pixels next to the center, clipped to the image.

`normalization = :integral` gives each localization unit mass (exactly, apart
from the window truncation), wherever it falls inside a pixel and however small
its sigma. `:maximum` scales that by `2π·sqrt(det Σ)` (pixel units), so each
pixel is the pixel average of a peak-1 Gaussian: about 1 at the peak for sigmas
of a pixel or more, and less for sigmas below a pixel.

Uncorrelated x and y use the exact product of error-function differences; a
correlation `|ρ| < 0.01` adds its first-order term (error below 1.2e-5 of the
localization's mass per pixel). Stronger correlations integrate the conditional
x-distribution over each row with an 8-point Gauss–Legendre rule in
`u = Φ((y - y0)/σy)`, which keeps each row's mass exact. A covariance that is not
positive definite falls back to the axis-aligned Gaussian.
"""
function foreach_gaussian_pixel(f::F, emitter, target::Image2DTarget,
                                sigma_x::Float64, sigma_y::Float64,
                                n_sigmas::Float64, normalization::Symbol;
                                sigma_xy::Float64=0.0) where {F}
    # Bound once: x0 is captured by the closures below, and a reassigned captured
    # variable is boxed, which makes the whole kernel type-unstable.
    xp, yp = physical_to_pixel(emitter.x, emitter.y, target)
    x0 = Float64(xp)
    y0 = Float64(yp)

    # Sigmas in pixels
    sx = sigma_x / target.pixel_size
    sy = sigma_y / target.pixel_size
    sxy = sigma_xy / target.pixel_size^2

    half_width = ceil(Int, n_sigmas * max(sx, sy))
    j_min = max(1, floor(Int, x0) - half_width)
    j_max = min(target.width, ceil(Int, x0) + half_width)
    i_min = max(1, floor(Int, y0) - half_width)
    i_max = min(target.height, ceil(Int, y0) + half_width)
    (j_min > j_max || i_min > i_max) && return nothing

    det = sx^2 * sy^2 - sxy^2
    if det <= 0
        sxy = 0.0
        det = sx^2 * sy^2
    end
    scale = normalization === :integral ? 1.0 : 2π * sqrt(det)
    ρ = sxy / (sx * sy)

    if abs(ρ) < _RHO_FIRST_ORDER
        inv_sx = 1.0 / sx
        inv_sy = 1.0 / sy
        # Row factors once per blob: ΔΦ and Δφ across each row's edges.
        n_rows = i_max - i_min + 1
        wy = Vector{Float64}(undef, n_rows)
        dy = Vector{Float64}(undef, n_rows)
        k = (i_min - 0.5 - y0) * inv_sy
        c_lo = _normcdf(k)
        p_lo = _normpdf(k)
        @inbounds for r in 1:n_rows
            k = (i_min + r - 0.5 - y0) * inv_sy
            c_hi = _normcdf(k)
            p_hi = _normpdf(k)
            wy[r] = c_hi - c_lo
            dy[r] = p_hi - p_lo
            c_lo = c_hi
            p_lo = p_hi
        end
        hl = (j_min - 0.5 - x0) * inv_sx
        c_l = _normcdf(hl)
        p_l = _normpdf(hl)
        @inbounds for j in j_min:j_max
            hr = (j + 0.5 - x0) * inv_sx
            c_r = _normcdf(hr)
            p_r = _normpdf(hr)
            wx = scale * (c_r - c_l)
            dx = scale * ρ * (p_r - p_l)
            for r in 1:n_rows
                # max(…, 0): the first-order term can only push a far-tail pixel of
                # a strongly anisotropic blob below zero, by a negligible amount
                f(i_min + r - 1, j, max(wx * wy[r] + dx * dy[r], 0.0))
            end
            c_l = c_r
            p_l = p_r
        end
    else
        # x | y is normal with mean x0 + β (y - y0) and variance det / σy².
        β_sy = sxy / sy        # β · σy, with β = σxy / σy²
        inv_s = sy / sqrt(det)
        inv_sy = 1.0 / sy
        u_lo = _normcdf((i_min - 0.5 - y0) * inv_sy)
        @inbounds for i in i_min:i_max
            u_hi = _normcdf((i + 0.5 - y0) * inv_sy)
            half = 0.5 * (u_hi - u_lo)
            if half > 0
                mid = 0.5 * (u_hi + u_lo)
                m = ntuple(k -> x0 + β_sy * _norminv(mid + half * _GL_NODES[k]), Val(8))
                c_prev = ntuple(k -> _normcdf((j_min - 0.5 - m[k]) * inv_s), Val(8))
                for j in j_min:j_max
                    c_next = ntuple(k -> _normcdf((j + 0.5 - m[k]) * inv_s), Val(8))
                    acc = 0.0
                    for k in 1:8
                        acc += _GL_WEIGHTS[k] * (c_next[k] - c_prev[k])
                    end
                    f(i, j, scale * half * acc)
                    c_prev = c_next
                end
            end
            u_lo = u_hi
        end
    end
    return nothing
end

"""
    render_gaussian_blob!(img::Matrix{Float64}, emitter, target, sigma_x, sigma_y,
                         n_sigmas, normalization, weight; sigma_xy=0.0)

Add one localization's pixel-integrated Gaussian, times `weight`, to a grayscale
accumulator. See [`foreach_gaussian_pixel`](@ref) for the kernel.

# Arguments
- `img`: Accumulator (modified in-place)
- `emitter`: Emitter with x, y position
- `target`: Image2DTarget
- `sigma_x, sigma_y`: Standard deviations in nm
- `n_sigmas`: How many σ to render
- `normalization`: :integral or :maximum
- `weight`: Multiplicative weight
- `sigma_xy`: Covariance in nm² (default: 0.0 for axis-aligned)
"""
function render_gaussian_blob!(img::Matrix{Float64}, emitter, target::Image2DTarget,
                               sigma_x::Float64, sigma_y::Float64,
                               n_sigmas::Float64, normalization::Symbol,
                               weight::Float64; sigma_xy::Float64=0.0)
    foreach_gaussian_pixel(emitter, target, sigma_x, sigma_y, n_sigmas, normalization;
                           sigma_xy=sigma_xy) do i, j, w
        @inbounds img[i, j] += weight * w
    end
end

"""
    render_gaussian_blob_weighted!(intensity, r_num, g_num, b_num, emitter, target,
                                   sigma_x, sigma_y, n_sigmas, normalization, color;
                                   sigma_xy=0.0)

Add one localization's pixel-integrated Gaussian to the intensity accumulator and
its color, weighted the same way, to the color numerators (intensity-weighted
color rendering). See [`foreach_gaussian_pixel`](@ref) for the kernel.
"""
function render_gaussian_blob_weighted!(intensity::Matrix{Float64},
                                       r_num::Matrix{Float64},
                                       g_num::Matrix{Float64},
                                       b_num::Matrix{Float64},
                                       emitter, target::Image2DTarget,
                                       sigma_x::Float64, sigma_y::Float64,
                                       n_sigmas::Float64, normalization::Symbol,
                                       color::RGB{Float64}; sigma_xy::Float64=0.0)
    foreach_gaussian_pixel(emitter, target, sigma_x, sigma_y, n_sigmas, normalization;
                           sigma_xy=sigma_xy) do i, j, w
        @inbounds begin
            intensity[i, j] += w
            r_num[i, j] += w * color.r
            g_num[i, j] += w * color.g
            b_num[i, j] += w * color.b
        end
    end
end
