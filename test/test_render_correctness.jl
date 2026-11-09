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
        # A blob cut by the frame edge has the same in-frame pixels as in a larger
        # frame, on both kernel paths and both normalizations.
        for ρ in (0.0, 0.5), normalization in (:integral, :maximum)
            e = Emitter2DFit{Float64}(0.012, 0.207, 1000.0, 10.0, 0.020, 0.012, 50.0, 2.0;
                                      σ_xy=ρ * 0.020 * 0.012)
            smld = BasicSMLD([e], IdealCamera(4, 4, 0.1), 1, 1)
            cfg = RenderConfig(color=:white, clip_percentile=nothing,
                               strategy=GaussianRender(normalization=normalization))
            (big, _) = render(smld, Image2DTarget(60, 41, 10.0, (-0.19, 0.41), (0.0, 0.41)), cfg)
            (cut, _) = render(smld, Image2DTarget(41, 41, 10.0, (0.0, 0.41), (0.0, 0.41)), cfg)
            @test map(red, cut) ≈ map(red, big[:, 20:60])
        end
    end

    @testset ":maximum finds the window's brightest pixel by its ridge search" begin
        # The frame starts 3 rows below the localization's row, so the peak lies
        # outside it. Its pixels must equal the full window's integral render
        # divided by that window's brightest pixel: on both kernel paths, both
        # search axes, and thin tilted blobs whose brightest pixel is not the one
        # nearest their center.
        golden = 0.6180339887498949
        cfg(n) = RenderConfig(color=:white, clip_percentile=nothing,
                              strategy=GaussianRender(normalization=n))
        k = 0
        for (σx, σy) in ((2.0, 2.0), (3.0, 12.0), (12.0, 3.0), (25.0, 4.0), (4.0, 25.0), (1.5, 30.0)),
            ρ in (0.0, 0.006, -0.009, 0.3, -0.8, 0.97, -0.999)
            k += 1
            x = 0.300 + 0.01 * mod(k * golden, 1.0)              # inside pixel 31 (μm)
            y = 0.300 + 0.01 * mod(k * golden^2 + 0.37, 1.0)
            e = Emitter2DFit{Float64}(x, y, 1000.0, 10.0, σx / 1000, σy / 1000, 50.0, 2.0;
                                      σ_xy=ρ * σx * σy / 1e6)
            smld = BasicSMLD([e], IdealCamera(8, 8, 0.1), 1, 1)
            (full, _) = render(smld, Image2DTarget(61, 61, 10.0, (0.0, 0.61), (0.0, 0.61)), cfg(:integral))
            (cut, _) = render(smld, Image2DTarget(61, 28, 10.0, (0.0, 0.61), (0.33, 0.61)), cfg(:maximum))
            @test map(red, cut) ≈ map(red, full[34:61, :]) ./ maximum(red, full)
        end
        # Cost: a wide correlated blob on a tiny frame evaluates only its in-image
        # pixels (a whole-window peak search built a 1202 × 1202 corner grid, 11.6 MB).
        e = Emitter2DFit{Float64}(0.005, 0.005, 1000.0, 10.0, 0.2, 0.2, 50.0, 2.0; σ_xy=0.3 * 0.2 * 0.2)
        smld = BasicSMLD([e], IdealCamera(4, 4, 0.1), 1, 1)
        tiny = Image2DTarget(10, 10, 1.0, (0.0, 0.01), (0.0, 0.01))
        (img, _) = render(smld, tiny, cfg(:maximum))
        @test maximum(red, img) ≈ 1.0
        @test (@allocated render(smld, tiny, cfg(:maximum))) < 1_000_000
    end

    @testset "Gaussian field and categorical color every pixel with intensity" begin
        # σ = 500 nm on 1 nm pixels: each pixel holds about 6e-7 of the
        # localization's mass, below the fixed 1e-6 cut once applied before coloring.
        e = Emitter2DFit{Float64}(0.0205, 0.0205, 1000.0, 10.0, 0.5, 0.5, 50.0, 2.0; id=1)
        smld = BasicSMLD([e], IdealCamera(4, 4, 0.1), 1, 1)
        target = Image2DTarget(41, 41, 1.0, (0.0, 0.041), (0.0, 0.041))
        strategy = GaussianRender(n_sigmas=0.02)         # a 21-pixel window inside the frame
        (white, _) = render(smld, target, RenderConfig(strategy=strategy, color=:white,
                                                      clip_percentile=nothing))
        lit = count(c -> red(c) > 0, white)
        @test lit >= 441
        for clip in (nothing, 0.99), kw in ((color_by=:photons,), (color_by=:id, categorical=true))
            (img, _) = render(smld, target, RenderConfig(; strategy=strategy, clip_percentile=clip, kw...))
            @test count(c -> red(c) + green(c) + blue(c) > 0, img) == lit
        end
        # Raw categorical: each pixel is the category's color times its intensity.
        (cat, _) = render(smld, target, RenderConfig(strategy=strategy, color_by=:id,
                                                    categorical=true, clip_percentile=nothing))
        ratio = [(red(cat[k]) + green(cat[k]) + blue(cat[k])) / red(white[k])
                 for k in eachindex(white) if red(white[k]) > 0]
        @test maximum(ratio) - minimum(ratio) < 1e-9 * maximum(ratio)
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
        # A square Float32 camera whose x edges start far from the origin: their
        # rounding (first spacing 99.976 nm against 100.000 nm in y) must not trip
        # the check.
        far = IdealCamera{Float32}(Float32.(1000 .+ 0.1 .* (0:16)), Float32.(0.1 .* (0:8)))
        e_far = Emitter2DFit{Float32}(1000.25f0, 0.35f0, 1000f0, 10f0, 0.01f0, 0.01f0, 50f0, 2f0)
        (img_far, _) = render(BasicSMLD([e_far], far, 1, 1); zoom=10)
        @test size(img_far) == (80, 160)
        # The output grid covers the camera's own extent on both axes, overshooting
        # by no more than rounding (the first x spacing would cut 0.37 nm off the
        # far x edge), so a localization just inside it renders.
        t_far = create_target_from_smld(BasicSMLD([e_far], far, 1, 1); zoom=10)
        x_ext = Float64(far.pixel_edges_x[end]) - Float64(far.pixel_edges_x[1])
        y_ext = Float64(far.pixel_edges_y[end]) - Float64(far.pixel_edges_y[1])
        cover_x = t_far.width * t_far.pixel_size / 1000 / x_ext
        cover_y = t_far.height * t_far.pixel_size / 1000 / y_ext
        @test min(cover_x, cover_y) >= 1 - 1e-12
        @test max(cover_x, cover_y) < 1 + 1e-4
        e_edge = Emitter2DFit{Float32}(1001.5999f0, 0.35f0, 1000f0, 10f0, 0.01f0, 0.01f0, 50f0, 2f0)
        (img_edge, _) = render(BasicSMLD([e_edge], far, 1, 1); zoom=10,
                               strategy=HistogramRender(), color=:white)
        @test count(c -> red(c) > 0, img_edge) == 1
        # A one-pixel axis cannot average its rounding away; the tolerance covers it.
        one_px = IdealCamera{Float32}(Float32.(1000 .+ 0.1 .* (0:1)), Float32.(0.1 .* (0:8)))
        e_one = Emitter2DFit{Float32}(1000.05f0, 0.35f0, 1000f0, 10f0, 0.01f0, 0.01f0, 50f0, 2f0)
        (img_one, _) = render(BasicSMLD([e_one], one_px, 1, 1); zoom=10)
        @test size(img_one) == (80, 10)
        # ...while pixels 0.1% apart are still refused.
        @test_throws ArgumentError render(BasicSMLD([emitter_at(0.25, 0.25)],
                                                    IdealCamera(16, 8, (0.1, 0.1001)), 1, 1); zoom=10)
        # Both axes are covered: y of the one-pixel camera rounds differently from
        # x, and so does an ROI of the far camera.
        e_top = Emitter2DFit{Float32}(1000.05f0, 0.7999f0, 1000f0, 10f0, 0.01f0, 0.01f0, 50f0, 2f0)
        hist = (strategy=HistogramRender(), color=:white)
        (img_top, _) = render(BasicSMLD([e_top], one_px, 1, 1); zoom=10, hist...)
        @test count(c -> red(c) > 0, img_top) == 1
        (img_roi, _) = render(BasicSMLD([e_top], far, 1, 1); zoom=10, roi=(1:1, :), hist...)
        @test size(img_roi) == (80, 10)
        @test count(c -> red(c) > 0, img_roi) == 1
        # A fractional zoom keeps output pixel = camera pixel / zoom and rounds each
        # dimension up: 3 × 1.5 = 4.5 -> 5 columns, 4 × 1.5 = 6 rows. The grid covers
        # the 300 × 400 nm field, overshoots it by less than one output pixel, and
        # its ranges give its extent.
        cam34 = IdealCamera(3, 4, 0.1)
        t34 = create_target_from_smld(BasicSMLD([emitter_at(0.15, 0.2)], cam34, 1, 1); zoom=1.5)
        @test (t34.width, t34.height) == (5, 6)
        @test t34.pixel_size ≈ 100 / 1.5
        @test t34.x_range[2] ≈ 5 * t34.pixel_size / 1000
        @test t34.y_range[2] ≈ 0.4
        (img34, _) = render(BasicSMLD([emitter_at(0.29, 0.39)], cam34, 1, 1); zoom=1.5, hist...)
        @test count(c -> red(c) > 0, img34) == 1
        # A whole dimension gets no padding: a localization 25 nm past the field
        # stays out of the image.
        (img_out, _) = render(BasicSMLD([emitter_at(0.15, 0.425)], cam34, 1, 1); zoom=1.5, hist...)
        @test !any(c -> red(c) > 0, img_out)
        # Only floating-point rounding counts as whole: a zoom just above a whole
        # number is fractional and rounds up, and a localization just inside the
        # field renders.
        tiny = BasicSMLD([emitter_at(0.09999999, 0.09999999)], IdealCamera(1, 1, 0.1), 1, 1)
        for z in (1.0000005, 1.00001)
            t_tiny = create_target_from_smld(tiny; zoom=z)
            @test (t_tiny.width, t_tiny.height) == (2, 2)
            @test t_tiny.width * t_tiny.pixel_size >= 100.0
            (img_tiny, _) = render(tiny; zoom=z, hist...)
            @test count(c -> red(c) > 0, img_tiny) == 1
        end
        # Whole products stay whole at any size, and floating-point noise in a
        # zoom adds no pixel: 3 plus two ulps still gives 3 (targets only, no image).
        @test create_target_from_smld(tiny; zoom=1_000_000_000).width == 1_000_000_000
        @test create_target_from_smld(tiny; zoom=nextfloat(3.0, 2)).width == 3
        # Unequal rounding on the two axes keeps each one's overshoot below one
        # output pixel (a 1 × 20,000 camera at zoom 100.000099: 101 × 2,000,002).
        long = BasicSMLD([emitter_at(0.05, 0.05)], IdealCamera(1, 20_000, 0.1), 1, 1)
        t_long = create_target_from_smld(long; zoom=100.000099)
        @test (t_long.width, t_long.height) == (101, 2_000_002)
        @test 0 <= t_long.width * t_long.pixel_size - 100 < t_long.pixel_size
        @test 0 <= t_long.height * t_long.pixel_size - 2_000_000 < t_long.pixel_size
        @test t_long.y_range[2] * 1000 - 2_000_000 < t_long.pixel_size
        # A Float32 zoom is used at its Float64 value (1.1f0 = 1.1000000238...,
        # just above 1.1, so 10 camera pixels need 12) through every entry point.
        ten = BasicSMLD([emitter_at(0.55, 0.55)], IdealCamera(10, 10, 0.1), 1, 1)
        t_f32 = create_target_from_smld(ten; zoom=1.1f0)
        (img_f32, info_f32) = render(ten; zoom=1.1f0, hist...)
        (img_ov, info_ov) = render([ten]; colors=[:white], zoom=1.1f0, strategy=HistogramRender())
        @test (t_f32.width, t_f32.height) == (12, 12)
        @test size(img_f32) == size(img_ov) == (12, 12)
        @test info_f32.pixel_size_nm ≈ t_f32.pixel_size
        @test info_ov.pixel_size_nm ≈ t_f32.pixel_size
        # A whole-number zoom always gives roi_pixels × zoom, even when the stored
        # spacings round differently (Float32 x edges at 10 mm: 99.6 against 100 nm).
        tenmm = IdealCamera{Float32}(Float32.(10000 .+ 0.1 .* (0:1)), Float32.(0.1 .* (0:8)))
        e_10mm = Emitter2DFit{Float32}(10000.05f0, 0.4f0, 1000f0, 10f0, 0.01f0, 0.01f0, 50f0, 2f0)
        (img_10mm, _) = render(BasicSMLD([e_10mm], tenmm, 1, 1); zoom=256, hist...)
        @test size(img_10mm) == (2048, 256)
        @test count(c -> red(c) > 0, img_10mm) == 1
        # Explicit edges follow the same rules: square Float32 edges far from the
        # origin render, covering both ranges; rectangular edges are refused.
        ex32 = Float32.(1000 .+ 0.1 .* (0:16))
        ey32 = Float32.(0.1 .* (0:8))
        e_edges = Emitter2DFit{Float32}(1001.5999f0, 0.7999f0, 1000f0, 10f0, 0.01f0, 0.01f0, 50f0, 2f0)
        (img_edges, _) = render(BasicSMLD([e_edges], IdealCamera(4, 4, 0.1), 1, 1), ex32, ey32;
                                strategy=HistogramRender(), color=:white)
        @test size(img_edges) == (8, 16)
        @test count(c -> red(c) > 0, img_edges) == 1
        @test_throws ArgumentError render(BasicSMLD([emitter_at(0.25, 0.25)], IdealCamera(4, 4, 0.1), 1, 1),
                                          0.0:0.1:1.6, 0.0:0.2:1.6; strategy=HistogramRender(), color=:white)
    end

    @testset "Tail-only Gaussian intensities normalize to finite colors" begin
        # Every pixel lies 38 to 48 sigma out in y, so the intensities are
        # subnormal and the reciprocal of their range overflows.
        e = Emitter2DFit{Float64}(0.005, 0.0, 1000.0, 10.0, 0.1, 0.001, 50.0, 2.0; id=1)
        smld = BasicSMLD([e], IdealCamera(4, 4, 0.1), 1, 1)
        target = Image2DTarget(10, 10, 1.0, (0.0, 0.01), (-0.048, -0.038))
        finite(c) = isfinite(red(c)) && isfinite(green(c)) && isfinite(blue(c))
        for kw in ((color_by=:photons,), (color_by=:id, categorical=true), (colormap=:inferno,))
            (img, _) = render(smld, target, RenderConfig(; kw...))
            @test all(finite, img)
        end
    end
end
