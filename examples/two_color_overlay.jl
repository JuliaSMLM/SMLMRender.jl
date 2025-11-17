"""
# Two-Color Multi-Channel Rendering

This example demonstrates multi-channel SMLM rendering:
1. Simulate two separate structures (e.g., two different proteins)
2. Render as two-color overlay with circles and Gaussian blobs
3. Classic red/green two-color STORM visualization

Outputs are saved to examples/output/
"""

# Activate the examples environment
import Pkg
Pkg.activate(@__DIR__)

using SMLMSim
using SMLMData
using SMLMRender
using MicroscopePSFs
using Statistics
using Colors

println("="^70)
println("Two-Color Multi-Channel Rendering")
println("="^70)

# 1. Simulate two separate structures
println("\n[1/3] Simulating two-color SMLM data...")

# Shared parameters
params = StaticSMLMParams(
    density = 1.0,          # 1 pattern per μm²
    σ_psf = 0.13,
    nframes = 10,
    framerate = 20.0,
    ndims = 2
)

fluor = GenericFluor(photons=2000.0, k_off=10.0, k_on=0.5)
camera = IdealCamera(128, 128, 0.1)

# Channel 1: Octamers (protein A)
println("  • Simulating Channel 1 (octamers)...")
pattern1 = Nmer2D(n=8, d=0.15)  # Octamers
smld_true_1, smld_model_1, smld_noisy_1 = simulate(
    params; pattern=pattern1, molecule=fluor, camera=camera
)

# Channel 2: Hexamers at different locations (protein B)
println("  • Simulating Channel 2 (hexamers)...")
pattern2 = Nmer2D(n=6, d=0.12)  # Hexamers (smaller)
smld_true_2, smld_model_2, smld_noisy_2 = simulate(
    params; pattern=pattern2, molecule=fluor, camera=camera
)

println("  ✓ Channel 1: $(length(smld_noisy_1.emitters)) localizations")
println("  ✓ Channel 2: $(length(smld_noisy_2.emitters)) localizations")

# 2. Render two-color overlays
println("\n[2/3] Rendering two-color overlays...")

output_dir = joinpath(@__DIR__, "output")
mkpath(output_dir)

# Image 1: Two-color Gaussian overlay (classic red/green)
println("  • Rendering two_color_gaussian_redgreen.png...")
t1 = @elapsed render(
    [smld_noisy_1, smld_noisy_2],
    colors = [colorant"red", colorant"green"],
    strategy = GaussianRender(),
    zoom = 20,
    filename = joinpath(output_dir, "two_color_gaussian_redgreen.png")
)
println("    ✓ $(round(t1*1000, digits=1)) ms")

# Image 2: Two-color Gaussian overlay (magenta/cyan)
println("  • Rendering two_color_gaussian_magcyan.png...")
t2 = @elapsed render(
    [smld_noisy_1, smld_noisy_2],
    colors = [colorant"magenta", colorant"cyan"],
    strategy = GaussianRender(),
    zoom = 20,
    filename = joinpath(output_dir, "two_color_gaussian_magcyan.png")
)
println("    ✓ $(round(t2*1000, digits=1)) ms")

# Image 3: Two-color Circle overlay (shows uncertainty)
println("  • Rendering two_color_circles_redgreen.png...")
t3 = @elapsed render(
    [smld_noisy_1, smld_noisy_2],
    colors = [colorant"red", colorant"green"],
    strategy = CircleRender(
        radius_factor = 1.0,
        line_width = 1.0,
        use_localization_precision = true
    ),
    zoom = 50,  # High resolution for circles
    filename = joinpath(output_dir, "two_color_circles_redgreen.png")
)
println("    ✓ $(round(t3*1000, digits=1)) ms")

# Image 4: Two-color Circle overlay (magenta/cyan)
println("  • Rendering two_color_circles_magcyan.png...")
t4 = @elapsed render(
    [smld_noisy_1, smld_noisy_2],
    colors = [colorant"magenta", colorant"cyan"],
    strategy = CircleRender(
        radius_factor = 1.0,
        line_width = 1.0,
        use_localization_precision = true
    ),
    zoom = 50,
    filename = joinpath(output_dir, "two_color_circles_magcyan.png")
)
println("    ✓ $(round(t4*1000, digits=1)) ms")

# 3. Summary
println("\n" * "="^70)
println("TWO-COLOR OVERLAY SUMMARY")
println("="^70)
println("Channel 1 (octamers): $(length(smld_noisy_1.emitters)) localizations")
println("Channel 2 (hexamers): $(length(smld_noisy_2.emitters)) localizations")
println("\nGeneration Times (render + save):")
println("  - two_color_gaussian_redgreen.png:   $(round(t1*1000, digits=1)) ms")
println("  - two_color_gaussian_magcyan.png:    $(round(t2*1000, digits=1)) ms")
println("  - two_color_circles_redgreen.png:    $(round(t3*1000, digits=1)) ms")
println("  - two_color_circles_magcyan.png:     $(round(t4*1000, digits=1)) ms")
println("\nColor Schemes:")
println("  • Red/Green:      Classic two-color STORM (most common)")
println("  • Magenta/Cyan:   Alternative palette (good for colorblind)")
println("\nRendering:")
println("  • Gaussian blobs:  Smooth, publication-quality overlay")
println("  • Circles:         Shows localization uncertainty for both channels")
println("\nWorkflow (using multiple dispatch):")
println("  render([smld1, smld2],")
println("         colors=[color1, color2],")
println("         strategy=..., zoom=20, filename=\"output.png\")")
println("="^70)

println("\n✓ All two-color images saved to $(output_dir)/")
println("\nGenerated files (4 two-color overlays):")
println("  - two_color_gaussian_redgreen.png    (Gaussian + red/green)")
println("  - two_color_gaussian_magcyan.png     (Gaussian + magenta/cyan)")
println("  - two_color_circles_redgreen.png     (Circles + red/green)")
println("  - two_color_circles_magcyan.png      (Circles + magenta/cyan)")
println("\nUse for:")
println("  • Two-color STORM/PALM imaging")
println("  • Protein colocalization studies")
println("  • Multi-target visualization")
