"""
# Octamer Rendering Example

This example demonstrates a complete SMLM simulation and rendering workflow:
1. Simulate octamer patterns with realistic photophysics
2. Generate microscope images
3. Create multiple visualization types:
   - Raw microscope images
   - Super-resolution reconstruction
   - Localization scatter plot with uncertainties
   - Ground truth overlay comparison

Outputs are saved to examples/output/

NOTE: This example uses SMLMSim/SMLMData but does NOT use SMLMRender.jl.
For examples using SMLMRender, see render_strategies_demo.jl
"""

# Activate the examples environment
import Pkg
Pkg.activate(@__DIR__)

using SMLMSim
using SMLMData
using MicroscopePSFs
using CairoMakie
using Statistics

println("Creating octamer SMLM simulation...")

# 1. Define simulation parameters
params = StaticSMLMParams(
    density = 1.0,        # 1 pattern per μm²
    σ_psf = 0.13,         # 130nm PSF width
    nframes = 1000,       # 1000 frames
    framerate = 20.0,     # 20 fps
    ndims = 2             # 2D simulation
)

# 2. Create octamer pattern (8 molecules in a ring)
pattern = Nmer2D(n=8, d=0.15)  # 150nm diameter

# 3. Create fluorophore with realistic blinking
fluor = GenericFluor(
    photons = 2000.0,     # 2000 photons per blink
    k_off = 10.0,         # 10 Hz off-rate
    k_on = 0.5            # 0.5 Hz on-rate
)

# 4. Define camera
camera = IdealCamera(128, 128, 0.1)  # 128×128 pixels, 100nm pixel size

# 5. Run simulation
println("Running simulation (this may take a moment)...")
smld_true, smld_model, smld_noisy = simulate(
    params;
    pattern = pattern,
    molecule = fluor,
    camera = camera
)

println("Simulation complete!")
println("  - Ground truth: $(length(smld_true.emitters)) positions")
println("  - With blinking: $(length(smld_model.emitters)) localizations")
println("  - With noise: $(length(smld_noisy.emitters)) localizations")

# 6. Generate microscope images
println("\nGenerating microscope images...")
psf = GaussianPSF(0.15)  # 150nm PSF width

images = gen_images(
    smld_model,           # Use model with blinking
    psf;
    support = 1.0,        # 1μm radius (much faster than Inf)
    bg = 5.0,             # 5 background photons/pixel
    poisson_noise = true  # Add photon counting noise
)

println("Generated $(size(images, 3)) frames of size $(size(images, 1))×$(size(images, 2))")

# 7. Create visualizations
println("\nCreating visualizations...")

# Set up output directory
output_dir = joinpath(@__DIR__, "output")
mkpath(output_dir)

# ===== Figure 1: Raw Microscope Images (first 4 frames) =====
fig1 = Figure(size=(1200, 300))

for i in 1:4
    ax = Axis(fig1[1, i],
        title = "Frame $i",
        xlabel = "x (pixels)",
        ylabel = "y (pixels)",
        aspect = DataAspect()
    )

    heatmap!(ax, images[:, :, i],
        colormap = :inferno,
        interpolate = false
    )
end

save(joinpath(output_dir, "microscope_images.png"), fig1)
println("  ✓ Saved microscope_images.png")

# ===== Figure 2: Super-Resolution Reconstruction =====
println("  Computing super-resolution reconstruction...")

# Extract positions and photons from noisy data
x_coords = [e.x for e in smld_noisy.emitters]
y_coords = [e.y for e in smld_noisy.emitters]
photons = [e.photons for e in smld_noisy.emitters]

# Create 2D histogram with 10nm pixel size (10x better than camera)
# Get camera dimensions from pixel edges
nx_cam = length(camera.pixel_edges_x) - 1
ny_cam = length(camera.pixel_edges_y) - 1
pixel_size = camera.pixel_edges_x[2] - camera.pixel_edges_x[1]

x_min, x_max = 0.0, nx_cam * pixel_size
y_min, y_max = 0.0, ny_cam * pixel_size
pixel_sr = 0.01  # 10nm super-resolution pixels

x_edges = x_min:pixel_sr:x_max
y_edges = y_min:pixel_sr:y_max

# Manually create 2D histogram
nx_sr = length(x_edges) - 1
ny_sr = length(y_edges) - 1
hist_2d = zeros(Float64, nx_sr, ny_sr)

for (x, y) in zip(x_coords, y_coords)
    # Find bin indices
    ix = searchsortedfirst(x_edges, x) - 1
    iy = searchsortedfirst(y_edges, y) - 1

    # Check bounds
    if 1 <= ix <= nx_sr && 1 <= iy <= ny_sr
        hist_2d[ix, iy] += 1
    end
end

fig2 = Figure(size=(800, 800))
ax2 = Axis(fig2[1, 1],
    title = "Super-Resolution Reconstruction\n$(length(smld_noisy.emitters)) localizations",
    xlabel = "x (μm)",
    ylabel = "y (μm)",
    aspect = DataAspect()
)

hm = heatmap!(ax2, x_edges[1:end-1], y_edges[1:end-1], hist_2d',
    colormap = :hot,
    interpolate = false
)

Colorbar(fig2[1, 2], hm, label = "Localizations per pixel")

save(joinpath(output_dir, "super_resolution.png"), fig2)
println("  ✓ Saved super_resolution.png")

# ===== Figure 3: Localization Scatter with Uncertainties =====
# Sample subset for visualization (too many points otherwise)
n_sample = min(5000, length(smld_noisy.emitters))
sample_idx = rand(1:length(smld_noisy.emitters), n_sample)
sample_emitters = smld_noisy.emitters[sample_idx]

x_sample = [e.x for e in sample_emitters]
y_sample = [e.y for e in sample_emitters]
σ_x_sample = [e.σ_x for e in sample_emitters]
photons_sample = [e.photons for e in sample_emitters]

fig3 = Figure(size=(900, 800))
ax3 = Axis(fig3[1, 1],
    title = "Localization Scatter Plot\n($(n_sample) random localizations)",
    xlabel = "x (μm)",
    ylabel = "y (μm)",
    aspect = DataAspect()
)

# Color by photons, size by uncertainty
scatter!(ax3, x_sample, y_sample,
    markersize = 3 .+ (σ_x_sample ./ maximum(σ_x_sample)) .* 5,
    color = photons_sample,
    colormap = :viridis,
    alpha = 0.6
)

Colorbar(fig3[1, 2], limits = (minimum(photons_sample), maximum(photons_sample)),
    colormap = :viridis,
    label = "Photons"
)

save(joinpath(output_dir, "localization_scatter.png"), fig3)
println("  ✓ Saved localization_scatter.png")

# ===== Figure 4: Ground Truth Overlay Comparison =====
# Get ground truth positions
x_true = [e.x for e in smld_true.emitters]
y_true = [e.y for e in smld_true.emitters]

fig4 = Figure(size=(1400, 700))

# Left: Super-resolution
ax4a = Axis(fig4[1, 1],
    title = "Super-Resolution Reconstruction",
    xlabel = "x (μm)",
    ylabel = "y (μm)",
    aspect = DataAspect()
)

heatmap!(ax4a, x_edges[1:end-1], y_edges[1:end-1], hist_2d',
    colormap = :hot,
    interpolate = false
)

# Right: Ground truth overlay
ax4b = Axis(fig4[1, 2],
    title = "Ground Truth Overlay",
    xlabel = "x (μm)",
    ylabel = "y (μm)",
    aspect = DataAspect()
)

heatmap!(ax4b, x_edges[1:end-1], y_edges[1:end-1], hist_2d',
    colormap = :hot,
    interpolate = false,
    alpha = 0.7
)

scatter!(ax4b, x_true, y_true,
    color = :cyan,
    markersize = 8,
    marker = :circle,
    strokewidth = 1,
    strokecolor = :white,
    label = "Ground truth"
)

axislegend(ax4b, position = :rt)

save(joinpath(output_dir, "comparison.png"), fig4)
println("  ✓ Saved comparison.png")

# ===== Statistics Summary =====
println("\n" * "="^60)
println("SIMULATION STATISTICS")
println("="^60)
println("Camera: $(nx_cam)×$(ny_cam) pixels @ $(pixel_size*1000)nm")
println("Field of view: $(x_max) × $(y_max) μm²")
println("Frames: $(params.nframes) @ $(params.framerate) fps")
println("\nLocalizations:")
println("  - Ground truth molecules: $(length(smld_true.emitters))")
println("  - Observed with blinking: $(length(smld_model.emitters))")
println("  - With localization noise: $(length(smld_noisy.emitters))")
println("\nPhoton statistics:")
println("  - Mean: $(round(mean(photons), digits=1)) photons")
println("  - Std: $(round(std(photons), digits=1)) photons")
println("  - Min: $(round(minimum(photons), digits=1)) photons")
println("  - Max: $(round(maximum(photons), digits=1)) photons")
println("\nLocalization precision:")
σ_x_all = [e.σ_x for e in smld_noisy.emitters]
σ_y_all = [e.σ_y for e in smld_noisy.emitters]
println("  - Mean σ_x: $(round(mean(σ_x_all)*1000, digits=1)) nm")
println("  - Mean σ_y: $(round(mean(σ_y_all)*1000, digits=1)) nm")
println("  - Best σ: $(round(minimum(σ_x_all)*1000, digits=1)) nm")
println("="^60)

println("\n✓ All outputs saved to $(output_dir)/")
println("\nGenerated files:")
println("  - microscope_images.png  (raw camera frames)")
println("  - super_resolution.png   (10nm pixel reconstruction)")
println("  - localization_scatter.png  (individual localizations)")
println("  - comparison.png         (reconstruction vs ground truth)")
