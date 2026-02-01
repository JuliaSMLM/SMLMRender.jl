# Percentile Clipping Comparison
#
# Demonstrates the difference between current and proposed percentile clipping methods
# for intensity scaling in SMLM rendering.
#
# Problem: Bright outliers (aggregates, artifacts) dominate the intensity scale,
# making sparse signal barely visible.
#
# Solution: Use 95th percentile of non-zero pixels as ceiling, then compute
# 99th percentile of pixels below that ceiling ("real blob" distribution).

using SMLMData
using SMLMRender
using Statistics
using ColorSchemes
using Colors

# Output directory
output_dir = joinpath(@__DIR__, "output")
mkpath(output_dir)

println("=" ^ 60)
println("Percentile Clipping Comparison")
println("=" ^ 60)

# Create synthetic SMLM data with outliers
camera = IdealCamera(64, 64, 100.0)  # 64x64 pixels, 100nm pixel size
emitters = Emitter2DFit[]

# Uniform sparse field (normal signal)
println("\nGenerating synthetic data...")
for _ in 1:3000
    x = 0.2 + 6.0 * rand()
    y = 0.2 + 6.0 * rand()
    push!(emitters, Emitter2DFit(x, y, 500.0, 10.0, 0.020, 0.020, 50.0, 2.0, 1, 1, 1, length(emitters)+1))
end
println("  Sparse signal: 3000 localizations")

# Dense clusters (moderate brightness)
for _ in 1:20
    cx, cy = 0.5 + 5.5 * rand(), 0.5 + 5.5 * rand()
    for _ in 1:20
        x = cx + 0.02 * randn()
        y = cy + 0.02 * randn()
        push!(emitters, Emitter2DFit(x, y, 500.0, 10.0, 0.020, 0.020, 50.0, 2.0, 1, 1, 1, length(emitters)+1))
    end
end
println("  Dense clusters: 20 clusters × 20 locs")

# Outlier aggregates (very bright - simulates aggregates/artifacts)
for _ in 1:5
    cx, cy = 1.0 + 4.5 * rand(), 1.0 + 4.5 * rand()
    for _ in 1:150
        x = cx + 0.008 * randn()
        y = cy + 0.008 * randn()
        push!(emitters, Emitter2DFit(x, y, 500.0, 10.0, 0.020, 0.020, 50.0, 2.0, 1, 1, 1, length(emitters)+1))
    end
end
println("  Outlier aggregates: 5 spots × 150 locs")

smld = BasicSMLD(emitters, camera, 1, 1)
println("\nTotal: $(length(emitters)) localizations")

# Create render target
target = create_target_from_smld(smld, pixel_size=10.0)
println("Image size: $(target.width) × $(target.height) pixels")

# Build intensity histogram manually
using SMLMRender: physical_to_pixel_index, in_bounds

intensity = zeros(Float64, target.height, target.width)
for e in smld.emitters
    i, j = physical_to_pixel_index(e.x, e.y, target)
    if in_bounds(i, j, target)
        intensity[i, j] += 1.0
    end
end

# Analyze distribution
nonzero = filter(x -> x > 0, vec(intensity))
println("\n" * "-" ^ 40)
println("Intensity Distribution (non-zero pixels)")
println("-" ^ 40)
println("  Count: $(length(nonzero)) pixels")
println("  Range: $(Int(minimum(nonzero))) - $(Int(maximum(nonzero)))")
println("  Median: $(median(nonzero))")
println("  95th percentile: $(quantile(nonzero, 0.95))")
println("  99th percentile: $(quantile(nonzero, 0.99))")

# CURRENT METHOD: 99th percentile of all non-zero pixels
clip_current = quantile(nonzero, 0.99)

# NEW METHOD: 99th percentile of pixels below 95th percentile ceiling
ceiling = quantile(nonzero, 0.95)
real_blob = filter(x -> x <= ceiling, nonzero)
clip_new = quantile(real_blob, 0.99)

println("\n" * "-" ^ 40)
println("Clipping Comparison")
println("-" ^ 40)
println("  CURRENT (99th of nonzero): $(round(clip_current, digits=1))")
println("  Ceiling (95th of nonzero): $(round(ceiling, digits=1))")
println("  NEW (99th of real blob):   $(round(clip_new, digits=1))")
println("  Ratio: $(round(clip_current/clip_new, digits=1))×")

# Render with both methods
cmap = colorschemes[:inferno]

# Current method
img_current = clamp.(intensity ./ clip_current, 0, 1)
rgb_current = [get(cmap, v) for v in img_current]
save_image(joinpath(output_dir, "percentile_current_99th.png"), rgb_current)

# New method
img_new = clamp.(intensity ./ clip_new, 0, 1)
rgb_new = [get(cmap, v) for v in img_new]
save_image(joinpath(output_dir, "percentile_new_95ceil_99th.png"), rgb_new)

println("\n" * "=" ^ 60)
println("Output saved to examples/output/")
println("=" ^ 60)
println("  percentile_current_99th.png    - Current: 99th percentile of nonzero")
println("  percentile_new_95ceil_99th.png - New: 99th of (nonzero ≤ 95th)")
println()
println("The NEW method makes sparse signal visible by excluding outliers")
println("from the percentile calculation.")
