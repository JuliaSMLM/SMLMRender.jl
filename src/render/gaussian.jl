# Gaussian blob rendering for SMLMRender.jl

using Colors
using StatsFuns: normcdf, normpdf, bvncdf

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
pixels → divide by the clip value → multiply by the color. Zero density stays
black (the scale is not min-max, so a frame with no empty pixel keeps its
dimmest structure visible). `clip_percentile=nothing` is saturate mode: the raw
accumulated intensity (each localization's unit mass spread over its pixels)
times the color, for callers that scale it themselves.
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
        clip_val = clip_at_percentile(intensity, clip_percentile)
        clip_val > 0 && (intensity ./= clip_val)
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

# Below this |correlation| a pixel's mass uses the bivariate normal's expansion to
# first order in ρ: P = ΔΦx·ΔΦy + ρ·Δφx·Δφy (Δ = difference across the pixel's
# standardized edges; ∂Φ₂/∂ρ = φ₂). The next term, (ρ²/2)·Δ(hφ(h))·Δ(kφ(k)), is
# at most 0.12ρ², so the error stays under 1.2e-5 of the localization's mass per
# pixel. Fitted σ_xy is small but almost never exactly zero (SeqSR lab data:
# median |ρ| 1e-3, 99th percentile 0.01), so this keeps fitted data on the fast
# path; stronger correlations use the exact bivariate normal CDF.
const _RHO_FIRST_ORDER = 0.01

"""
    foreach_gaussian_pixel(f, emitter, target, sigma_x, sigma_y, n_sigmas,
                           normalization; sigma_xy=0.0)

Call `f(i, j, w)` for each in-image pixel `(i, j)` of a localization's window,
where `w` is its 2D Gaussian (covariance `[σx² σxy; σxy σy²]`, nm and nm²)
integrated over that pixel. The window spans `n_sigmas` of the larger sigma
beyond the pixels next to the center.

- `normalization = :integral`: each localization has unit mass (exactly, apart
  from the mass beyond the window), wherever it falls inside a pixel and however
  small its sigma.
- `normalization = :maximum`: the same pixel integrals scaled so the
  localization's brightest pixel is 1, wherever it falls and whatever its sigma.
  The peak is taken over the whole window, so a localization just outside the
  image still shows only its dim tail; it is found by a search along the
  window's ridge, so only in-image pixels are evaluated in full. Because the
  peak is fixed, the total depends on where the localization falls in a pixel
  (by up to about 26% at a 1-pixel sigma, more below); use `:integral` for
  position-independent totals.

Uncorrelated x and y use the exact product of normal-CDF differences. A
correlation `|ρ| < 0.01` adds its first-order term (error below 1.2e-5 of the
localization's mass per pixel). Stronger correlations use the bivariate normal
CDF at the pixel corners (Genz's algorithm, `StatsFuns.bvncdf`). A covariance
that is not positive definite falls back to the axis-aligned Gaussian.
"""
function foreach_gaussian_pixel(f::F, emitter, target::Image2DTarget,
                                sigma_x::Float64, sigma_y::Float64,
                                n_sigmas::Float64, normalization::Symbol;
                                sigma_xy::Float64=0.0) where {F}
    xp, yp = physical_to_pixel(emitter.x, emitter.y, target)
    x0 = Float64(xp)
    y0 = Float64(yp)

    # Sigmas in pixels
    sx = sigma_x / target.pixel_size
    sy = sigma_y / target.pixel_size
    sxy = sigma_xy / target.pixel_size^2

    half_width = ceil(Int, n_sigmas * max(sx, sy))
    j_lo = floor(Int, x0) - half_width
    j_hi = ceil(Int, x0) + half_width
    i_lo = floor(Int, y0) - half_width
    i_hi = ceil(Int, y0) + half_width
    (j_hi < 1 || j_lo > target.width || i_hi < 1 || i_lo > target.height) && return nothing

    det = sx^2 * sy^2 - sxy^2
    ρ = det > 0 ? sxy / (sx * sy) : 0.0   # not positive definite: axis-aligned

    # :maximum scales by the brightest pixel of the whole window, which can lie
    # outside the image; the ridge search finds it without the off-image pixels.
    peak = normalization === :maximum
    window_peak = peak ? _window_peak(x0, y0, sx, sy, ρ, i_lo, i_hi, j_lo, j_hi) : 0.0

    # Every other evaluation covers only the in-image part of the window
    j_lo = max(j_lo, 1)
    j_hi = min(j_hi, target.width)
    i_lo = max(i_lo, 1)
    i_hi = min(i_hi, target.height)
    n_cols = j_hi - j_lo + 1
    n_rows = i_hi - i_lo + 1

    if abs(ρ) < _RHO_FIRST_ORDER
        # ΔΦ and Δφ across each column's and each row's standardized edges
        wx, dx = _edge_terms(j_lo, n_cols, x0, sx)
        wy, dy = _edge_terms(i_lo, n_rows, y0, sy)
        pixel_mass = (r, c) -> @inbounds _first_order_mass(wx[c], dx[c], wy[r], dy[r], ρ)
        _emit_blob(f, pixel_mass, i_lo, j_lo, n_rows, n_cols, peak, window_peak)
    else
        # Bivariate normal CDF at every pixel corner
        G = Matrix{Float64}(undef, n_rows + 1, n_cols + 1)
        @inbounds for c in 1:(n_cols + 1), r in 1:(n_rows + 1)
            G[r, c] = bvncdf((j_lo + c - 1.5 - x0) / sx, (i_lo + r - 1.5 - y0) / sy, ρ)
        end
        pixel_mass = (r, c) -> @inbounds _corner_mass(G[r + 1, c + 1], G[r, c + 1], G[r + 1, c], G[r, c])
        _emit_blob(f, pixel_mass, i_lo, j_lo, n_rows, n_cols, peak, window_peak)
    end
    return nothing
end

# A pixel's mass from its ΔΦ and Δφ terms to first order in ρ. max(…, 0): the
# first-order term can only push a far-tail pixel of a strongly anisotropic blob
# below zero, by a negligible amount.
@inline _first_order_mass(wx, dx, wy, dy, ρ) = max(wx * wy + ρ * dx * dy, 0.0)

# A pixel's mass from the bivariate normal CDF at its corners (x high/low, y high/low).
@inline _corner_mass(g_hh, g_hl, g_lh, g_ll) = max(g_hh - g_hl - g_lh + g_ll, 0.0)

# Mass of pixel (row i, column j), computed exactly as the kernel computes it.
@inline function _pixel_mass_at(i::Int, j::Int, x0, y0, sx, sy, ρ)
    xl = (j - 0.5 - x0) / sx
    xh = (j + 0.5 - x0) / sx
    yl = (i - 0.5 - y0) / sy
    yh = (i + 0.5 - y0) / sy
    if abs(ρ) < _RHO_FIRST_ORDER
        return _first_order_mass(normcdf(xh) - normcdf(xl), normpdf(xh) - normpdf(xl),
                                 normcdf(yh) - normcdf(yl), normpdf(yh) - normpdf(yl), ρ)
    end
    return _corner_mass(bvncdf(xh, yh, ρ), bvncdf(xh, yl, ρ), bvncdf(xl, yh, ρ), bvncdf(xl, yl, ρ))
end

# Brightest pixel mass in rows i_lo:i_hi and columns j_lo:j_hi, found without
# evaluating the whole window. Within one row (a strip of y), the pixel masses
# are a log-concave function of the column (Prékopa), and the strip's x density
# is a mixture of equal-width normals whose means, x0 + β(y - y0) with
# β = ρσx/σy, span |β| over the strip; so the row's mode lies within half a pixel
# of that span and its brightest pixel is one of the columns next to it. Rows are
# visited outward from the brightest row of the y marginal (where the row masses
# fall monotonically) and the walk stops once a row's total mass, times the
# largest share of it one pixel can hold (the conditional density bound
# 1/(σ_{x|y}√(2π))), cannot beat the best pixel found. The search runs along the
# axis with the smaller conditional slope, so |β| ≤ |ρ| < 1 and each row has at
# most four candidates.
#
# The argument is exact for the exact masses (the bivariate-CDF path, |ρ| ≥ 0.01).
# On the first-order path (|ρ| < 0.01) the masses are the expansion's: the search
# still contains the exact masses' brightest pixel, so the peak it returns is
# within twice the expansion's error at the peak of the expansion's own maximum:
# of order ρ², at most about 2e-4 of the peak. That holds because the window
# always contains the center, as every kernel window does (asserted); far out in
# the tails, where the expansion's relative error grows, the search is never
# asked for a peak.
function _window_peak(x0, y0, sx, sy, ρ, i_lo::Int, i_hi::Int, j_lo::Int, j_hi::Int)
    @assert j_lo <= x0 <= j_hi && i_lo <= y0 <= i_hi "the window must contain the center"
    rows = sx <= sy   # |ρ·sx/sy| ≤ |ρ·sy/sx|: walk rows, candidates along x
    u0, v0, su, sv = rows ? (x0, y0, sx, sy) : (y0, x0, sy, sx)
    u_lo, u_hi, v_lo, v_hi = rows ? (j_lo, j_hi, i_lo, i_hi) : (i_lo, i_hi, j_lo, j_hi)
    β = ρ * su / sv
    share = min(1.0, 1 / (su * sqrt(1 - ρ^2) * sqrt(2π)))
    best = 0.0
    vc = clamp(round(Int, v0), v_lo, v_hi)
    for (v_start, step) in ((vc, 1), (vc - 1, -1))
        v = v_start
        while v_lo <= v <= v_hi
            line = normcdf((v + 0.5 - v0) / sv) - normcdf((v - 0.5 - v0) / sv)
            line * share <= best && break
            m = u0 + β * (v - v0)
            u_a = clamp(floor(Int, m - abs(β) / 2 - 0.5), u_lo, u_hi)
            u_b = clamp(ceil(Int, m + abs(β) / 2 + 0.5), u_lo, u_hi)
            for u in u_a:u_b
                w = rows ? _pixel_mass_at(v, u, x0, y0, sx, sy, ρ) :
                           _pixel_mass_at(u, v, x0, y0, sx, sy, ρ)
                best = max(best, w)
            end
            v += step
        end
    end
    return best
end

# Differences of the standard normal CDF (ΔΦ) and density (Δφ) across the edges
# of n pixels starting at index `lo`, for a Gaussian at pixel coordinate `μ` with
# sigma `s` (pixels). Pixel k spans [k - 0.5, k + 0.5].
function _edge_terms(lo::Int, n::Int, μ::Float64, s::Float64)
    w = Vector{Float64}(undef, n)
    d = Vector{Float64}(undef, n)
    t = (lo - 0.5 - μ) / s
    c_prev = normcdf(t)
    p_prev = normpdf(t)
    @inbounds for k in 1:n
        t = (lo + k - 0.5 - μ) / s
        c = normcdf(t)
        p = normpdf(t)
        w[k] = c - c_prev
        d[k] = p - p_prev
        c_prev = c
        p_prev = p
    end
    return w, d
end

# Call f(i, j, w) for the in-image pixels (rows i_lo:i_lo+n_rows-1, columns
# j_lo:j_lo+n_cols-1). When `peak` (normalization = :maximum) every value is
# divided by the brightest pixel: the window's, from the ridge search, or an
# in-image pixel's if it is higher (rounding, or the first-order path's
# approximation), so no pixel exceeds 1 and the brightest in-image pixel of a
# localization whose peak is in the image is exactly 1.
@inline function _emit_blob(f::F, pixel_mass::P, i_lo::Int, j_lo::Int, n_rows::Int, n_cols::Int,
                            peak::Bool, window_peak::Float64) where {F, P}
    if peak
        m = window_peak
        for c in 1:n_cols, r in 1:n_rows
            m = max(m, pixel_mass(r, c))
        end
        m > 0 || return nothing
        for c in 1:n_cols
            j = j_lo + c - 1
            for r in 1:n_rows
                f(i_lo + r - 1, j, pixel_mass(r, c) / m)
            end
        end
    else
        for c in 1:n_cols
            j = j_lo + c - 1
            for r in 1:n_rows
                f(i_lo + r - 1, j, pixel_mass(r, c))
            end
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
