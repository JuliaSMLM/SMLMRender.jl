"""
    SMLMRender

High-performance rendering for single molecule localization microscopy (SMLM) data.
Supports multiple rendering strategies (Histogram, Gaussian, Circle, Ellipse) and flexible
color mapping (intensity-based, field-based, manual, grayscale).

# API Overview
For a comprehensive overview of the API, use the help mode on `api`:

    ?SMLMRender.api

Or access the complete API documentation programmatically:

    docs = SMLMRender.api()
"""
module SMLMRender

using Colors
using ColorSchemes
using Statistics
using FileIO
using ImageIO

# Core types
include("types.jl")

# Utilities
include("utils.jl")

# Color mapping
include("color/mapping.jl")

# Rendering functions
include("render/histogram.jl")
include("render/gaussian.jl")
include("render/circle.jl")
include("render/ellipse.jl")

# Main interface
include("interface.jl")

# API documentation
include("api.jl")

# Export types
export RenderingStrategy, Render2DStrategy
export HistogramRender, GaussianRender, CircleRender, EllipseRender
export ColorMapping
export IntensityColorMapping, FieldColorMapping, ManualColorMapping, GrayscaleMapping
export RenderTarget, Image2DTarget
export ContrastMethod, ContrastOptions
export RenderOptions, RenderResult2D

# Export main interface
export render  # Multi-channel via dispatch on Vector{SMLD}

# Export utilities (may be useful for users)
export Image2DTarget, create_target_from_smld
export list_recommended_colormaps
export save_image
export export_colorbar

# Export API documentation function
export api

end
