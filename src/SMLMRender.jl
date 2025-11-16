module SMLMRender

using Colors
using ColorSchemes
using Statistics

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

# Main interface
include("interface.jl")

# Export types
export RenderingStrategy, Render2DStrategy
export HistogramRender, GaussianRender, CircleRender
export ColorMapping
export IntensityColorMapping, FieldColorMapping, ManualColorMapping, GrayscaleMapping
export RenderTarget, Image2DTarget
export ContrastMethod, ContrastOptions
export RenderOptions, RenderResult2D

# Export main interface
export render, render_overlay

# Export utilities (may be useful for users)
export Image2DTarget, create_target_from_smld
export list_recommended_colormaps

end
