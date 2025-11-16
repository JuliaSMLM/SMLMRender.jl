module SMLMRender

using Colors

# Core types
include("types.jl")

# Export types
export RenderingStrategy, Render2DStrategy
export HistogramRender, GaussianRender, CircleRender
export ColorMapping
export IntensityColorMapping, FieldColorMapping, ManualColorMapping, GrayscaleMapping
export RenderTarget, Image2DTarget
export ContrastMethod, ContrastOptions
export RenderOptions, RenderResult2D

# Rendering backends (will be implemented)
# include("backends/cpu.jl")
# include("render/histogram.jl")
# include("render/gaussian.jl")
# include("render/circle.jl")

# Color mapping (will be implemented)
# include("color/mapping.jl")
# include("color/contrast.jl")

# Main interface (will be implemented)
# include("interface.jl")

# Export main interface
# export render, render_overlay

end
