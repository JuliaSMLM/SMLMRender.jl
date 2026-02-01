"""
# Categorical Coloring Demo

Demonstrates SMLMRender's categorical coloring feature for visualizing
cluster IDs, molecule IDs, or other discrete labels.

Key features:
- `categorical=true` flag enables discrete color palette
- Colors cycle via mod1(value, palette_size) for large ID ranges
- Works with all render strategies (Gaussian, Circle, Histogram, Ellipse)
- Default palette is :tab10 (10 distinct colors)

Note: SMLMSim automatically populates the `id` field with pattern instance IDs,
so all emitters from the same Nmer share the same ID.

Outputs are saved to examples/output/
"""

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
println("SMLMRender.jl - Categorical Coloring Demo")
println("="^70)

# 1. Simulate data with multiple patterns (octamers)
println("\n[1/3] Simulating octamer SMLM data...")

params = StaticSMLMParams(
    density = 3.0,        # 3 patterns per μm² (more clusters)
    σ_psf = 0.13,
    nframes = 15,
    framerate = 20.0,
    ndims = 2
)

pattern = Nmer2D(n=8, d=0.15)  # Octamer, 150nm diameter
fluor = GenericFluor(photons=2000.0, k_off=10.0, k_on=0.5)
camera = IdealCamera(64, 64, 0.1)  # 6.4μm FOV

smld_true, smld_model, smld_noisy = simulate(params; pattern, molecule=fluor, camera)

n_clusters = length(unique([e.id for e in smld_noisy.emitters]))
println("  ✓ $(length(smld_noisy.emitters)) localizations, $(n_clusters) pattern instances")

# 2. Render with categorical coloring
println("\n[2/3] Rendering with categorical coloring...")

output_dir = joinpath(@__DIR__, "output")
mkpath(output_dir)

clamp_rgb(img) = map(px -> RGB(clamp(px.r, 0, 1), clamp(px.g, 0, 1), clamp(px.b, 0, 1)), img)

# Gaussian + categorical (default tab10)
println("  • categorical_gaussian_tab10.png")
render(smld_noisy, strategy=GaussianRender(), color_by=:id, categorical=true,
       zoom=20, filename=joinpath(output_dir, "categorical_gaussian_tab10.png"))

# Gaussian + Set1 palette
println("  • categorical_gaussian_set1.png")
render(smld_noisy, strategy=GaussianRender(), color_by=:id, colormap=:Set1_9,
       categorical=true, zoom=20, filename=joinpath(output_dir, "categorical_gaussian_set1.png"))

# Circles + categorical
println("  • categorical_circles.png")
render(smld_noisy, strategy=CircleRender(1.0, 1.0, true, nothing),
       color_by=:id, categorical=true, zoom=40,
       filename=joinpath(output_dir, "categorical_circles.png"))

# Histogram + categorical
println("  • categorical_histogram.png")
render(smld_noisy, strategy=HistogramRender(), color_by=:id, categorical=true,
       zoom=10, filename=joinpath(output_dir, "categorical_histogram.png"))

# Intensity comparison
println("  • intensity_comparison.png")
render(smld_noisy, strategy=GaussianRender(), colormap=:inferno,
       zoom=20, filename=joinpath(output_dir, "intensity_comparison.png"))

# 3. Comparison figure
println("\n[3/3] Creating comparison figure...")

r_intensity = render(smld_noisy, strategy=GaussianRender(), colormap=:inferno, zoom=20)
r_categorical = render(smld_noisy, strategy=GaussianRender(), color_by=:id, categorical=true, zoom=20)
r_circles = render(smld_noisy, strategy=CircleRender(1.0, 1.0, true, nothing),
                   color_by=:id, categorical=true, zoom=40)

fig = Figure(size=(1800, 600))

ax1 = Axis(fig[1,1], title="Intensity\n(no cluster info)", aspect=DataAspect())
image!(ax1, rotr90(clamp_rgb(r_intensity.image)))
hidedecorations!(ax1)

ax2 = Axis(fig[1,2], title="Categorical\n(pattern IDs)", aspect=DataAspect())
image!(ax2, rotr90(clamp_rgb(r_categorical.image)))
hidedecorations!(ax2)

ax3 = Axis(fig[1,3], title="Categorical Circles\n(individual locs)", aspect=DataAspect())
image!(ax3, rotr90(clamp_rgb(r_circles.image)))
hidedecorations!(ax3)

Label(fig[0,:], "SMLMRender: Categorical Coloring for Cluster Visualization", fontsize=24, font=:bold)

save(joinpath(output_dir, "categorical_comparison.png"), fig)
println("  ✓ categorical_comparison.png")

println("\n" * "="^70)
println("Usage: render(smld, color_by=:id, categorical=true, zoom=20)")
println("Palettes: :tab10 (default), :Set1_9, :Set2_8, :Set3_12, :tab20")
println("="^70)
