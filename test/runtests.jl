using SMLMRender
using SMLMData
using Colors
using Test

# Create test data
function make_test_smld()
    n = 100
    emitters = [
        Emitter2DFit(
            rand() * 10.0,      # x (μm)
            rand() * 10.0,      # y (μm)
            1000.0 + rand() * 500.0,  # photons
            10.0,               # bg
            20.0 + rand() * 10.0,  # σ_x (nm)
            20.0 + rand() * 10.0,  # σ_y (nm)
            50.0,               # σ_photons
            2.0,                # σ_bg
            rand(1:100),        # frame
            1,                  # dataset
            0,                  # track_id
            i                   # id
        ) for i in 1:n
    ]
    camera = IdealCamera(128, 128, 100.0)  # 128x128 pixels, 100nm pixel size
    return BasicSMLD(emitters, camera, 100, 1)  # n_frames, n_datasets
end

@testset "SMLMRender.jl" begin

    @testset "Tuple return pattern" begin
        smld = make_test_smld()

        @testset "Basic tuple unpacking" begin
            (image, info) = render(smld, zoom=10)

            @test image isa Matrix{RGB{Float64}}
            @test info isa RenderInfo
        end

        @testset "RenderInfo fields - common ecosystem fields" begin
            (image, info) = render(smld, zoom=10)

            # elapsed_ns is reasonable (> 0, < 60s worth)
            @test info.elapsed_ns > 0
            @test info.elapsed_ns < 60_000_000_000  # 60 seconds in ns

            # backend for CPU rendering
            @test info.backend == :cpu

            # device_id for CPU
            @test info.device_id == 0
        end

        @testset "RenderInfo fields - render-specific" begin
            smld = make_test_smld()
            (image, info) = render(smld, zoom=10)

            # n_emitters_rendered matches input
            @test info.n_emitters_rendered == length(smld.emitters)

            # output_size matches image dimensions (height, width)
            @test info.output_size == size(image)

            # pixel_size_nm is positive
            @test info.pixel_size_nm > 0
        end

        @testset "Strategy symbol" begin
            smld = make_test_smld()

            # Gaussian (default)
            (_, info) = render(smld, zoom=10)
            @test info.strategy == :gaussian

            # Histogram
            (_, info) = render(smld, zoom=10, strategy=HistogramRender())
            @test info.strategy == :histogram

            # Circle
            (_, info) = render(smld, zoom=10, strategy=CircleRender())
            @test info.strategy == :circle
        end

        @testset "Color mode symbol" begin
            smld = make_test_smld()

            # Intensity (default with colormap)
            (_, info) = render(smld, zoom=10, colormap=:inferno)
            @test info.color_mode == :intensity

            # Field coloring
            (_, info) = render(smld, zoom=10, color_by=:frame)
            @test info.color_mode == :field

            # Manual color
            (_, info) = render(smld, zoom=10, color=RGB(1.0, 0.0, 0.0))
            @test info.color_mode == :manual
        end

        @testset "Field range populated for field coloring" begin
            smld = make_test_smld()

            # No field range for intensity mode
            (_, info) = render(smld, zoom=10, colormap=:inferno)
            @test info.field_range === nothing

            # Field range populated for field coloring
            (_, info) = render(smld, zoom=10, color_by=:frame)
            @test info.field_range !== nothing
            @test info.field_range isa Tuple{Float64, Float64}
            @test info.field_range[1] < info.field_range[2]
        end

        @testset "Discard info pattern" begin
            smld = make_test_smld()

            # Just get the image
            img, _ = render(smld, zoom=10)
            @test img isa Matrix{RGB{Float64}}
        end
    end

    @testset "Multi-channel overlay tuple pattern" begin
        smld1 = make_test_smld()
        smld2 = make_test_smld()

        (image, info) = render([smld1, smld2],
                               colors=[RGB(1.0, 0.0, 0.0), RGB(0.0, 1.0, 0.0)],
                               zoom=10)

        @test image isa Matrix{RGB{Float64}}
        @test info isa RenderInfo

        # Total emitters from both datasets
        @test info.n_emitters_rendered == length(smld1.emitters) + length(smld2.emitters)

        # Overlay uses manual color mode
        @test info.color_mode == :manual
    end

end
