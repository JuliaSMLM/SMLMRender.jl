"""
# SMLMRender Strategies Demo

This example demonstrates SMLMRender.jl's rendering capabilities:
1. Simulate SMLM data with SMLMSim
2. Render using different strategies (Histogram, Gaussian, Circle)
3. Show different color mapping options
4. Compare rendering quality and speed

Outputs are saved to examples/output/
"""

# Activate the examples environment
import Pkg
Pkg.activate(@__DIR__)

using SMLMSim
using SMLMData
using SMLMRender
using MicroscopePSFs
using CairoMakie
using Statistics
using Colors

println("="^70)
println("SMLMRender.jl Rendering Strategies Demo")
println("="^70)

# 1. Create simulation data
println("\n[1/4] Simulating octamer SMLM data...")

params = StaticSMLMParams(
    density = 2.0,        # 2 patterns per μm² (more patterns)
    σ_psf = 0.13,
    nframes = 500,        # Fewer frames for faster demo
    framerate = 20.0,
    ndims = 2
)

pattern = Nmer2D(n=8, d=0.15)  # Octamer, 150nm diameter

fluor = GenericFluor(
    photons = 2000.0,
    k_off = 10.0,
    k_on = 0.5
)

camera = IdealCamera(128, 128, 0.1)  # 128×128 pixels, 100nm pixel size

smld_true, smld_model, smld_noisy = simulate(
    params;
    pattern = pattern,
    molecule = fluor,
    camera = camera
)

println("  ✓ Generated $(length(smld_noisy.emitters)) localizations")
println("  ✓ Mean photons: $(round(mean([e.photons for e in smld_noisy.emitters]), digits=1))")
println("  ✓ Mean σ_x: $(round(mean([e.σ_x for e in smld_noisy.emitters])*1000, digits=1)) nm")

# 2. Render with different strategies
println("\n[2/4] Rendering with different strategies...")

output_dir = joinpath(@__DIR__, "output")
mkpath(output_dir)

# Strategy 1: Histogram Rendering (fastest)
println("  • Histogram rendering...")
t1 = @elapsed img_histogram = render(smld_noisy,
    strategy = HistogramRender(),
    colormap = :inferno,
    zoom = 10  # 10nm pixels (10x better than camera)
)
println("    ✓ Complete in $(round(t1*1000, digits=1)) ms")

# Strategy 2: Gaussian Rendering with localization precision
println("  • Gaussian rendering (with localization precision)...")
t2 = @elapsed img_gaussian = render(smld_noisy,
    strategy = GaussianRender(
        n_sigmas = 3.0,
        use_localization_precision = true,
        fixed_sigma = nothing,
        normalization = :integral
    ),
    colormap = :hot,
    zoom = 10
)
println("    ✓ Complete in $(round(t2*1000, digits=1)) ms")

# Strategy 3: Gaussian Rendering with fixed sigma
println("  • Gaussian rendering (fixed 15nm sigma)...")
t3 = @elapsed img_gaussian_fixed = render(smld_noisy,
    strategy = GaussianRender(
        n_sigmas = 3.0,
        use_localization_precision = false,
        fixed_sigma = 15.0,  # 15nm fixed sigma
        normalization = :integral
    ),
    colormap = :viridis,
    zoom = 10
)
println("    ✓ Complete in $(round(t3*1000, digits=1)) ms")

# Strategy 4: Circle Rendering (shows uncertainty)
println("  • Circle rendering (2σ circles)...")
t4 = @elapsed img_circles = render(smld_noisy,
    strategy = CircleRender(
        radius_factor = 2.0,  # 2σ circles
        line_width = 1.0,
        use_localization_precision = true,
        fixed_radius = nothing
    ),
    color_by = :photons,  # Uses default :viridis colormap
    zoom = 10
)
println("    ✓ Complete in $(round(t4*1000, digits=1)) ms")

# Demonstrate direct save with filename kwarg (NEW FEATURE!)
println("  • Direct save with filename kwarg...")
t5 = @elapsed render(smld_noisy,
    strategy = GaussianRender(),
    colormap = :magma,
    zoom = 10,
    filename = joinpath(output_dir, "direct_save_example.png")  # Saves automatically!
)
println("    ✓ Rendered and saved in $(round(t5*1000, digits=1)) ms")

# 3. Create comparison figure
println("\n[3/4] Creating comparison visualizations...")

# Workaround: Clamp RGB values to [0,1] (should be done in SMLMRender)
function clamp_rgb(img)
    return map(img) do pixel
        RGB(clamp(pixel.r, 0.0, 1.0),
            clamp(pixel.g, 0.0, 1.0),
            clamp(pixel.b, 0.0, 1.0))
    end
end

fig1 = Figure(size=(1600, 1200))

# Row 1: Different rendering strategies
ax1 = Axis(fig1[1, 1],
    title = "Histogram Render\n($(round(t1*1000, digits=1)) ms)",
    aspect = DataAspect()
)
image!(ax1, rotr90(clamp_rgb(img_histogram)))
hidedecorations!(ax1)

ax2 = Axis(fig1[1, 2],
    title = "Gaussian Render (precision)\n($(round(t2*1000, digits=1)) ms)",
    aspect = DataAspect()
)
image!(ax2, rotr90(clamp_rgb(img_gaussian)))
hidedecorations!(ax2)

ax3 = Axis(fig1[2, 1],
    title = "Gaussian Render (15nm fixed)\n($(round(t3*1000, digits=1)) ms)",
    aspect = DataAspect()
)
image!(ax3, rotr90(clamp_rgb(img_gaussian_fixed)))
hidedecorations!(ax3)

ax4 = Axis(fig1[2, 2],
    title = "Circle Render (2σ, colored by photons)\n($(round(t4*1000, digits=1)) ms)",
    aspect = DataAspect()
)
image!(ax4, rotr90(clamp_rgb(img_circles)))
hidedecorations!(ax4)

# Add overall title
Label(fig1[0, :], "SMLMRender.jl Rendering Strategies Comparison",
    fontsize = 24, font = :bold)

save(joinpath(output_dir, "rendering_strategies.png"), fig1)
println("  ✓ Saved rendering_strategies.png")

# 4. Demonstrate color mapping options
println("\n[4/4] Demonstrating color mapping options...")

# Color by different fields (uses default :viridis colormap for field-based coloring)
println("  • Color by photons...")
img_color_photons = render(smld_noisy,
    strategy = GaussianRender(),
    color_by = :photons,
    zoom = 10
)

println("  • Color by localization precision (σ_x)...")
img_color_sigma = render(smld_noisy,
    strategy = GaussianRender(),
    color_by = :σ_x,
    zoom = 10
)

println("  • Color by time (frame number) - shows temporal dynamics...")
# This is especially useful for visualizing blinking dynamics or diffusion over time
img_color_frame = render(smld_noisy,
    strategy = GaussianRender(),
    color_by = :frame,
    zoom = 10,
    filename = joinpath(output_dir, "temporal_coloring.png")  # Direct save!
)
println("    ✓ Saved temporal_coloring.png")

# Create color mapping comparison
fig2 = Figure(size=(1600, 400))

ax5 = Axis(fig2[1, 1],
    title = "Color by photons",
    aspect = DataAspect()
)
image!(ax5, rotr90(clamp_rgb(img_color_photons)))
hidedecorations!(ax5)

ax6 = Axis(fig2[1, 2],
    title = "Color by precision σ_x",
    aspect = DataAspect()
)
image!(ax6, rotr90(clamp_rgb(img_color_sigma)))
hidedecorations!(ax6)

ax7 = Axis(fig2[1, 3],
    title = "Color by frame number",
    aspect = DataAspect()
)
image!(ax7, rotr90(clamp_rgb(img_color_frame)))
hidedecorations!(ax7)

Label(fig2[0, :], "Field-Based Color Mapping Examples (all use :viridis)",
    fontsize = 24, font = :bold)

save(joinpath(output_dir, "color_mapping.png"), fig2)
println("  ✓ Saved color_mapping.png")

# 5. Performance summary
println("\n" * "="^70)
println("PERFORMANCE SUMMARY")
println("="^70)
println("Dataset: $(length(smld_noisy.emitters)) localizations")
println("\nRendering Times:")
println("  - Histogram:              $(round(t1*1000, digits=1)) ms  (baseline)")
println("  - Gaussian (precision):   $(round(t2*1000, digits=1)) ms  ($(round(t2/t1, digits=1))× slower)")
println("  - Gaussian (fixed σ):     $(round(t3*1000, digits=1)) ms  ($(round(t3/t1, digits=1))× slower)")
println("  - Circle (2σ):            $(round(t4*1000, digits=1)) ms  ($(round(t4/t1, digits=1))× slower)")
println("\nRendering Strategies:")
println("  - HistogramRender:  Fast, no sub-pixel accuracy")
println("  - GaussianRender:   High quality, sub-pixel accuracy, realistic PSF")
println("  - CircleRender:     Visualize localization uncertainty")
println("\nColor Mapping Options:")
println("  - Intensity colormaps: accumulate intensity → apply colormap")
println("  - Field-based: color each localization by field value (photons, σ, time)")
println("  - Manual colors: fixed color (useful for multi-channel overlays)")
println("\nDirect Save Feature:")
println("  - Use filename kwarg for one-step render + save workflow")
println("  - Example: render(smld, zoom=10, filename=\"output.png\")")
println("="^70)

println("\n✓ All outputs saved to $(output_dir)/")
println("\nGenerated files:")
println("  - rendering_strategies.png  (compare 4 rendering methods)")
println("  - color_mapping.png         (compare field-based coloring)")
println("  - direct_save_example.png   (direct save demo)")
println("  - temporal_coloring.png     (color by time/frame)")
