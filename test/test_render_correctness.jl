# Correctness checks for where intensity lands and how much, added in the
# November 2026 bug-fix round (findings M1-M6 of the 2026-11-02 review). Each
# testset fails on v0.4.7 and passes after the fix.

using Test, SMLMRender, SMLMData, Colors
using StatsFuns: normcdf
using SMLMRender: get_ellipse_params

# Inverse of a 2×2 matrix (keeps LinearAlgebra out of the test deps).
inv2(M) = [M[2, 2] -M[1, 2]; -M[2, 1] M[1, 1]] ./ (M[1, 1] * M[2, 2] - M[1, 2] * M[2, 1])

emitter_at(x, y; σ=0.01, σ_xy=0.0, T=Float64, frame=1, id=0, photons=1000.0) =
    Emitter2DFit{T}(T(x), T(y), T(photons), T(10), T(σ), T(σ), T(50), T(2);
                    σ_xy=T(σ_xy), frame=frame, id=id)

# A deterministic, irregular cloud of localizations inside [x0, x0+w] × [y0, y0+w] μm.
function cloud(n, x0, y0, w; σ=0.01, T=Float64)
    golden = 0.6180339887498949
    [emitter_at(x0 + w * mod(k * golden, 1.0), y0 + w * mod(k * golden^2 + 0.37, 1.0);
                σ=σ, T=T, frame=k, id=k, photons=500.0 + 10k) for k in 1:n]
end

# Sum of one localization's raw Gaussian (saturate mode, white) on a window of
# the 10 nm pixel grid that keeps its sub-pixel position.
function blob_sum(x, y, σ_nm, σ_xy_nm2=0.0; σy_nm=σ_nm, n_sigmas=6.0, normalization=:integral)
    ps = 10.0
    e = Emitter2DFit{Float64}(x, y, 1000.0, 10.0, σ_nm / 1000, σy_nm / 1000, 50.0, 2.0;
                              σ_xy=σ_xy_nm2 / 1e6)
    target = Image2DTarget(41, 41, ps, (0.0, 0.41), (0.0, 0.41))
    smld = BasicSMLD([e], IdealCamera(4, 4, 0.1), 1, 1)
    cfg = RenderConfig(color=:white, clip_percentile=nothing,
                       strategy=GaussianRender(n_sigmas=n_sigmas, normalization=normalization))
    (img, _) = render(smld, target, cfg)
    return img
end

@testset "Render correctness (2026-11 bug-fix round)" begin

    @testset "M5: field range is Float64 for integer and Float32 fields" begin
        camera = IdealCamera(32, 32, 0.1)
        smld64 = BasicSMLD(cloud(40, 1.0, 1.0, 1.0), camera, 40, 1)
        smld32 = BasicSMLD(cloud(40, 1.0, 1.0, 1.0; T=Float32), camera, 40, 1)
        for strategy in (GaussianRender(), HistogramRender(), CircleRender(), EllipseRender())
            for field in (:frame, :id)
                (img, info) = render(smld64; strategy=strategy, color_by=field,
                                     field_clip_percentiles=nothing, zoom=5)
                @test info.field_range === (1.0, 40.0)
                @test any(c -> c != RGB(0, 0, 0), img)
            end
            (img, info) = render(smld32; strategy=strategy, color_by=:photons,
                                 field_clip_percentiles=nothing, zoom=5)
            @test info.field_range isa Tuple{Float64, Float64}
            @test info.field_range == (510.0, 900.0)
        end
    end

    @testset "M4: single-color Gaussian is clipped and normalized" begin
        camera = IdealCamera(32, 32, 0.1)
        smld = BasicSMLD(cloud(300, 1.0, 1.0, 1.2; σ=0.008), camera, 300, 1)
        for zoom in (5, 50)
            (img, _) = render(smld; color=:red, zoom=zoom)
            @test maximum(red, img) ≈ 1.0
            @test maximum(green, img) == 0.0
            (img_half, _) = render(smld; color=:red, zoom=zoom, clip_percentile=0.5)
            @test img_half != img
            @test maximum(red, img_half) ≈ 1.0
        end
        # Saturate mode keeps the raw accumulated density (the histogram path's
        # meaning of `nothing`): one unit of mass per localization.
        (raw, _) = render(smld; color=:red, zoom=5, clip_percentile=nothing)
        @test isapprox(sum(red, raw), 300; rtol=1e-3)
        # Gaussian field coloring honors saturate mode too (raw intensity, as
        # color= already gave in v0.4.7; it used to silently clip at 0.99).
        (f99, _) = render(smld; color_by=:photons, zoom=5)
        (fsat, _) = render(smld; color_by=:photons, zoom=5, clip_percentile=nothing)
        @test fsat != f99
        # A Gaussian overlay channel is that channel's single-color render,
        # scaled by normalize_each so its brightest component is 1 (:green parses
        # to CSS green, (0, 0.502, 0)).
        smld2 = BasicSMLD(cloud(200, 1.3, 1.1, 1.0; σ=0.012), camera, 200, 1)
        (ov, _) = render([smld, smld2]; colors=[:red, :green], zoom=10)
        (r1, _) = render(smld; color=:red, zoom=10)
        (g2, _) = render(smld2; color=:green, zoom=10)
        @test map(red, ov) ≈ map(red, r1)
        @test map(green, ov) ≈ map(green, g2) ./ maximum(green, g2)
        # normalize_each = false with a clip percentile: each channel is exactly its
        # single-color render (already clipped and scaled), not rescaled.
        (ov_raw, _) = render([smld, smld2]; colors=[:red, :green], zoom=10, normalize_each=false)
        @test map(red, ov_raw) ≈ map(red, r1)
        @test map(green, ov_raw) ≈ map(green, g2)
        # A frame with no empty pixel: zero density stays black (the scale is
        # density / clip value, not min-max), so the dimmest structure is not
        # subtracted away, and an overlay channel equals its single-color render.
        grid = [emitter_at(1.37 + 0.013a + 0.002b, 1.37 + 0.011b; σ=0.03)
                for a in 0:20, b in 0:23]
        dense = BasicSMLD(vec(grid), camera, 1, 1)
        t = Image2DTarget(50, 50, 4.0, (1.4, 1.6), (1.4, 1.6))
        (d1, _) = render(dense, t, RenderConfig(color=:red))
        @test minimum(red, d1) > 0.05
        (dov, _) = render([dense]; colors=[:red], target=t)
        @test map(red, dov) ≈ map(red, d1)
    end

    @testset "M1: overlay in pixel_size mode frames every channel" begin
        camera = IdealCamera(64, 64, 0.1)
        ch1 = BasicSMLD(cloud(121, 1.0, 1.0, 1.0), camera, 121, 1)
        ch2 = BasicSMLD(cloud(121, 4.0, 4.0, 1.0), camera, 121, 1)
        (ov, _) = render([ch1, ch2]; colors=[:red, :green], pixel_size=10.0,
                         clip_percentile=nothing, normalize_each=false)
        # Saturate, un-normalized Gaussian: each channel's total is its
        # localization count, less the window truncation.
        @test sum(green, ov) > 0
        # Lit pixels match each channel rendered alone (the two frames' pixel
        # grids can be offset by a fraction of a pixel, hence the tolerance).
        (a2, _) = render(ch2; color=:green, pixel_size=10.0, clip_percentile=nothing)
        @test isapprox(count(c -> green(c) > 0, ov), count(c -> green(c) > 0, a2); rtol=0.05)
        (a1, _) = render(ch1; color=:red, pixel_size=10.0, clip_percentile=nothing)
        @test isapprox(count(c -> red(c) > 0, ov), count(c -> red(c) > 0, a1); rtol=0.05)
        # The shared frame spans both channels' extents.
        @test size(ov, 2) * 10.0 / 1000 > 4.0
    end

    @testset "M2: each localization deposits unit mass wherever it falls" begin
        # Uncorrelated: exact product of error-function differences.
        # Pixel 21 spans 200-210 nm: (dx, dy) is the offset from its center in
        # pixels, so (0, 0) is the center, (0.5, 0) an edge, (0.5, 0.5) a corner.
        masses = Dict{Tuple{Float64, Float64}, Float64}()
        for σ_px in (0.2, 0.3, 0.5, 1.0, 2.0), (dx, dy) in ((0.0, 0.0), (0.5, 0.0), (0.5, 0.5))
            img = blob_sum(0.205 + 0.01dx, 0.205 + 0.01dy, 10σ_px)
            @test isapprox(sum(red, img), 1.0; atol=1e-6)
            masses[(σ_px, dx + dy)] = sum(red, img)
        end
        # v0.4.7 sampled pixel centers: 2.55 at the center and 0.19 at a corner for σ = 0.25 px
        @test isapprox(masses[(0.2, 0.0)], masses[(0.2, 1.0)]; atol=1e-6)
        # The window covers the wide axis at the default n_sigmas = 3 (a 6:1 blob).
        @test sum(red, blob_sum(0.205, 0.205, 30.0; σy_nm=5.0, n_sigmas=3.0)) > 0.995
        # Correlated: mass exact, and pixel values match a fine-grid integral of
        # the same Gaussian, on both kernel paths (first order in ρ below 0.01,
        # bivariate normal CDF above) and for unequal sigmas.
        for (σx_nm, σy_nm, ρ) in ((5.0, 5.0, 0.8), (4.0, 6.0, -0.5), (5.0, 3.0, 0.009), (3.0, 5.0, -0.004))
            x, y = 0.2032, 0.1968
            sxy = ρ * σx_nm * σy_nm
            img = blob_sum(x, y, σx_nm, sxy; σy_nm=σy_nm)
            @test isapprox(sum(red, img), 1.0; atol=1e-5)
            Σi = inv2([σx_nm^2 sxy; sxy σy_nm^2])
            norm = 1 / (2π * σx_nm * σy_nm * sqrt(1 - ρ^2))
            n = 200                               # 200 × 200 sub-samples per pixel
            for (i, j) in ((21, 21), (20, 21), (21, 22), (20, 22), (22, 20), (19, 23))
                acc = 0.0
                for a in 1:n, b in 1:n
                    px = (j - 1) * 10.0 + (b - 0.5) * 10.0 / n - 1000x
                    py = (i - 1) * 10.0 + (a - 0.5) * 10.0 / n - 1000y
                    acc += exp(-0.5 * (Σi[1, 1] * px^2 + 2Σi[1, 2] * px * py + Σi[2, 2] * py^2))
                end
                @test isapprox(red(img[i, j]), acc * norm * (10.0 / n)^2; atol=2e-5)
            end
        end
        # Thin, tilted blobs in both orientations and a near-singular one, against
        # an independent reference: the exact conditional x-probability integrated
        # over y with 4000 midpoint samples per pixel row.
        function conditional_ref(i, j, x, y, σx, σy, ρ)
            s = σx * sqrt(1 - ρ^2)
            β = ρ * σx / σy
            n = 4000
            xl, xr = (j - 1) * 10.0 - 1000x, j * 10.0 - 1000x
            acc = 0.0
            for a in 1:n
                yy = (i - 1) * 10.0 + (a - 0.5) * 10.0 / n - 1000y
                acc += exp(-0.5 * (yy / σy)^2) / (sqrt(2π) * σy) *
                       (normcdf((xr - β * yy) / s) - normcdf((xl - β * yy) / s))
            end
            return acc * 10.0 / n
        end
        for (σx_nm, σy_nm, ρ) in ((20.0, 2.0, 0.9), (2.0, 20.0, 0.9), (2.5, 2.5, 0.99))
            x, y = 0.2030, 0.1980
            img = blob_sum(x, y, σx_nm, ρ * σx_nm * σy_nm; σy_nm=σy_nm)
            @test isapprox(sum(red, img), 1.0; atol=1e-5)
            worst = maximum(abs(red(img[i, j]) - conditional_ref(i, j, x, y, σx_nm, σy_nm, ρ))
                            for i in 15:27, j in 15:27)
            @test worst < 1e-5
        end
        # :maximum: each localization's brightest pixel is 1 wherever it falls and
        # whatever its sigma (v0.4.7: 1 at a pixel center, 0.018 at a corner for 0.25 px).
        for σ_nm in (2.5, 5.0, 30.0), (dx, dy) in ((0.0, 0.0), (0.5, 0.5), (0.3, -0.2))
            img = blob_sum(0.205 + 0.01dx, 0.205 + 0.01dy, σ_nm; normalization=:maximum)
            @test maximum(red, img) ≈ 1.0
        end
        # ...and the peak is the whole window's: a localization 3 px outside the
        # frame shows only its dim tail.
        @test 0 < maximum(red, blob_sum(-0.025, 0.205, 10.0; normalization=:maximum)) < 0.05
    end

    @testset "M3: ellipse outline is the covariance ellipse" begin
        strategy = EllipseRender(radius_factor=2.0)
        mahalanobis_error(e) = begin
            rx, ry, θ = get_ellipse_params(e, strategy)
            Σi = inv2([(1000e.σ_x)^2 1e6e.σ_xy; 1e6e.σ_xy (1000e.σ_y)^2])
            maximum(range(0, 2π; length=97)) do t
                xl, yl = rx * cos(t), ry * sin(t)
                p = [xl * cos(θ) - yl * sin(θ), xl * sin(θ) + yl * cos(θ)]
                abs(sqrt(p' * Σi * p) / 2.0 - 1)
            end
        end
        corr(σx, σy, ρ) = Emitter2DFit{Float64}(1.0, 1.0, 1000.0, 10.0, σx, σy, 50.0, 2.0;
                                                σ_xy=ρ * σx * σy)
        @test mahalanobis_error(corr(0.020, 0.020, 0.9)) < 1e-9
        @test mahalanobis_error(corr(0.020, 0.012, -0.5)) < 1e-9
        @test mahalanobis_error(corr(0.012, 0.020, 0.3)) < 1e-9
        # σ_x < σ_y with a vanishing σ_xy (fitted data) must not swap the axes.
        @test mahalanobis_error(corr(0.004, 0.006, 1e-6)) < 1e-9
        @test mahalanobis_error(corr(0.020, 0.012, 0.0)) < 1e-9

        # The drawn image: lit pixels sit on the 1σ covariance ellipse.
        e = corr(0.020, 0.020, 0.9)
        target = Image2DTarget(161, 161, 1.0, (0.9195, 1.0805), (0.9195, 1.0805))
        (img, _) = render(BasicSMLD([e], IdealCamera(20, 20, 0.1), 1, 1), target,
                          RenderConfig(strategy=EllipseRender(), color=:white))
        Σi = inv2([400.0 360.0; 360.0 400.0])
        r = [sqrt([j - 81.0, i - 81.0]' * Σi * [j - 81.0, i - 81.0])
             for i in 1:161, j in 1:161 if red(img[i, j]) > 0.5]
        @test !isempty(r)
        @test maximum(abs.(r .- 1)) < 0.2
        # A near-singular covariance (ρ = 0.99999) draws as a line, not nothing.
        e_line = corr(0.020, 0.020, 0.99999)
        (img_line, _) = render(BasicSMLD([e_line], IdealCamera(20, 20, 0.1), 1, 1), target,
                               RenderConfig(strategy=EllipseRender(), color=:white))
        @test count(c -> red(c) > 0, img_line) > 20
    end

    @testset "M6: zoom mode refuses rectangular camera pixels" begin
        camera = IdealCamera(16, 8, (0.1, 0.2))
        smld = BasicSMLD([emitter_at(0.25, 1.5)], camera, 1, 1)
        @test_throws ArgumentError render(smld; zoom=10)
        @test_throws ArgumentError create_target_from_smld(smld; zoom=10)
        # pixel_size mode does not depend on the camera's pixels
        (img, _) = render(smld; pixel_size=10.0, strategy=HistogramRender(), color=:white)
        @test any(c -> red(c) > 0, img)
        # square pixels still render in zoom mode
        square = BasicSMLD([emitter_at(0.25, 0.75)], IdealCamera(16, 8, 0.1), 1, 1)
        (img_sq, _) = render(square; zoom=10)
        @test size(img_sq) == (80, 160)
        # A square Float32 camera far from the origin: rounding of its edges must
        # not trip the check.
        far = IdealCamera{Float32}(Float32.(1000 .+ 0.1 .* (0:16)), Float32.(1000 .+ 0.1 .* (0:8)))
        e_far = Emitter2DFit{Float32}(1000.25f0, 1000.35f0, 1000f0, 10f0, 0.01f0, 0.01f0, 50f0, 2f0)
        (img_far, _) = render(BasicSMLD([e_far], far, 1, 1); zoom=10)
        @test size(img_far) == (80, 160)
    end
end
