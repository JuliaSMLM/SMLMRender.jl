# Ellipse outline rendering for SMLMRender.jl

using Colors

"""
    render_ellipse(smld, target::Image2DTarget, strategy::EllipseRender,
                  color_mapping::ColorMapping)

Render SMLD data as ellipse outlines.

Each localization is rendered as an ellipse outline using σ_x, σ_y for radii
and σ_xy (covariance) for rotation when available.

# Arguments
- `smld`: SMLD dataset with .emitters field
- `target`: Image2DTarget specifying output dimensions
- `strategy`: EllipseRender strategy parameters
- `color_mapping`: ColorMapping specification

Returns Matrix{RGB{Float64}}
"""
function render_ellipse(smld, target::Image2DTarget, strategy::EllipseRender,
                       color_mapping::ColorMapping)
    if color_mapping isa FieldColorMapping
        return render_ellipse_field(smld, target, strategy, color_mapping)
    elseif color_mapping isa ManualColorMapping
        return render_ellipse_manual(smld, target, strategy, color_mapping)
    elseif color_mapping isa IntensityColorMapping
        return render_ellipse_intensity(smld, target, strategy, color_mapping)
    else
        error("Unsupported color mapping type for ellipse render")
    end
end

"""
    render_ellipse_field(smld, target, strategy, mapping::FieldColorMapping)

Ellipse render with field-based coloring.
"""
function render_ellipse_field(smld, target::Image2DTarget,
                              strategy::EllipseRender,
                              mapping::FieldColorMapping)
    result = zeros(RGB{Float64}, target.height, target.width)

    # Determine value range
    value_range = prepare_field_range(smld, mapping)

    for emitter in smld.emitters
        # Get ellipse parameters (radii and rotation)
        radius_x_nm, radius_y_nm, θ = get_ellipse_params(emitter, strategy)

        if radius_x_nm < 0.1 || radius_x_nm > 10000.0 ||
           radius_y_nm < 0.1 || radius_y_nm > 10000.0
            continue
        end

        # Get color
        color = get_emitter_color(emitter, mapping; value_range=value_range)

        # Draw ellipse
        draw_ellipse_outline!(result, emitter, target, radius_x_nm, radius_y_nm, θ,
                             color, strategy.line_width)
    end

    return result
end

"""
    render_ellipse_manual(smld, target, strategy, mapping::ManualColorMapping)

Ellipse render with single manual color.
"""
function render_ellipse_manual(smld, target::Image2DTarget,
                               strategy::EllipseRender,
                               mapping::ManualColorMapping)
    result = zeros(RGB{Float64}, target.height, target.width)

    for emitter in smld.emitters
        radius_x_nm, radius_y_nm, θ = get_ellipse_params(emitter, strategy)

        if radius_x_nm < 0.1 || radius_x_nm > 10000.0 ||
           radius_y_nm < 0.1 || radius_y_nm > 10000.0
            continue
        end

        draw_ellipse_outline!(result, emitter, target, radius_x_nm, radius_y_nm, θ,
                             mapping.color, strategy.line_width)
    end

    return result
end

"""
    render_ellipse_intensity(smld, target, strategy, mapping::IntensityColorMapping)

Ellipse render with intensity colormap.

Accumulates to grayscale, then applies colormap.
"""
function render_ellipse_intensity(smld, target::Image2DTarget,
                                  strategy::EllipseRender,
                                  mapping::IntensityColorMapping)
    # Accumulate to grayscale
    intensity = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        radius_x_nm, radius_y_nm, θ = get_ellipse_params(emitter, strategy)

        if radius_x_nm < 0.1 || radius_x_nm > 10000.0 ||
           radius_y_nm < 0.1 || radius_y_nm > 10000.0
            continue
        end

        draw_ellipse_outline_grayscale!(intensity, emitter, target,
                                       radius_x_nm, radius_y_nm, θ,
                                       strategy.line_width)
    end

    # Apply intensity colormap
    return apply_intensity_colormap(intensity, mapping)
end

"""
    get_ellipse_params(emitter, strategy::EllipseRender)

Get ellipse parameters for an emitter based on strategy settings.

Returns (radius_x_nm, radius_y_nm, rotation_angle) where rotation is in radians.
Rotation is computed from σ_xy covariance if available.
"""
function get_ellipse_params(emitter, strategy::EllipseRender)
    if strategy.use_localization_precision
        # Get σ_x, σ_y in μm, convert to nm
        radius_x_nm = emitter.σ_x * strategy.radius_factor * 1000.0
        radius_y_nm = emitter.σ_y * strategy.radius_factor * 1000.0

        # Check for covariance term (σ_xy) for rotation
        # σ_xy may not exist in older emitter types
        σ_xy = _get_sigma_xy(emitter)

        if σ_xy != 0.0
            # Rotation angle from covariance matrix
            # θ = 0.5 * atan(2 * σ_xy / (σ_x² - σ_y²))
            σ_x_sq = emitter.σ_x^2
            σ_y_sq = emitter.σ_y^2
            θ = 0.5 * atan(2.0 * σ_xy, σ_x_sq - σ_y_sq)
        else
            θ = 0.0
        end
    else
        # Use fixed radii
        radius_x_nm = strategy.fixed_radius_x * strategy.radius_factor
        radius_y_nm = strategy.fixed_radius_y * strategy.radius_factor
        θ = 0.0
    end

    return (radius_x_nm, radius_y_nm, θ)
end

"""
    _get_sigma_xy(emitter)

Safely get σ_xy covariance from emitter, returning 0.0 if not present.
"""
function _get_sigma_xy(emitter)
    if hasproperty(emitter, :σ_xy)
        val = getproperty(emitter, :σ_xy)
        return val === nothing ? 0.0 : Float64(val)
    else
        return 0.0
    end
end

"""
    draw_ellipse_outline!(img::Matrix{RGB{Float64}}, emitter, target,
                         radius_x_nm, radius_y_nm, θ, color, line_width)

Draw an ellipse outline on RGB image.

# Algorithm:
- Sample points around ellipse circumference using parametric form
- Apply rotation by angle θ
- Draw anti-aliased points
- Number of samples adaptive to ellipse size
"""
function draw_ellipse_outline!(img::Matrix{RGB{Float64}}, emitter,
                              target::Image2DTarget,
                              radius_x_nm::Float64, radius_y_nm::Float64,
                              θ::Float64, color::RGB{Float64},
                              line_width::Float64)
    # Convert to pixel coordinates
    center_x, center_y = physical_to_pixel(emitter.x, emitter.y, target)
    radius_x_pix = radius_x_nm / target.pixel_size
    radius_y_pix = radius_y_nm / target.pixel_size

    # Precompute rotation
    cos_θ = cos(θ)
    sin_θ = sin(θ)

    # Number of sample points (adaptive to larger radius)
    max_radius = max(radius_x_pix, radius_y_pix)
    n_points = max(16, ceil(Int, 2π * max_radius))

    # Draw ellipse by sampling points
    for i in 1:n_points
        t = 2π * i / n_points

        # Parametric ellipse (before rotation)
        x_local = radius_x_pix * cos(t)
        y_local = radius_y_pix * sin(t)

        # Apply rotation
        x_rot = x_local * cos_θ - y_local * sin_θ
        y_rot = x_local * sin_θ + y_local * cos_θ

        # Translate to center
        x = center_x + x_rot
        y = center_y + y_rot

        # Draw anti-aliased point
        draw_antialiased_point!(img, x, y, color, line_width)
    end
end

"""
    draw_ellipse_outline_grayscale!(img::Matrix{Float64}, emitter, target,
                                   radius_x_nm, radius_y_nm, θ, line_width)

Draw an ellipse outline on grayscale image.
"""
function draw_ellipse_outline_grayscale!(img::Matrix{Float64}, emitter,
                                        target::Image2DTarget,
                                        radius_x_nm::Float64, radius_y_nm::Float64,
                                        θ::Float64, line_width::Float64)
    center_x, center_y = physical_to_pixel(emitter.x, emitter.y, target)
    radius_x_pix = radius_x_nm / target.pixel_size
    radius_y_pix = radius_y_nm / target.pixel_size

    cos_θ = cos(θ)
    sin_θ = sin(θ)

    max_radius = max(radius_x_pix, radius_y_pix)
    n_points = max(16, ceil(Int, 2π * max_radius))

    for i in 1:n_points
        t = 2π * i / n_points

        x_local = radius_x_pix * cos(t)
        y_local = radius_y_pix * sin(t)

        x_rot = x_local * cos_θ - y_local * sin_θ
        y_rot = x_local * sin_θ + y_local * cos_θ

        x = center_x + x_rot
        y = center_y + y_rot

        draw_antialiased_point_grayscale!(img, x, y, line_width)
    end
end
