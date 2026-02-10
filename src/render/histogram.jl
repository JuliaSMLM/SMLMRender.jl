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
function render_histogram(smld, target::Image2DTarget, color_mapping::ColorMapping;
                          clip_percentile::Union{Float64, Nothing}=0.99)
    if color_mapping isa IntensityColorMapping
        return render_histogram_intensity(smld, target, color_mapping)
    elseif color_mapping isa FieldColorMapping
        return render_histogram_field(smld, target, color_mapping; clip_percentile=clip_percentile)
    elseif color_mapping isa ManualColorMapping
        return render_histogram_manual(smld, target, color_mapping; clip_percentile=clip_percentile)
    elseif color_mapping isa GrayscaleMapping
        return render_histogram_grayscale(smld, target)
    elseif color_mapping isa CategoricalColorMapping
        return render_histogram_categorical(smld, target, color_mapping; clip_percentile=clip_percentile)
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
                                mapping::FieldColorMapping;
                                clip_percentile::Union{Float64, Nothing}=0.99)
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

    # Compute brightness from intensity
    if clip_percentile !== nothing
        # Clip and normalize intensity to [0, 1] (same as Gaussian path)
        intensity_norm = copy(intensity)
        clip_at_percentile(intensity_norm, clip_percentile)
        intensity_norm = normalize_to_01(intensity_norm)
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

            # Apply brightness
            if clip_percentile !== nothing
                result[i, j] = color * intensity_norm[i, j]
            else
                # Saturate mode: raw count multiplier, can exceed 1.0
                result[i, j] = color * intensity[i, j]
            end
        end
    end

    return result
end

"""
    render_histogram_manual(smld, target, mapping::ManualColorMapping)

Histogram render with single manual color.
"""
function render_histogram_manual(smld, target::Image2DTarget,
                                 mapping::ManualColorMapping;
                                 clip_percentile::Union{Float64, Nothing}=0.99)
    # Accumulate counts
    counts = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        i, j = physical_to_pixel_index(emitter.x, emitter.y, target)
        if in_bounds(i, j, target)
            counts[i, j] += 1.0
        end
    end

    if clip_percentile !== nothing
        # Clip and normalize counts to [0, 1]
        clip_at_percentile(counts, clip_percentile)
        counts_norm = normalize_to_01(counts)
    else
        # Saturate mode: raw counts, can exceed 1.0
        counts_norm = counts
    end

    # Apply manual color with intensity
    result = zeros(RGB{Float64}, target.height, target.width)
    for i in eachindex(counts_norm)
        result[i] = mapping.color * counts_norm[i]
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
                                      mapping::CategoricalColorMapping;
                                      clip_percentile::Union{Float64, Nothing}=0.99)
    # Get palette
    palette = get_colormap(mapping.palette)
    n_colors = length(palette)

    # Track color component sums and counts per pixel
    r_sum = zeros(Float64, target.height, target.width)
    g_sum = zeros(Float64, target.height, target.width)
    b_sum = zeros(Float64, target.height, target.width)
    counts = zeros(Float64, target.height, target.width)

    for emitter in smld.emitters
        i, j = physical_to_pixel_index(emitter.x, emitter.y, target)
        if in_bounds(i, j, target)
            # Get categorical color
            value = getfield(emitter, mapping.field)
            int_value = round(Int, value)
            idx = mod1(int_value, n_colors)
            color = RGB{Float64}(palette[idx])

            # Accumulate color components and count
            r_sum[i, j] += color.r
            g_sum[i, j] += color.g
            b_sum[i, j] += color.b
            counts[i, j] += 1.0
        end
    end

    if clip_percentile !== nothing
        # Clip and normalize counts for brightness
        counts_norm = copy(counts)
        clip_at_percentile(counts_norm, clip_percentile)
        counts_norm = normalize_to_01(counts_norm)

        # Average color modulated by normalized brightness
        result = zeros(RGB{Float64}, target.height, target.width)
        for i in 1:target.height, j in 1:target.width
            if counts[i, j] > 0
                r_avg = r_sum[i, j] / counts[i, j]
                g_avg = g_sum[i, j] / counts[i, j]
                b_avg = b_sum[i, j] / counts[i, j]
                brightness = counts_norm[i, j]
                result[i, j] = RGB(r_avg * brightness, g_avg * brightness, b_avg * brightness)
            end
        end
    else
        # Saturate mode: raw additive accumulation, can exceed 1.0
        result = zeros(RGB{Float64}, target.height, target.width)
        for i in 1:target.height, j in 1:target.width
            result[i, j] = RGB(r_sum[i, j], g_sum[i, j], b_sum[i, j])
        end
    end

    return result
end
