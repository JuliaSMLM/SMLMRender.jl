using Pkg
Pkg.activate(temp = true)
Pkg.add([
    "Images",
    "Colors",
    "ColorSchemes",
    "FileIO",
    "CairoMakie",
])

using Images
using Colors
using ColorSchemes
using FileIO
using CairoMakie

CairoMakie.activate!()  # ensure backend is active

# --------------------------
# Parameters and grid
# --------------------------

nx, ny = 512, 512                     # image size
xs = range(0f0, 1f0; length = nx)
ys = range(0f0, 1f0; length = ny)

σ_xy = 0.015f0                        # Gaussian width (fraction of image size)

# z range for color mapping (nm, arbitrary)
zmin, zmax = -300.0f0, 300.0f0

# --------------------------
# Synthetic "SMLM" structure:
#   - vertical line at low z
#   - horizontal line at high z
#   - diagonal line at mid z
# --------------------------

locs = NamedTuple[]

# Vertical line at x = 0.5, z = -200 nm (low z, bluish)
for y in range(0.1f0, 0.9f0; length = 40)
    push!(locs, (x = 0.50f0, y = y, z = -200.0f0, amp = 1.0f0))
end

# Horizontal line at y = 0.5, z = +200 nm (high z, reddish)
for x in range(0.1f0, 0.9f0; length = 40)
    push!(locs, (x = x, y = 0.50f0, z = 200.0f0, amp = 1.0f0))
end

# Diagonal line from bottom-left to top-right at z = 0 nm (mid z, greenish)
for t in range(0.15f0, 0.85f0; length = 40)
    push!(locs, (x = t, y = t, z = 0.0f0, amp = 1.0f0))
end

# --------------------------
# Accumulate scalar intensity and color numerators
# --------------------------

S    = zeros(Float32, nx, ny)   # total scalar intensity
Rnum = zeros(Float32, nx, ny)   # Σ w * r
Gnum = zeros(Float32, nx, ny)   # Σ w * g
Bnum = zeros(Float32, nx, ny)   # Σ w * b

for loc in locs
    # Map z -> t ∈ [0,1]
    t = clamp((loc.z - zmin) / (zmax - zmin), 0f0, 1f0)

    # Choose a z-colormap (jet just for demo; swap to viridis/balance if you prefer)
    c = get(ColorSchemes.jet, t)
    r, g, b = Float32(red(c)), Float32(green(c)), Float32(blue(c))

    # Add Gaussian blob to S, Rnum, Gnum, Bnum
    @inbounds for ix in 1:nx, iy in 1:ny
        dx = xs[ix] - loc.x
        dy = ys[iy] - loc.y
        w = loc.amp * exp(-0.5f0 * ((dx / σ_xy)^2 + (dy / σ_xy)^2))

        S[ix, iy]    += w
        Rnum[ix, iy] += w * r
        Gnum[ix, iy] += w * g
        Bnum[ix, iy] += w * b
    end
end

# --------------------------
# Intensity-weighted color + brightness scaling
# --------------------------

ε = 1f-6
R = Rnum ./ (S .+ ε)
G = Gnum ./ (S .+ ε)
B = Bnum ./ (S .+ ε)

# Brightness from total intensity S (gamma gives more dynamic range)
Smax = maximum(S)
Smax == 0 && (Smax = 1f0)
S_norm = S ./ Smax

γ = 0.6f0
Bscale = S_norm .^ γ

Rimg = clamp.(R .* Bscale, 0f0, 1f0)
Gimg = clamp.(G .* Bscale, 0f0, 1f0)
Bimg = clamp.(B .* Bscale, 0f0, 1f0)

img = colorview(RGB, Rimg, Gimg, Bimg)

# --------------------------
# Save and display
# --------------------------

save("smlm_zcolor_crosslines.png", img)

f = Figure(size = (600, 600))
ax = CairoMakie.Axis(
    f[1, 1];
    title = "z-colored crossing lines (intensity-weighted)",
    xlabel = "x",
    ylabel = "y",
)

xlims = (first(xs), last(xs))
ylims = (first(ys), last(ys))

CairoMakie.image!(ax, xlims, ylims, img)
hidedecorations!(ax; grid = false)
resize_to_layout!(f)

save("smlm_zcolor_crosslines_makie.png", f)
display(f)

println("Saved images: smlm_zcolor_crosslines.png and smlm_zcolor_crosslines_makie.png")
