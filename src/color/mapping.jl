# Color mapping functions for SMLMRender.jl

using ColorSchemes
using Colors
using Statistics

"""
    get_colormap(name::Symbol)

Get a ColorScheme by name. Validates that the colormap exists.
"""
function get_colormap(name::Symbol)
    if !haskey(colorschemes, name)
        error("Colormap :$name not found. Use ColorSchemes.colorschemes to see available colormaps.")
    end
    return colorschemes[name]
end

"""
    apply_intensity_colormap(intensity::Matrix{Float64}, mapping::IntensityColorMapping)

Apply intensity-based colormap to grayscale intensity image.

# Process:
1. Clip at percentile
2. Normalize to [0, 1]
3. Apply colormap

Returns Matrix{RGB{Float64}}
"""
function apply_intensity_colormap(intensity::Matrix{Float64}, mapping::IntensityColorMapping)
    # Copy to avoid modifying input
    img = copy(intensity)

    # Clip at percentile
    clip_at_percentile(img, mapping.clip_percentile)

    # Normalize to [0, 1]
    img_norm = normalize_to_01(img)

    # Get colormap
    cmap = get_colormap(mapping.colormap)

    # Apply colormap
    result = similar(img, RGB{Float64})
    for i in eachindex(img_norm)
        # ColorSchemes.get maps [0,1] -> RGB
        result[i] = get(cmap, img_norm[i])
    end

    return result
end

"""
    get_field_color(emitter, mapping::FieldColorMapping, value_range::Tuple{Float64, Float64};
                   frame_offsets=nothing)

Get RGB color for a single emitter based on its field value.

# Arguments
- `emitter`: Emitter object (must have the specified field)
- `mapping`: FieldColorMapping specification
- `value_range`: (min_val, max_val) for normalization
- `frame_offsets`: Required when `mapping.field === :absolute_frame`

Returns RGB{Float64}
"""
function get_field_color(emitter, mapping::FieldColorMapping,
                        value_range::Tuple{Float64, Float64};
                        frame_offsets=nothing)
    # Get field value (handles computed fields like :absolute_frame)
    value = get_field_value(emitter, mapping.field; frame_offsets=frame_offsets)

    # Normalize to [0, 1]
    min_val, max_val = value_range
    if max_val ≈ min_val
        normalized = 0.5
    else
        normalized = clamp((value - min_val) / (max_val - min_val), 0.0, 1.0)
    end

    # Get colormap and map to color
    cmap = get_colormap(mapping.colormap)
    return get(cmap, normalized)
end

"""
    get_emitter_color(emitter, mapping::ColorMapping; value_range=nothing)

Dispatch function to get color for a single emitter.

# Arguments
- `emitter`: Emitter object
- `mapping`: ColorMapping specification
- `value_range`: Required for FieldColorMapping, ignored otherwise (keyword argument)

Returns RGB{Float64}
"""
function get_emitter_color(emitter, mapping::ManualColorMapping; value_range=nothing)
    return mapping.color
end

function get_emitter_color(emitter, mapping::FieldColorMapping;
                          value_range::Tuple{Float64, Float64},
                          frame_offsets=nothing)
    return get_field_color(emitter, mapping, value_range; frame_offsets=frame_offsets)
end

function get_emitter_color(emitter, mapping::IntensityColorMapping; value_range=nothing)
    # For intensity mapping, we don't color individual emitters
    # Return white (will be accumulated as grayscale then colored later)
    return RGB{Float64}(1.0, 1.0, 1.0)
end

function get_emitter_color(emitter, mapping::GrayscaleMapping; value_range=nothing, kwargs...)
    return RGB{Float64}(1.0, 1.0, 1.0)
end

"""
    get_emitter_color(emitter, mapping::CategoricalColorMapping; kwargs...)

Get categorical color for emitter based on integer field value.
Uses modular indexing into palette - colors cycle for values > palette size.
"""
function get_emitter_color(emitter, mapping::CategoricalColorMapping; kwargs...)
    # Get integer field value
    value = getfield(emitter, mapping.field)
    int_value = round(Int, value)

    # Get palette
    palette = get_colormap(mapping.palette)
    n_colors = length(palette)

    # Modular index (1-based)
    idx = mod1(int_value, n_colors)

    return RGB{Float64}(palette[idx])
end

"""
    prepare_field_range(smld, mapping::FieldColorMapping)

Calculate the value range for field-based color mapping.

Handles `:auto` range and percentile clipping. Also computes `frame_offsets`
when `mapping.field === :absolute_frame`.

Returns `(value_range, frame_offsets)` where `frame_offsets` is `nothing`
for regular fields or a `Dict{Int,Int}` for `:absolute_frame`.
"""
function prepare_field_range(smld, mapping::FieldColorMapping)
    # Compute frame_offsets if needed
    frame_offsets = mapping.field === :absolute_frame ? compute_frame_offsets(smld) : nothing

    if mapping.range isa Tuple
        return (mapping.range, frame_offsets)
    else  # :auto
        range = calculate_field_range(smld, mapping.field, mapping.clip_percentiles;
                                     frame_offsets=frame_offsets)
        return (range, frame_offsets)
    end
end

"""
    blend_field_colors(values::Vector{Float64}, weights::Vector{Float64},
                      mapping::FieldColorMapping, value_range)

Blend multiple field values with weights to get average color.

Used for histogram rendering when multiple localizations fall in same pixel.

# Arguments
- `values`: Field values for localizations in pixel
- `weights`: Weights (e.g., photon counts) for each localization
- `mapping`: FieldColorMapping specification
- `value_range`: (min_val, max_val) for normalization

Returns RGB{Float64}
"""
function blend_field_colors(values::Vector{Float64}, weights::Vector{Float64},
                           mapping::FieldColorMapping, value_range::Tuple{Float64, Float64})
    # Weighted average of field values
    total_weight = sum(weights)
    if total_weight ≈ 0
        avg_value = mean(values)
    else
        avg_value = sum(values .* weights) / total_weight
    end

    # Create temporary emitter-like object with averaged field
    # This is a bit hacky but avoids code duplication
    temp = (; mapping.field => avg_value)

    # Get color for averaged value
    min_val, max_val = value_range
    if max_val ≈ min_val
        normalized = 0.5
    else
        normalized = clamp((avg_value - min_val) / (max_val - min_val), 0.0, 1.0)
    end

    cmap = get_colormap(mapping.colormap)
    return get(cmap, normalized)
end

"""
    rgb_to_grayscale(rgb::RGB{Float64})

Convert RGB to grayscale using standard luminance weights.
"""
function rgb_to_grayscale(rgb::RGB{Float64})
    return 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
end

"""
    validate_colormap(name::Symbol)

Check if a colormap name is valid. Returns true/false.
"""
function validate_colormap(name::Symbol)
    return haskey(colorschemes, name)
end

"""
    list_recommended_colormaps()

Return a dictionary of recommended colormaps organized by category.
"""
function list_recommended_colormaps()
    return Dict(
        :sequential => [:viridis, :cividis, :inferno, :magma, :plasma, :turbo, :hot],
        :diverging => [:RdBu, :seismic, :coolwarm],
        :cyclic => [:twilight, :phase],
        :perceptual => [:viridis, :cividis, :inferno, :magma, :plasma],
        :categorical => [:tab10, :Set1_9, :Set2_8, :Set3_12, :tab20, :tab20b, :tab20c]
    )
end

"""
    normalize_rgb(img::Matrix{RGB{Float64}})

Normalize RGB image to use full dynamic range while preserving hue.

This function scales all RGB values so that the maximum component
value across the entire image becomes 1.0, ensuring the image uses
the full brightness range without changing colors.

Used for field-based rendering to auto-scale like intensity-based rendering does.
"""
function normalize_rgb(img::AbstractMatrix{<:Colorant})
    # Find maximum value across all RGB components
    max_val = 0.0
    for pixel in img
        max_val = max(max_val, pixel.r, pixel.g, pixel.b)
    end

    # If image is completely black, return as-is
    if max_val ≈ 0.0
        return img
    end

    # Scale all values so max becomes 1.0
    scale_factor = 1.0 / max_val

    # Apply scaling
    result = similar(img)
    for i in eachindex(img)
        pixel = img[i]
        result[i] = RGB(pixel.r * scale_factor,
                       pixel.g * scale_factor,
                       pixel.b * scale_factor)
    end

    return result
end

"""
    apply_intensity_weighted_color(intensity, r_num, g_num, b_num; clip_percentile=0.99)

Combine intensity and color numerators using intensity-weighted color algorithm.

Computes the average color at each pixel (weighted by intensity) and modulates
by the normalized intensity for brightness. Uses the same clip-and-normalize
approach as the intensity rendering path.

# Algorithm:
1. Clip intensity at `clip_percentile` of non-zero pixels
2. Normalize clipped intensity to [0, 1]
3. Average color: RGB = (r_num/S, g_num/S, b_num/S) where S = original intensity
4. Final: RGB * normalized_brightness

# Arguments
- `intensity`: Total accumulated intensity (overlap count)
- `r_num`, `g_num`, `b_num`: Color numerators weighted by intensity
- `clip_percentile`: Percentile of non-zero pixels for clipping (default 0.99)
"""
function apply_intensity_weighted_color(intensity::Matrix{Float64},
                                       r_num::Matrix{Float64},
                                       g_num::Matrix{Float64},
                                       b_num::Matrix{Float64};
                                       clip_percentile::Float64 = 0.99)
    height, width = size(intensity)
    result = zeros(RGB{Float64}, height, width)

    # Clip and normalize intensity (same as intensity rendering path)
    intensity_norm = copy(intensity)
    clip_at_percentile(intensity_norm, clip_percentile)
    intensity_norm = normalize_to_01(intensity_norm)

    # Small epsilon to avoid division by zero
    ε = 1e-6

    for i in 1:height, j in 1:width
        S = intensity[i, j]

        if S > ε
            # Compute average color (from original, unclipped intensity)
            r_avg = r_num[i, j] / S
            g_avg = g_num[i, j] / S
            b_avg = b_num[i, j] / S

            # Brightness from clipped+normalized intensity
            brightness = intensity_norm[i, j]

            # Final color: average color * brightness
            result[i, j] = RGB(r_avg * brightness,
                             g_avg * brightness,
                             b_avg * brightness)
        end
        # else: pixel stays black (S ≈ 0)
    end

    return result
end
