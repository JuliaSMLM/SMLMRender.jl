"""
# SMLMRender Strategies Demo

This example demonstrates SMLMRender.jl's core workflow:
1. Simulate SMLM data with SMLMSim
2. Batch generate images with different rendering strategies and color mappings
3. All using direct save (filename kwarg) - the primary workflow

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

println("="^70)
println("SMLMRender.jl - Batch Image Generation Demo")
println("="^70)

# 1. Create simulation data
println("\n[1/3] Simulating octamer SMLM data...")

params = StaticSMLMParams(
    density = 2.0,        # 2 patterns per μm²
    σ_psf = 0.13,         # 130nm PSF width
    nframes = 10,         # 10 frames → ~5 blinks per emitter, ~40 per octamer
    framerate = 20.0,     # 20 fps (0.5 second acquisition)
    ndims = 2             # 2D simulation
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

# 2. Batch generate images with direct save
println("\n[2/3] Batch generating images (direct save workflow)...")

output_dir = joinpath(@__DIR__, "output")
mkpath(output_dir)

# Image 1: Gaussian + inferno (classic SMLM look)
println("  • Rendering octamer_inferno.png...")
t1 = @elapsed render(smld_noisy,
    strategy = GaussianRender(),
    colormap = :inferno,
    zoom = 20,  # 5nm pixels - good for smooth Gaussian blobs
    filename = joinpath(output_dir, "octamer_inferno.png")
)
println("    ✓ $(round(t1*1000, digits=1)) ms")

# Image 2: Gaussian + hot (alternative classic)
println("  • Rendering octamer_hot.png...")
t2 = @elapsed render(smld_noisy,
    strategy = GaussianRender(),
    colormap = :hot,
    zoom = 20,  # 5nm pixels
    filename = joinpath(output_dir, "octamer_hot.png")
)
println("    ✓ $(round(t2*1000, digits=1)) ms")

# Image 3a: Gaussian + time coloring with viridis (perceptual uniform)
println("  • Rendering octamer_time_viridis.png...")
t3a = @elapsed render(smld_noisy,
    strategy = GaussianRender(),
    color_by = :frame,
    colormap = :viridis,  # Default perceptual colormap
    zoom = 20,
    filename = joinpath(output_dir, "octamer_time_viridis.png")
)
println("    ✓ $(round(t3a*1000, digits=1)) ms")

# Image 3b: Gaussian + time coloring with turbo (high contrast)
println("  • Rendering octamer_time_turbo.png...")
t3b = @elapsed render(smld_noisy,
    strategy = GaussianRender(),
    color_by = :frame,
    colormap = :turbo,  # Google's high-contrast rainbow
    zoom = 20,
    filename = joinpath(output_dir, "octamer_time_turbo.png")
)
println("    ✓ $(round(t3b*1000, digits=1)) ms")

# Image 3c: Gaussian + time coloring with plasma (high contrast perceptual)
println("  • Rendering octamer_time_plasma.png...")
t3c = @elapsed render(smld_noisy,
    strategy = GaussianRender(),
    color_by = :frame,
    colormap = :plasma,  # High contrast perceptual
    zoom = 20,
    filename = joinpath(output_dir, "octamer_time_plasma.png")
)
println("    ✓ $(round(t3c*1000, digits=1)) ms")

# Image 4: Gaussian + photon coloring (brightness information)
println("  • Rendering octamer_photons.png...")
t4 = @elapsed render(smld_noisy,
    strategy = GaussianRender(),
    color_by = :photons,  # Shows brightness of each localization
    colormap = :plasma,  # Good for showing continuous variation
    zoom = 20,  # 5nm pixels
    filename = joinpath(output_dir, "octamer_photons.png")
)
println("    ✓ $(round(t4*1000, digits=1)) ms")

# Image 5: Circles + time (uncertainty + temporal)
println("  • Rendering octamer_circles_time.png...")
t5 = @elapsed render(smld_noisy,
    strategy = CircleRender(
        radius_factor = 1.0,  # 1σ circles (shows localization precision)
        line_width = 1.0,
        use_localization_precision = true
    ),
    color_by = :frame,  # Temporal information
    colormap = :turbo,  # Bright colormap, saturates on overlap for visibility
    zoom = 50,  # 2nm pixels - need high resolution for thin circle lines
    filename = joinpath(output_dir, "octamer_circles_time.png")
)
println("    ✓ $(round(t5*1000, digits=1)) ms")

# Image 6: Histogram + viridis (fast, pixelated)
println("  • Rendering octamer_histogram.png...")
t6 = @elapsed render(smld_noisy,
    strategy = HistogramRender(),
    colormap = :viridis,
    zoom = 10,  # 10nm pixels - fast, intentionally pixelated
    filename = joinpath(output_dir, "octamer_histogram.png")
)
println("    ✓ $(round(t6*1000, digits=1)) ms")

# 3. Optional: Create comparison figure (for analysis)
println("\n[3/3] Creating comparison figure (optional)...")

# Workaround for RGB > 1.0 bug: clamp values
function clamp_rgb(img)
    return map(img) do pixel
        RGB(clamp(pixel.r, 0.0, 1.0),
            clamp(pixel.g, 0.0, 1.0),
            clamp(pixel.b, 0.0, 1.0))
    end
end

# Load the generated images for comparison
img_inferno = render(smld_noisy, strategy=GaussianRender(), colormap=:inferno, zoom=20)
img_time = render(smld_noisy, strategy=GaussianRender(), color_by=:frame,
                  colormap=:twilight, zoom=20)
img_circles = render(smld_noisy, strategy=CircleRender(1.0, 1.0, true, nothing),
                     color_by=:frame, colormap=:turbo, zoom=50)

fig = Figure(size=(1600, 500))

ax1 = Axis(fig[1, 1],
    title = "Gaussian + Inferno\n(intensity colormap)",
    aspect = DataAspect()
)
image!(ax1, rotr90(clamp_rgb(img_inferno)))
hidedecorations!(ax1)

ax2 = Axis(fig[1, 2],
    title = "Gaussian + Time\n(temporal dynamics)",
    aspect = DataAspect()
)
image!(ax2, rotr90(clamp_rgb(img_time)))
hidedecorations!(ax2)

ax3 = Axis(fig[1, 3],
    title = "Circles + Time\n(uncertainty + temporal)",
    aspect = DataAspect()
)
image!(ax3, rotr90(clamp_rgb(img_circles)))
hidedecorations!(ax3)

Label(fig[0, :], "SMLMRender.jl: Rendering Strategy Comparison",
    fontsize = 24, font = :bold)

save(joinpath(output_dir, "comparison.png"), fig)
println("  ✓ Saved comparison.png")

# 4. Summary
println("\n" * "="^70)
println("BATCH GENERATION SUMMARY")
println("="^70)
println("Dataset: $(length(smld_noisy.emitters)) localizations")
println("\nGeneration Times (render + save):")
println("  - octamer_inferno.png:        $(round(t1*1000, digits=1)) ms  (Gaussian + inferno)")
println("  - octamer_hot.png:            $(round(t2*1000, digits=1)) ms  (Gaussian + hot)")
println("  - octamer_time_viridis.png:   $(round(t3a*1000, digits=1)) ms  (Gaussian + time + viridis)")
println("  - octamer_time_turbo.png:     $(round(t3b*1000, digits=1)) ms  (Gaussian + time + turbo)")
println("  - octamer_time_plasma.png:    $(round(t3c*1000, digits=1)) ms  (Gaussian + time + plasma)")
println("  - octamer_photons.png:        $(round(t4*1000, digits=1)) ms  (Gaussian + photons + plasma)")
println("  - octamer_circles_time.png:   $(round(t5*1000, digits=1)) ms  (Circles + time + turbo)")
println("  - octamer_histogram.png:      $(round(t6*1000, digits=1)) ms  (Histogram + viridis)")
println("\nRendering Strategies:")
println("  • GaussianRender:   Smooth, sub-pixel accuracy, publication quality")
println("  • CircleRender:     Visualize localization uncertainty (1σ circles)")
println("  • HistogramRender:  Fast binning, no sub-pixel (good for quick checks)")
println("\nZoom Strategy:")
println("  • Circles:   50x (2nm/pixel) - High resolution for thin lines")
println("  • Gaussian:  20x (5nm/pixel) - Good for smooth blobs")
println("  • Histogram: 10x (10nm/pixel) - Fast, intentionally pixelated")
println("\nColor Mapping:")
println("  • Intensity (colormap):  Accumulate counts → apply colormap (:inferno, :hot)")
println("  • Field-based:           Color by emitter property (:frame, :photons, :σ_x)")
println("\nPrimary Workflow:")
println("  render(smld, strategy=..., colormap=..., zoom=20, filename=\"output.png\")")
println("="^70)

println("\n✓ All images saved to $(output_dir)/")
println("\nGenerated files (8 core images + 1 comparison):")
println("  - octamer_inferno.png         (Gaussian + inferno)")
println("  - octamer_hot.png             (Gaussian + hot)")
println("  - octamer_time_viridis.png    (Gaussian + time + viridis)")
println("  - octamer_time_turbo.png      (Gaussian + time + turbo)")
println("  - octamer_time_plasma.png     (Gaussian + time + plasma)")
println("  - octamer_photons.png         (Gaussian + photons + plasma)")
println("  - octamer_circles_time.png    (Circles + time + turbo, saturates)")
println("  - octamer_histogram.png       (Histogram + viridis)")
println("  - comparison.png              (side-by-side for analysis)")
