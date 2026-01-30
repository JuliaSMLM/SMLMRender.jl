# Circle outline rendering for SMLMRender.jl

using Colors

"""
    render_circle(smld, target::Image2DTarget, strategy::CircleRender,
                 color_mapping::ColorMapping)

Render SMLD data as circle outlines.

Each localization is rendered as a circle outline. Useful for visualizing
localization precision (radius = σ).

# Arguments
- `smld`: SMLD dataset with .emitters field
- `target`: Image2DTarget specifying output dimensions
- `strategy`: CircleRender strategy parameters
- `color_mapping`: ColorMapping specification (ManualColorMapping or FieldColorMapping)

Returns Matrix{RGB{Float64}}

# Note
IntensityColorMapping is not supported for circle rendering. Use `color=` for
a single color, or `color_by=:field` with `colormap=` to color each circle
by a field value.
"""
function render_circle(smld, target::Image2DTarget, strategy::CircleRender,
                      color_mapping::ColorMapping)
    if color_mapping isa FieldColorMapping
        return render_circle_field(smld, target, strategy, color_mapping)
    elseif color_mapping isa ManualColorMapping
        return render_circle_manual(smld, target, strategy, color_mapping)
    elseif color_mapping isa CategoricalColorMapping
        return render_circle_categorical(smld, target, strategy, color_mapping)
    elseif color_mapping isa IntensityColorMapping
        error("IntensityColorMapping not supported for CircleRender. Use `color=` for single color, or `color_by=:field` with `colormap=` to color by field value.")
    else
        error("Unsupported color mapping type for circle render")
    end
end

"""
    render_circle_field(smld, target, strategy, mapping::FieldColorMapping)

Circle render with field-based coloring.
"""
function render_circle_field(smld, target::Image2DTarget,
                             strategy::CircleRender,
                             mapping::FieldColorMapping)
    result = zeros(RGB{Float64}, target.height, target.width)

    # Determine value range and frame_offsets (for :absolute_frame support)
    value_range, frame_offsets = prepare_field_range(smld, mapping)

    for emitter in smld.emitters
        # Get radius
        radius_nm = get_emitter_radius(emitter, strategy)

        if radius_nm < 0.1 || radius_nm > 10000.0
            continue
        end

        # Get color
        color = get_emitter_color(emitter, mapping; value_range=value_range,
                                  frame_offsets=frame_offsets)

        # Draw circle
        draw_circle_outline!(result, emitter, target, radius_nm,
                           color, strategy.line_width)
    end

    # Don't normalize - let circles saturate on overlap for bright intersections
    return result
end

"""
    render_circle_manual(smld, target, strategy, mapping::ManualColorMapping)

Circle render with single manual color.
"""
function render_circle_manual(smld, target::Image2DTarget,
                              strategy::CircleRender,
                              mapping::ManualColorMapping)
    result = zeros(RGB{Float64}, target.height, target.width)

    for emitter in smld.emitters
        radius_nm = get_emitter_radius(emitter, strategy)

        if radius_nm < 0.1 || radius_nm > 10000.0
            continue
        end

        draw_circle_outline!(result, emitter, target, radius_nm,
                           mapping.color, strategy.line_width)
    end

    return result
end

"""
    render_circle_categorical(smld, target, strategy, mapping::CategoricalColorMapping)

Circle render with categorical coloring for cluster/ID visualization.
"""
function render_circle_categorical(smld, target::Image2DTarget,
                                   strategy::CircleRender,
                                   mapping::CategoricalColorMapping)
    result = zeros(RGB{Float64}, target.height, target.width)

    for emitter in smld.emitters
        radius_nm = get_emitter_radius(emitter, strategy)

        if radius_nm < 0.1 || radius_nm > 10000.0
            continue
        end

        # Get categorical color
        color = get_emitter_color(emitter, mapping)

        draw_circle_outline!(result, emitter, target, radius_nm,
                           color, strategy.line_width)
    end

    return result
end


"""
    get_emitter_radius(emitter, strategy::CircleRender)

Get radius for an emitter based on strategy settings.

Returns radius in nm.
"""
function get_emitter_radius(emitter, strategy::CircleRender)
    if strategy.use_localization_precision
        # Use average of σ_x and σ_y (in μm)
        # Multiply by radius_factor and convert to nm
        avg_sigma_um = (emitter.σ_x + emitter.σ_y) / 2.0
        radius_nm = avg_sigma_um * strategy.radius_factor * 1000.0
    else
        # Use fixed radius
        radius_nm = strategy.fixed_radius * strategy.radius_factor
    end

    return radius_nm
end

"""
    draw_circle_outline!(img::Matrix{RGB{Float64}}, emitter, target, radius_nm,
                        color, line_width)

Draw a circle outline on RGB image.

# Algorithm:
- Sample points around circumference
- Draw anti-aliased points
- Number of samples adaptive to radius
"""
function draw_circle_outline!(img::Matrix{RGB{Float64}}, emitter,
                             target::Image2DTarget,
                             radius_nm::Float64, color::RGB{Float64},
                             line_width::Float64)
    # Convert to pixel coordinates
    center_x, center_y = physical_to_pixel(emitter.x, emitter.y, target)
    radius_pix = radius_nm / target.pixel_size

    # Number of sample points (adaptive)
    # At least 12 points, more for larger circles
    n_points = max(12, ceil(Int, 2π * radius_pix))

    # Draw circle by sampling points
    for i in 1:n_points
        θ = 2π * i / n_points
        x = center_x + radius_pix * cos(θ)
        y = center_y + radius_pix * sin(θ)

        # Draw anti-aliased point
        draw_antialiased_point!(img, x, y, color, line_width)
    end
end

"""
    draw_circle_outline_grayscale!(img::Matrix{Float64}, emitter, target,
                                   radius_nm, line_width)

Draw a circle outline on grayscale image.
"""
function draw_circle_outline_grayscale!(img::Matrix{Float64}, emitter,
                                       target::Image2DTarget,
                                       radius_nm::Float64, line_width::Float64)
    center_x, center_y = physical_to_pixel(emitter.x, emitter.y, target)
    radius_pix = radius_nm / target.pixel_size

    n_points = max(12, ceil(Int, 2π * radius_pix))

    for i in 1:n_points
        θ = 2π * i / n_points
        x = center_x + radius_pix * cos(θ)
        y = center_y + radius_pix * sin(θ)

        # Draw anti-aliased point (grayscale version)
        draw_antialiased_point_grayscale!(img, x, y, line_width)
    end
end

"""
    draw_antialiased_point_grayscale!(img::Matrix{Float64}, x, y, thickness)

Draw an anti-aliased point on grayscale image.

Primary pixel gets full intensity, neighbors get AA fringe for smooth edges.
"""
function draw_antialiased_point_grayscale!(img::Matrix{Float64}, x::Real, y::Real,
                                          thickness::Real)
    # Get nearest pixel coordinates
    i0 = round(Int, y)
    j0 = round(Int, x)

    thickness_factor = min(1.0, thickness)

    # Primary pixel gets full intensity
    if 1 <= i0 <= size(img, 1) && 1 <= j0 <= size(img, 2)
        img[i0, j0] += thickness_factor
    end

    # AA fringe to neighbors based on sub-pixel position
    fy = y - i0  # ranges from -0.5 to 0.5
    fx = x - j0

    aa_strength = 0.3 * thickness_factor

    # Horizontal neighbors
    if abs(fx) > 0.1
        j_neighbor = fx > 0 ? j0 + 1 : j0 - 1
        if 1 <= i0 <= size(img, 1) && 1 <= j_neighbor <= size(img, 2)
            img[i0, j_neighbor] += aa_strength * abs(fx)
        end
    end

    # Vertical neighbors
    if abs(fy) > 0.1
        i_neighbor = fy > 0 ? i0 + 1 : i0 - 1
        if 1 <= i_neighbor <= size(img, 1) && 1 <= j0 <= size(img, 2)
            img[i_neighbor, j0] += aa_strength * abs(fy)
        end
    end
end
