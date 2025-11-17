"""
# 3D Octamer Simulation with Z-Depth Coloring

This example demonstrates:
1. 3D SMLM simulation with z-depth variation
2. Color-coding by z-depth to visualize 3D structure in 2D projection
3. Multiple colormaps to compare depth visualization

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

println("="^70)
println("3D Octamer Simulation - Z-Depth Color Coding")
println("="^70)

# 1. Create 3D simulation
println("\n[1/3] Simulating 3D octamer data...")

params_3d = StaticSMLMParams(
    density = 2.0,              # 2 patterns per μm²
    σ_psf = 0.13,               # Lateral PSF width (130nm)
    nframes = 10,               # 10 frames → ~5 blinks per emitter
    framerate = 20.0,           # 20 fps
    ndims = 3,                  # ENABLE 3D
    zrange = [-0.5, 0.5]        # Z-range: -500nm to +500nm depth
)

# Create 3D octamer pattern
octamer_3d = Nmer3D(n=8, d=0.15)  # 8 molecules, 150nm diameter

# Fluorophore with realistic blinking
fluor = GenericFluor(
    photons = 2000.0,
    k_off = 10.0,
    k_on = 0.5
)

# Camera
camera = IdealCamera(128, 128, 0.1)  # 128×128 pixels, 100nm pixel size

# Run 3D simulation
smld_true_3d, smld_model_3d, smld_noisy_3d = simulate(
    params_3d;
    pattern = octamer_3d,
    molecule = fluor,
    camera = camera
)

# Extract z-coordinates
z_coords = [e.z for e in smld_noisy_3d.emitters]
z_min, z_max = minimum(z_coords), maximum(z_coords)

println("  ✓ Generated $(length(smld_noisy_3d.emitters)) 3D localizations")
println("  ✓ Mean photons: $(round(mean([e.photons for e in smld_noisy_3d.emitters]), digits=1))")
println("  ✓ Z-depth range: $(round(z_min*1000, digits=1))nm to $(round(z_max*1000, digits=1))nm")
println("  ✓ Mean σ_x: $(round(mean([e.σ_x for e in smld_noisy_3d.emitters])*1000, digits=1)) nm")

# 2. Render 2D projections colored by z-depth
println("\n[2/3] Rendering z-depth colored projections...")

output_dir = joinpath(@__DIR__, "output")
mkpath(output_dir)

# Render with different colormaps for depth visualization
zoom = 20  # 5nm pixels

# Image 1: Z-depth with viridis (perceptual, good contrast)
println("  • Rendering octamer_3d_depth_viridis.png...")
t1 = @elapsed render(smld_noisy_3d,
    strategy = GaussianRender(),
    color_by = :z,           # Color by z-depth!
    colormap = :viridis,     # Purple (deep) → Yellow (shallow)
    zoom = zoom,
    filename = joinpath(output_dir, "octamer_3d_depth_viridis.png")
)
println("    ✓ $(round(t1*1000, digits=1)) ms")

# Image 2: Z-depth with turbo (high contrast rainbow)
println("  • Rendering octamer_3d_depth_turbo.png...")
t2 = @elapsed render(smld_noisy_3d,
    strategy = GaussianRender(),
    color_by = :z,
    colormap = :turbo,       # Google turbo - very high contrast
    zoom = zoom,
    filename = joinpath(output_dir, "octamer_3d_depth_turbo.png")
)
println("    ✓ $(round(t2*1000, digits=1)) ms")

# Image 3: Z-depth with RdBu (diverging - shows depth symmetry)
println("  • Rendering octamer_3d_depth_RdBu.png...")
t3 = @elapsed render(smld_noisy_3d,
    strategy = GaussianRender(),
    color_by = :z,
    colormap = :RdBu,        # Red (deep) ↔ Blue (shallow)
    zoom = zoom,
    filename = joinpath(output_dir, "octamer_3d_depth_RdBu.png")
)
println("    ✓ $(round(t3*1000, digits=1)) ms")

# Image 4: Z-depth with plasma (high contrast perceptual)
println("  • Rendering octamer_3d_depth_plasma.png...")
t4 = @elapsed render(smld_noisy_3d,
    strategy = GaussianRender(),
    color_by = :z,
    colormap = :plasma,      # Blue → Pink → Yellow
    zoom = zoom,
    filename = joinpath(output_dir, "octamer_3d_depth_plasma.png")
)
println("    ✓ $(round(t4*1000, digits=1)) ms")

# 3. Summary
println("\n" * "="^70)
println("3D DEPTH VISUALIZATION SUMMARY")
println("="^70)
println("Dataset: $(length(smld_noisy_3d.emitters)) 3D localizations")
println("Z-depth range: $(round(z_min*1000, digits=1))nm to $(round(z_max*1000, digits=1))nm")
println("Field of view: 12.8μm × 12.8μm × $(round((z_max-z_min)*1000, digits=1))nm depth")
println("\nGeneration Times (render + save):")
println("  - octamer_3d_depth_viridis.png:   $(round(t1*1000, digits=1)) ms")
println("  - octamer_3d_depth_turbo.png:     $(round(t2*1000, digits=1)) ms")
println("  - octamer_3d_depth_RdBu.png:      $(round(t3*1000, digits=1)) ms")
println("  - octamer_3d_depth_plasma.png:    $(round(t4*1000, digits=1)) ms")
println("\nColormaps for Z-Depth:")
println("  • viridis:  Purple (deep) → Yellow (shallow) - perceptual uniform")
println("  • turbo:    Rainbow spectrum - very high contrast")
println("  • RdBu:     Red ↔ Blue diverging - shows depth symmetry")
println("  • plasma:   Blue → Yellow - high contrast perceptual")
println("\nIntensity-Weighted Color:")
println("  Color from z-depth + Brightness from overlap density")
println("  Gamma = 0.6 for punchy, vibrant colors")
println("="^70)

println("\n✓ All 3D depth images saved to $(output_dir)/")
println("\nGenerated files (4 z-depth colormaps):")
println("  - octamer_3d_depth_viridis.png    (perceptual uniform)")
println("  - octamer_3d_depth_turbo.png      (high contrast rainbow)")
println("  - octamer_3d_depth_RdBu.png       (diverging red-blue)")
println("  - octamer_3d_depth_plasma.png     (high contrast perceptual)")
