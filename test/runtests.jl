using SMLMRender
using SMLMData
using Test
using Colors

# Helper to create test emitters compatible with SMLMData 0.5+
function make_emitter2d(x, y, photons, bg, σ_x, σ_y, σ_photons, σ_bg; frame=1, dataset=1, track_id=0, id=0)
    Emitter2DFit{Float64}(x, y, photons, bg, σ_x, σ_y, σ_photons, σ_bg;
                          frame=frame, dataset=dataset, track_id=track_id, id=id)
end

@testset "SMLMRender.jl" begin

    @testset "RenderInfo struct" begin
        # Test RenderInfo constructor
        info = RenderInfo(
            elapsed_s = 0.001,
            backend = :cpu,
            device_id = 0,
            n_emitters_rendered = 100,
            output_size = (512, 512),
            pixel_size_nm = 10.0,
            strategy = :gaussian,
            color_mode = :intensity,
            field_range = nothing
        )

        @test info.elapsed_s == 0.001
        @test info.backend == :cpu
        @test info.device_id == 0
        @test info.n_emitters_rendered == 100
        @test info.output_size == (512, 512)
        @test info.pixel_size_nm == 10.0
        @test info.strategy == :gaussian
        @test info.color_mode == :intensity
        @test info.field_range === nothing

        # Test with field_range
        info_with_range = RenderInfo(
            elapsed_s = 0.0005,
            backend = :cpu,
            device_id = 0,
            n_emitters_rendered = 50,
            output_size = (256, 256),
            pixel_size_nm = 5.0,
            strategy = :histogram,
            color_mode = :field,
            field_range = (0.0, 100.0)
        )

        @test info_with_range.field_range == (0.0, 100.0)
    end

    @testset "Tuple return pattern" begin
        # Create minimal test data
        camera = IdealCamera(64, 64, 100.0)
        emitters = [
            make_emitter2d(3.2, 3.2, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; frame=1, id=1),
            make_emitter2d(3.5, 3.5, 1500.0, 12.0, 0.018, 0.018, 60.0, 2.5; frame=2, id=2),
            make_emitter2d(3.8, 3.2, 800.0, 8.0, 0.025, 0.025, 40.0, 1.5; frame=3, id=3),
        ]
        smld = BasicSMLD(emitters, camera, 3, 1)

        # Test basic render returns tuple
        result = render(smld, zoom=10)
        @test result isa Tuple{Matrix{RGB{Float64}}, RenderInfo}

        (img, info) = result
        @test img isa Matrix{RGB{Float64}}
        @test info isa RenderInfo

        # Verify RenderInfo fields
        @test info.elapsed_s > 0
        @test info.elapsed_s < 60.0  # Less than 60 seconds
        @test info.backend == :cpu
        @test info.device_id == 0
        @test info.n_emitters_rendered == 3
        @test info.output_size == size(img)
        @test info.pixel_size_nm > 0
        @test info.strategy == :gaussian
        @test info.color_mode == :intensity
    end

    @testset "Strategy symbols in RenderInfo" begin
        camera = IdealCamera(32, 32, 100.0)
        emitters = [make_emitter2d(1.6, 1.6, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; id=1)]
        smld = BasicSMLD(emitters, camera, 1, 1)

        # Test Gaussian strategy
        (_, info_gauss) = render(smld, strategy=GaussianRender(), zoom=5)
        @test info_gauss.strategy == :gaussian

        # Test Histogram strategy
        (_, info_hist) = render(smld, strategy=HistogramRender(), zoom=5)
        @test info_hist.strategy == :histogram

        # Test Circle strategy (needs explicit color - doesn't support intensity mapping)
        (_, info_circ) = render(smld, strategy=CircleRender(), color=:red, zoom=10)
        @test info_circ.strategy == :circle

        # Test Ellipse strategy (needs explicit color - doesn't support intensity mapping)
        (_, info_ell) = render(smld, strategy=EllipseRender(), color=:green, zoom=10)
        @test info_ell.strategy == :ellipse
    end

    @testset "Color mode symbols in RenderInfo" begin
        camera = IdealCamera(32, 32, 100.0)
        emitters = [make_emitter2d(1.6, 1.6, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; id=1)]
        smld = BasicSMLD(emitters, camera, 1, 1)

        # Test intensity mode (default)
        (_, info_intensity) = render(smld, colormap=:inferno, zoom=5)
        @test info_intensity.color_mode == :intensity

        # Test field mode
        (_, info_field) = render(smld, color_by=:photons, zoom=5)
        @test info_field.color_mode == :field
        @test info_field.field_range !== nothing

        # Test categorical mode
        (_, info_cat) = render(smld, color_by=:id, categorical=true, zoom=5)
        @test info_cat.color_mode == :categorical

        # Test manual mode
        (_, info_manual) = render(smld, color=:red, zoom=5)
        @test info_manual.color_mode == :manual
    end

    @testset "Categorical id 0 renders as gray" begin
        palette = SMLMRender.categorical_palette(:tab10)
        n = length(palette)

        # id 0 is reserved for unclustered/background -> fixed gray
        @test SMLMRender.categorical_color(0, palette) == SMLMRender.CATEGORICAL_ZERO_COLOR
        @test SMLMRender.categorical_color(0, palette) == RGB{Float64}(0.5, 0.5, 0.5)

        # Positive ids use the palette (and are not the gray)
        @test SMLMRender.categorical_color(1, palette) != SMLMRender.CATEGORICAL_ZERO_COLOR
        @test SMLMRender.categorical_color(1, palette) == RGB{Float64}(palette[1])

        # Cycling intact for values beyond palette size
        @test SMLMRender.categorical_color(n + 1, palette) ==
              SMLMRender.categorical_color(1, palette)

        # Gray-like palette entries are filtered out: tab10's 8th color is
        # (0.498,0.498,0.498), which would collide with the noise gray.
        @test n == length(SMLMRender.get_colormap(:tab10)) - 1
        @test !any(SMLMRender.is_gray_like, palette)
        # No positive cluster id (full cycle) ever renders gray-like
        @test all(!SMLMRender.is_gray_like(SMLMRender.categorical_color(k, palette))
                  for k in 1:n)
    end

    @testset "Field range in RenderInfo" begin
        camera = IdealCamera(32, 32, 100.0)
        emitters = [
            make_emitter2d(1.6, 1.6, 500.0, 10.0, 0.02, 0.02, 50.0, 2.0; frame=1, id=1),
            make_emitter2d(1.8, 1.8, 2000.0, 10.0, 0.02, 0.02, 50.0, 2.0; frame=2, id=2),
        ]
        smld = BasicSMLD(emitters, camera, 2, 1)

        # Field coloring should populate field_range
        (_, info) = render(smld, color_by=:photons, zoom=5)
        @test info.field_range !== nothing
        @test info.field_range isa Tuple{Float64, Float64}
        @test info.field_range[1] < info.field_range[2]

        # Intensity coloring should have nothing
        (_, info_int) = render(smld, colormap=:inferno, zoom=5)
        @test info_int.field_range === nothing
    end

    @testset "Multi-channel render returns tuple" begin
        camera = IdealCamera(32, 32, 100.0)
        emitters1 = [make_emitter2d(1.6, 1.6, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; id=1)]
        emitters2 = [make_emitter2d(1.8, 1.8, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; id=1)]
        smld1 = BasicSMLD(emitters1, camera, 1, 1)
        smld2 = BasicSMLD(emitters2, camera, 1, 1)

        result = render([smld1, smld2], colors=[:red, :green], zoom=5)
        @test result isa Tuple{Matrix{RGB{Float64}}, RenderInfo}

        (img, info) = result
        @test img isa Matrix{RGB{Float64}}
        @test info.n_emitters_rendered == 2  # Total from both channels
        @test info.color_mode == :manual
    end

    @testset "Overlay clip_percentile applies per-channel" begin
        # Test _clip_rgb_channels directly: create an RGB image with a known outlier
        # and verify clipping reduces its value
        using SMLMRender: _clip_rgb_channels

        test_img = zeros(RGB{Float64}, 10, 10)
        # Fill with moderate values in red channel
        for i in 1:9, j in 1:9
            test_img[i, j] = RGB(0.5, 0.0, 0.0)
        end
        # Add bright outlier in red channel
        test_img[10, 10] = RGB(10.0, 0.0, 0.0)

        clipped = _clip_rgb_channels(copy(test_img), 0.95)

        # The outlier red value should be reduced by clipping
        @test clipped[10, 10].r < test_img[10, 10].r
        # Non-outlier red values should be unchanged (below percentile)
        @test clipped[1, 1].r == test_img[1, 1].r
        # Green channel (all zero) should stay zero
        @test maximum(c.g for c in clipped) == 0.0

        # Integration test: overlay with histogram (which already clips internally)
        # just verifies the overlay path accepts clip_percentile without error
        camera = IdealCamera(64, 64, 100.0)
        emitters1 = [
            make_emitter2d(3.2, 3.2, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; frame=1, id=1),
        ]
        emitters2 = [
            make_emitter2d(3.5, 3.5, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; frame=1, id=2),
        ]
        smld1 = BasicSMLD(emitters1, camera, 1, 1)
        smld2 = BasicSMLD(emitters2, camera, 1, 1)

        # Default clip_percentile=0.99 should work
        (img, info) = render([smld1, smld2], colors=[:red, :green], zoom=10)
        @test img isa Matrix{RGB{Float64}}
        @test info.color_mode == :manual

        # Explicit clip_percentile=nothing disables overlay clipping
        (img2, _) = render([smld1, smld2], colors=[:red, :green], zoom=10,
                           clip_percentile=nothing)
        @test img2 isa Matrix{RGB{Float64}}
    end

    @testset "Primary form render(smld, target, config)" begin
        camera = IdealCamera(32, 32, 100.0)
        emitters = [make_emitter2d(1.6, 1.6, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; id=1)]
        smld = BasicSMLD(emitters, camera, 1, 1)

        # Create target and config explicitly
        target = create_target_from_smld(smld, zoom=5)
        config = RenderConfig(colormap=:inferno, clip_percentile=0.99)

        # Test primary form
        result = render(smld, target, config)
        @test result isa Tuple{Matrix{RGB{Float64}}, RenderInfo}

        (img, info) = result
        @test size(img) == (target.height, target.width)
        @test info.strategy == :gaussian
        @test info.color_mode == :intensity

        # Test config form (target in config)
        config2 = RenderConfig(zoom=5, colormap=:inferno)
        (img2, info2) = render(smld, config2)
        @test img2 isa Matrix{RGB{Float64}}
        @test info2.strategy == :gaussian
    end

    @testset "Scalebar integration" begin
        camera = IdealCamera(64, 64, 100.0)
        emitters = [
            make_emitter2d(3.2, 3.2, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; frame=1, id=1),
            make_emitter2d(3.5, 3.5, 1500.0, 12.0, 0.018, 0.018, 60.0, 2.5; frame=2, id=2),
        ]
        smld = BasicSMLD(emitters, camera, 2, 1)

        # scalebar=false (default) should not modify image
        (img_no_sb, info) = render(smld, zoom=10)
        @test img_no_sb isa Matrix{RGB{Float64}}
        @test info.scalebar_length_um === nothing

        # scalebar=true with auto length
        (img_sb, info_sb) = render(smld, zoom=10, scalebar=true)
        @test img_sb isa Matrix{RGB{Float64}}
        @test size(img_sb) == size(img_no_sb)
        # Image should differ (scalebar drawn on it)
        @test img_sb != img_no_sb
        # Auto-calculated length should be reported
        @test info_sb.scalebar_length_um isa Float64
        @test info_sb.scalebar_length_um > 0

        # scalebar=true with explicit length and options
        # Note: camera pixel size is 100μm, zoom=10 → 10μm/pixel output
        (img_sb2, info_sb2) = render(smld, zoom=10, scalebar=true,
                              scalebar_length=500.0, scalebar_position=:tl,
                              scalebar_color=:black)
        @test img_sb2 isa Matrix{RGB{Float64}}
        @test size(img_sb2) == size(img_no_sb)
        @test info_sb2.scalebar_length_um == 500.0

        # RenderConfig form
        config = RenderConfig(zoom=10, scalebar=true, scalebar_length=200.0)
        (img_cfg, info_cfg) = render(smld, config)
        @test img_cfg isa Matrix{RGB{Float64}}
        @test info_cfg.scalebar_length_um == 200.0

        # Overlay with scalebar
        emitters2 = [make_emitter2d(3.8, 3.2, 800.0, 8.0, 0.025, 0.025, 40.0, 1.5; frame=1, id=3)]
        smld2 = BasicSMLD(emitters2, camera, 1, 1)
        (img_ov, info_ov) = render([smld, smld2], colors=[:red, :green], zoom=10, scalebar=true)
        @test img_ov isa Matrix{RGB{Float64}}
        @test info_ov.color_mode == :manual
        @test info_ov.scalebar_length_um isa Float64
    end

    @testset "Tuple unpacking patterns" begin
        camera = IdealCamera(32, 32, 100.0)
        emitters = [make_emitter2d(1.6, 1.6, 1000.0, 10.0, 0.02, 0.02, 50.0, 2.0; id=1)]
        smld = BasicSMLD(emitters, camera, 1, 1)

        # Full unpacking
        (img, info) = render(smld, zoom=5)
        @test img isa Matrix{RGB{Float64}}
        @test info isa RenderInfo

        # Discard info
        img_only, _ = render(smld, zoom=5)
        @test img_only isa Matrix{RGB{Float64}}

        # Discard image (less common but valid)
        _, info_only = render(smld, zoom=5)
        @test info_only isa RenderInfo

        # Direct indexing
        result = render(smld, zoom=5)
        @test result[1] isa Matrix{RGB{Float64}}
        @test result[2] isa RenderInfo
    end

    @testset "compose" begin
        # Create two small test images
        bg = fill(RGB{Float64}(0.5, 0.5, 0.5), 10, 10)
        bg[1, 1] = RGB{Float64}(0.0, 0.0, 0.0)  # black pixel

        fg = zeros(RGB{Float64}, 10, 10)
        fg[5, 5] = RGB{Float64}(1.0, 0.0, 0.0)  # red pixel

        # Additive blend
        added = compose(bg, fg, blend=:additive)
        @test added[5, 5] ≈ RGB{Float64}(1.0, 0.5, 0.5)  # gray + red
        @test added[1, 1] ≈ RGB{Float64}(0.0, 0.0, 0.0)  # bg was black here, fg is zero → stays black

        # Replace blend — non-black fg pixels overwrite
        replaced = compose(bg, fg, blend=:replace)
        @test replaced[5, 5] ≈ RGB{Float64}(1.0, 0.0, 0.0)  # red replaces gray
        @test replaced[3, 3] ≈ RGB{Float64}(0.5, 0.5, 0.5)  # no fg, keeps bg

        # Replace with black fg pixel — should NOT overwrite
        @test replaced[1, 1] ≈ RGB{Float64}(0.0, 0.0, 0.0)  # bg was black, fg absent → stays black

        # Vector form
        vec_result = compose([bg, fg], blend=:replace)
        @test vec_result == replaced

        # Dimension mismatch
        @test_throws AssertionError compose(bg, zeros(RGB{Float64}, 5, 5))

        # Invalid blend mode
        @test_throws AssertionError compose(bg, fg, blend=:invalid)
    end

    @testset "Empty and few-localization robustness" begin
        # Regression: render() must not crash on 0 or 1-2 localizations and must
        # return a valid image (blank for empty) across every
        # strategy × color-mode × resolution-mode combination. Previously empty
        # input crashed in reductions (extrema/quantile over empty values,
        # zero-span target bounds) and tiny inputs hit a 0-dimension target.
        cam = IdealCamera(32, 32, 100.0)

        # SMLD with n emitters (n=0 → typed-empty vector).
        make_n(n) = BasicSMLD(
            n == 0 ? Emitter2DFit{Float64}[] :
                     [make_emitter2d(3.0 + 0.05k, 3.0 + 0.05k, 1000.0, 10.0,
                                     0.02, 0.02, 50.0, 2.0; frame=1, id=k)
                      for k in 1:n],
            cam, 1, 1)

        # color-mode label => render kwargs
        intensity   = (:intensity,   (; colormap=:inferno))
        field       = (:field,       (; color_by=:photons))
        categorical = (:categorical, (; color_by=:id, categorical=true))
        manual      = (:manual,      (; color=:red))

        # Circle/Ellipse don't support the intensity colormap.
        strategies = [
            (:gaussian,  GaussianRender(),  [intensity, field, categorical, manual]),
            (:histogram, HistogramRender(), [intensity, field, categorical, manual]),
            (:circle,    CircleRender(),    [field, categorical, manual]),
            (:ellipse,   EllipseRender(),   [field, categorical, manual]),
        ]

        for (sname, strat, modes) in strategies, (cname, ckw) in modes,
            resmode in (:zoom, :pixel_size), n in (0, 1, 2)

            rkw = resmode === :zoom ? (; zoom=5) : (; pixel_size=100.0)

            # Must not throw for 0, 1, or 2 localizations.
            img = nothing; info = nothing; threw = false
            try
                (img, info) = render(make_n(n); strategy=strat, rkw..., ckw...)
            catch err
                threw = true
                @info "render threw" sname cname resmode n err
            end
            @test !threw
            threw && continue

            # Valid RGB image with positive, info-consistent dimensions.
            @test img isa Matrix{RGB{Float64}}
            @test size(img, 1) > 0 && size(img, 2) > 0
            @test size(img) == info.output_size
            @test info.n_emitters_rendered == n
            @test all(p -> isfinite(p.r) && isfinite(p.g) && isfinite(p.b), img)

            if n == 0
                # Empty input → spatially uniform (no spurious localized signal).
                @test all(==(first(img)), img)
                if cname === :intensity
                    # Colormap zero (blank background), far below the previous
                    # mid-colormap fill that wrongly painted empties solid.
                    @test max(first(img).r, first(img).g, first(img).b) < 0.1
                else
                    # All other modes render an empty input as pure black.
                    @test first(img) == RGB{Float64}(0.0, 0.0, 0.0)
                end
            end
        end
    end

    @testset "Physical scale in PNG pHYs chunk" begin
        # Read the pHYs chunk straight out of the file rather than trusting a
        # library round-trip: this is the on-disk contract other tools read.
        function read_phys(path)
            bytes = read(path)
            i = 9  # skip the 8-byte PNG signature
            while i < length(bytes) - 8
                len = Int(bytes[i]) << 24 | Int(bytes[i+1]) << 16 |
                      Int(bytes[i+2]) << 8 | Int(bytes[i+3])
                typ = String(bytes[i+4:i+7])
                if typ == "pHYs"
                    p = i + 8
                    ppux = Int(bytes[p])   << 24 | Int(bytes[p+1]) << 16 |
                           Int(bytes[p+2]) << 8  | Int(bytes[p+3])
                    ppuy = Int(bytes[p+4]) << 24 | Int(bytes[p+5]) << 16 |
                           Int(bytes[p+6]) << 8  | Int(bytes[p+7])
                    return (ppux, ppuy, Int(bytes[p+8]))
                end
                i += 12 + len
            end
            return nothing
        end

        # nm per pixel recovered from a pHYs pixels-per-meter reading
        nm_from_ppu(ppu) = 1e9 / ppu

        emitters = [make_emitter2d(1.0, 1.0, 1000.0, 10.0, 0.01, 0.01, 50.0, 2.0),
                    make_emitter2d(2.0, 2.0, 1200.0, 10.0, 0.01, 0.01, 50.0, 2.0)]
        camera = IdealCamera(1:32, 1:32, 0.1)   # 100 nm pixels
        smld = BasicSMLD(emitters, camera, 1, 1, Dict{String,Any}())

        dir = mktempdir()

        @testset "single-render save site" begin
            f = joinpath(dir, "single.png")
            (_, info) = render(smld; zoom=10, filename=f)

            @test isfile(f)
            phys = read_phys(f)
            @test phys !== nothing
            ppux, ppuy, unit = phys
            @test unit == 1                       # 1 == meters
            @test nm_from_ppu(ppux) ≈ info.pixel_size_nm rtol=1e-6
            @test nm_from_ppu(ppuy) ≈ info.pixel_size_nm rtol=1e-6
        end

        @testset "overlay save site" begin
            f = joinpath(dir, "overlay.png")
            (_, info) = render([smld, smld];
                               colors=[RGB(1.0, 0.0, 0.0), RGB(0.0, 1.0, 0.0)],
                               zoom=10, filename=f)

            @test isfile(f)
            phys = read_phys(f)
            @test phys !== nothing
            ppux, ppuy, unit = phys
            @test unit == 1
            @test nm_from_ppu(ppux) ≈ info.pixel_size_nm rtol=1e-6
        end

        @testset "in-memory render writes nothing" begin
            before = readdir(dir)
            (img, _) = render(smld; zoom=10)     # no filename
            @test img isa Matrix{RGB{Float64}}
            @test readdir(dir) == before          # no file appeared anywhere
        end

        @testset "scale is opt-in on save_image" begin
            (img, _) = render(smld; zoom=10)

            # No pixel_size_nm -> no pHYs chunk at all.
            bare = joinpath(dir, "bare.png")
            save_image(bare, img)
            @test read_phys(bare) === nothing

            # Explicit scale -> pHYs present, even for a direct caller that
            # never went through render() (the gap the kwarg exists to close).
            scaled = joinpath(dir, "scaled.png")
            save_image(scaled, img; pixel_size_nm=12.5)
            ppux, _, _ = read_phys(scaled)
            @test nm_from_ppu(ppux) ≈ 12.5 rtol=1e-6
        end

        @testset "anisotropic x/y scales stay independent" begin
            (img, _) = render(smld; zoom=10)
            f = joinpath(dir, "aniso.png")
            save_image(f, img; pixel_size_nm=(10.7, 21.4))

            ppux, ppuy, _ = read_phys(f)
            @test nm_from_ppu(ppux) ≈ 10.7 rtol=1e-6
            @test nm_from_ppu(ppuy) ≈ 21.4 rtol=1e-6
            @test ppux != ppuy
        end

        @testset "non-PNG saves the image without scale" begin
            (img, _) = render(smld; zoom=10)
            f = joinpath(dir, "nonpng.tif")
            # TIFF rejects the dpi kwarg; the image must still be written.
            @test_logs (:warn,) save_image(f, img; pixel_size_nm=10.0)
            @test isfile(f)
        end

        @testset "render does not warn on a non-PNG target" begin
            # render() must not nag about metadata the user never asked for:
            # it only offers the scale to formats that can hold it.
            f = joinpath(dir, "quiet.tif")
            @test_logs render(smld; zoom=2, filename=f)
            @test isfile(f)
            @test filesize(f) > 0
        end

        @testset "unrepresentable scale still writes the image" begin
            (img, _) = render(smld; zoom=10)

            # pHYs holds pixels-per-meter in a UInt32. Scales past either end
            # of that field must degrade to "no scale", never to a lost image.
            for bad in (0.2, 0.1, 1e-6,   # too fine: ppu overflows UInt32
                        2e9, 1e12)        # too coarse: ppu rounds to zero
                f = joinpath(dir, "unrep_$(bad).png")
                @test_logs (:warn,) save_image(f, img; pixel_size_nm=bad)
                @test isfile(f)
                @test filesize(f) > 0          # a real PNG, not a 0-byte stub
                @test read_phys(f) === nothing # and no misleading chunk
            end

            # Just inside the representable range still gets a real scale.
            f = joinpath(dir, "fine_ok.png")
            save_image(f, img; pixel_size_nm=0.25)
            ppux, _, _ = read_phys(f)
            @test nm_from_ppu(ppux) ≈ 0.25 rtol=1e-6
        end

        @testset "high zoom saves rather than throwing" begin
            # Regression: zoom past ~430 on a 100 nm camera drove pixel size
            # below the UInt32 pHYs floor and threw out of render(), costing
            # the caller both the image and the returned (img, info).
            for z in (400, 430, 1000)
                f = joinpath(dir, "zoom_$(z).png")
                (img, info) = render(smld; zoom=z, roi=(1:2, 1:2), filename=f)
                @test img isa Matrix{RGB{Float64}}
                @test info.pixel_size_nm > 0
                @test isfile(f)
                @test filesize(f) > 0
            end
        end

        @testset "non-finite scale is rejected" begin
            (img, _) = render(smld; zoom=10)
            f = joinpath(dir, "nonfinite.png")
            @test_throws AssertionError save_image(f, img; pixel_size_nm=Inf)
            @test_throws AssertionError save_image(f, img; pixel_size_nm=NaN)
        end

        @testset "non-positive scale is rejected" begin
            (img, _) = render(smld; zoom=10)
            f = joinpath(dir, "bad.png")
            @test_throws AssertionError save_image(f, img; pixel_size_nm=0.0)
            @test_throws AssertionError save_image(f, img; pixel_size_nm=-5.0)
            @test_throws AssertionError save_image(f, img; pixel_size_nm=(10.0, -1.0))
        end
    end

end
