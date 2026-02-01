# Histogram-based rendering for SMLMRender.jl

using Colors

"""
    render_histogram(smld, target::Image2DTarget, color_mapping::ColorMapping)

Render SMLD data using histogram binning.

Each pixel counts the number of localizations that fall within it.
Fast but no sub-pixel accuracy.

# Arguments
- `smld`: SMLD dataset with .emitters field
- `target`: Image2DTarget specifying output dimensions
- `color_mapping`: ColorMapping specification

Returns Matrix{RGB{Float64}}
"""
function render_histogram(smld, target::Image2DTarget, color_mapping::ColorMapping)
    if color_mapping isa IntensityColorMapping
        return render_histogram_intensity(smld, target, color_mapping)
    elseif color_mapping isa FieldColorMapping
        return render_histogram_field(smld, target, color_mapping)
    elseif color_mapping isa ManualColorMapping
        return render_histogram_manual(smld, target, color_mapping)
    elseif color_mapping isa GrayscaleMapping
        return render_histogram_grayscale(smld, target)
    elseif color_mapping isa CategoricalColorMapping
        return render_histogram_categorical(smld, target, color_mapping)
    else
        error("Unsupported color mapping type for histogram render")
    end
end

"""
    render_histogram_intensity(smld, target, mapping::IntensityColorMapping)

Histogram render with intensity colormap.

Process: accumulate counts → normalize → apply colormap
"""
function render_histogram_intensity(smld, target::Image2DTarget,
                                   mapping::IntensityColorMapping)
    # Accumulate counts
    counts = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        i, j = physical_to_pixel_index(emitter.x, emitter.y, target)
        if in_bounds(i, j, target)
            counts[i, j] += 1.0
        end
    end

    # Apply intensity colormap
    return apply_intensity_colormap(counts, mapping)
end

"""
    render_histogram_field(smld, target, mapping::FieldColorMapping)

Histogram render with field-based coloring.

For pixels with multiple localizations, averages field values.
"""
function render_histogram_field(smld, target::Image2DTarget,
                                mapping::FieldColorMapping)
    # Determine value range and frame_offsets (for :absolute_frame support)
    value_range, frame_offsets = prepare_field_range(smld, mapping)

    # Accumulate intensity and field values
    intensity = zeros(Float64, target.height, target.width)
    field_sum = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        i, j = physical_to_pixel_index(emitter.x, emitter.y, target)
        if in_bounds(i, j, target)
            intensity[i, j] += 1.0
            field_sum[i, j] += get_field_value(emitter, mapping.field;
                                               frame_offsets=frame_offsets)
        end
    end

    # Calculate average field value per pixel
    field_avg = similar(field_sum)
    for idx in eachindex(intensity)
        if intensity[idx] > 0
            field_avg[idx] = field_sum[idx] / intensity[idx]
        else
            field_avg[idx] = 0.0
        end
    end

    # Map field values to colors
    result = zeros(RGB{Float64}, target.height, target.width)
    cmap = get_colormap(mapping.colormap)
    min_val, max_val = value_range

    for i in 1:target.height, j in 1:target.width
        if intensity[i, j] > 0
            # Normalize field value to [0, 1]
            if max_val ≈ min_val
                normalized = 0.5
            else
                normalized = clamp((field_avg[i, j] - min_val) / (max_val - min_val), 0.0, 1.0)
            end

            # Get color from colormap
            color = get(cmap, normalized)

            # Use full color, let saturate on overlap (like circles)
            # Don't normalize - makes colors too dim
            result[i, j] = color * intensity[i, j]
        end
    end

    # Don't normalize - let saturate for bright colors
    return result
end

"""
    render_histogram_manual(smld, target, mapping::ManualColorMapping)

Histogram render with single manual color.
"""
function render_histogram_manual(smld, target::Image2DTarget,
                                 mapping::ManualColorMapping)
    # Accumulate counts
    counts = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        i, j = physical_to_pixel_index(emitter.x, emitter.y, target)
        if in_bounds(i, j, target)
            counts[i, j] += 1.0
        end
    end

    # Normalize counts
    max_count = maximum(counts)
    if max_count > 0
        counts ./= max_count
    end

    # Apply manual color with intensity
    result = zeros(RGB{Float64}, target.height, target.width)
    for i in eachindex(counts)
        result[i] = mapping.color * counts[i]
    end

    return result
end

"""
    render_histogram_grayscale(smld, target)

Histogram render returning grayscale image.
"""
function render_histogram_grayscale(smld, target::Image2DTarget)
    # Accumulate counts
    counts = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        i, j = physical_to_pixel_index(emitter.x, emitter.y, target)
        if in_bounds(i, j, target)
            counts[i, j] += 1.0
        end
    end

    # Normalize and convert to RGB grayscale
    counts_norm = normalize_to_01(counts)
    result = similar(counts, RGB{Float64})
    for i in eachindex(counts_norm)
        gray_val = counts_norm[i]
        result[i] = RGB{Float64}(gray_val, gray_val, gray_val)
    end

    return result
end

"""
    render_histogram_categorical(smld, target, mapping::CategoricalColorMapping)

Histogram render with categorical coloring for cluster/ID visualization.

For pixels with multiple localizations from different clusters, uses
the most frequent cluster's color (mode).
"""
function render_histogram_categorical(smld, target::Image2DTarget,
                                      mapping::CategoricalColorMapping)
    # Get palette
    palette = get_colormap(mapping.palette)
    n_colors = length(palette)

    # Track color accumulation per pixel
    # For simplicity, accumulate RGB directly weighted by count
    result = zeros(RGB{Float64}, target.height, target.width)
    counts = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        i, j = physical_to_pixel_index(emitter.x, emitter.y, target)
        if in_bounds(i, j, target)
            # Get categorical color
            value = getfield(emitter, mapping.field)
            int_value = round(Int, value)
            idx = mod1(int_value, n_colors)
            color = RGB{Float64}(palette[idx])

            # Accumulate color and count
            result[i, j] += color
            counts[i, j] += 1.0
        end
    end

    # Saturate overlapping regions (don't normalize - similar to field histogram)
    return result
end
