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
            elapsed_ns = UInt64(1_000_000),
            backend = :cpu,
            device_id = 0,
            n_emitters_rendered = 100,
            output_size = (512, 512),
            pixel_size_nm = 10.0,
            strategy = :gaussian,
            color_mode = :intensity,
            field_range = nothing
        )

        @test info.elapsed_ns == UInt64(1_000_000)
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
            elapsed_ns = UInt64(500_000),
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
        @test info.elapsed_ns > 0
        @test info.elapsed_ns < 60_000_000_000  # Less than 60 seconds
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

end
