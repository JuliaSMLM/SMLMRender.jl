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
    get_field_color(emitter, mapping::FieldColorMapping, value_range::Tuple{Float64, Float64})

Get RGB color for a single emitter based on its field value.

# Arguments
- `emitter`: Emitter object (must have the specified field)
- `mapping`: FieldColorMapping specification
- `value_range`: (min_val, max_val) for normalization

Returns RGB{Float64}
"""
function get_field_color(emitter, mapping::FieldColorMapping,
                        value_range::Tuple{Float64, Float64})
    # Get field value
    value = getfield(emitter, mapping.field)

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
    get_emitter_color(emitter, mapping::ColorMapping, value_range=nothing)

Dispatch function to get color for a single emitter.

# Arguments
- `emitter`: Emitter object
- `mapping`: ColorMapping specification
- `value_range`: Required for FieldColorMapping, ignored otherwise

Returns RGB{Float64}
"""
function get_emitter_color(emitter, mapping::ManualColorMapping, value_range=nothing)
    return mapping.color
end

function get_emitter_color(emitter, mapping::FieldColorMapping, value_range::Tuple{Float64, Float64})
    return get_field_color(emitter, mapping, value_range)
end

function get_emitter_color(emitter, mapping::IntensityColorMapping, value_range=nothing)
    # For intensity mapping, we don't color individual emitters
    # Return white (will be accumulated as grayscale then colored later)
    return RGB{Float64}(1.0, 1.0, 1.0)
end

function get_emitter_color(emitter, mapping::GrayscaleMapping, value_range=nothing)
    return RGB{Float64}(1.0, 1.0, 1.0)
end

"""
    prepare_field_range(smld, mapping::FieldColorMapping)

Calculate the value range for field-based color mapping.

Handles :auto range and percentile clipping.
"""
function prepare_field_range(smld, mapping::FieldColorMapping)
    if mapping.range isa Tuple
        return mapping.range
    else  # :auto
        return calculate_field_range(smld, mapping.field, mapping.clip_percentiles)
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
        :perceptual => [:viridis, :cividis, :inferno, :magma, :plasma]
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
