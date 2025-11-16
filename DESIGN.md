# SMLMRender.jl Design Document

## What is SMLM Rendering and Why This Package?

### Background: Single Molecule Localization Microscopy

Single Molecule Localization Microscopy (SMLM) is a super-resolution imaging technique that breaks the diffraction limit of conventional light microscopy. Techniques like PALM, STORM, and DNA-PAINT produce datasets containing millions of individual molecule localizations, each with:

- **Spatial coordinates** (x, y, z) with nanometer precision
- **Photon counts** representing brightness
- **Localization uncertainties** (σ_x, σ_y, σ_z)
- **Temporal information** (frame number)
- **Metadata** (track IDs, datasets, custom fields)

### The Rendering Challenge

Raw localization data is just a table of coordinates. To create meaningful images, we need to render these sparse point clouds into continuous 2D/3D representations. This is computationally intensive:

- **Scale**: Datasets with 1-100 million localizations
- **Resolution**: Images at 10-100× optical resolution (10-100 megapixels)
- **Real-time needs**: Interactive exploration requires <1s render times
- **Flexibility**: Color by any field (z-position, time, photons, uncertainty, custom metrics)

### Why Separate from SMLMVis.jl?

**Architectural Clarity:**
- SMLMVis.jl has accumulated rendering, visualization, analysis, and GUI code
- Rendering is a distinct concern that should be reusable
- Other packages (analysis, simulation) need rendering without full visualization stack

**Performance Focus:**
- Rendering is the performance bottleneck (GPU acceleration critical)
- Dedicated package allows aggressive optimization without breaking other features
- Easier to benchmark and profile in isolation

**Fresh Start:**
- Previous SMLMVis rendering had aspect ratio bugs, zoom restrictions, complex offset array management
- No backwards compatibility constraints allows clean, Julian design
- Opportunity to implement modern GPU-accelerated approaches from scratch

**Reusability:**
- SMLMData.jl → SMLMRender.jl → SMLMVis.jl pipeline
- SMLMMetrics.jl can use rendering for quality assessment
- Simulation packages can render ground truth
- Custom analysis workflows can generate figures programmatically

---

## Core Design Principles

### 1. Julian Design
- **Multiple dispatch** for `render()` interface
- **Type stability** for performance
- **Composability** through small, focused functions
- **Extensibility** via abstract types and traits
- **Immutability** where possible (rendering options)
- **Named tuples** for lightweight parameter passing

### 2. Performance First
- **GPU acceleration** as primary target (CPU fallback)
- **Multi-threading** for CPU path
- **Memory efficiency** through streaming/batching
- **Type stability** and specialization
- **Avoid allocations** in hot paths
- **Progressive rendering** for interactivity

### 3. Flexibility
- **Strategy pattern** for rendering algorithms
- **Field-based coloring** (any EmitterFit field)
- **Perceptual colormaps** from ColorSchemes.jl
- **Multiple output formats** (arrays, Images.jl types, RGB, normalized)
- **Physical and pixel coordinates** handled transparently

### 4. Extensibility for 3D
- **Type hierarchy** designed for 2D → 3D → volumetric → time series
- **Abstract render targets** (image, volume, point cloud, mesh)
- **Camera abstraction** for 3D viewpoints
- **Projection strategies** (orthographic, perspective, maximum intensity)

---

## Proposed Type Hierarchy

```julia
# ============================================================================
# Rendering Strategies (Algorithm Selection)
# ============================================================================

abstract type RenderingStrategy end

# 2D Rendering Strategies
abstract type Render2DStrategy <: RenderingStrategy end

struct HistogramRender <: Render2DStrategy
    # Fast binning, each pixel counts localizations
    # No sub-pixel accuracy, but very fast
end

struct GaussianRender <: Render2DStrategy
    n_sigmas::Float64          # How many σ to render (default: 3.0)
    use_localization_precision::Bool  # Use σ_x, σ_y or fixed sigma
    fixed_sigma::Union{Float64, Nothing}  # If not using localization precision
    normalization::Symbol      # :integral or :maximum
end

struct AdaptiveGaussianRender <: Render2DStrategy
    n_sigmas::Float64
    min_sigma::Float64         # Minimum blur (nm)
    density_radius::Float64    # Look around this radius for adaptive sigma
    normalization::Symbol
end

# Future: 3D Rendering Strategies
abstract type Render3DStrategy <: RenderingStrategy end

struct VolumetricRender <: Render3DStrategy
    # 3D Gaussian blobs in volume
    n_sigmas::Float64
    voxel_size::NTuple{3, Float64}  # (x, y, z) in nm
end

struct ProjectionRender <: Render3DStrategy
    # Project 3D → 2D with viewpoint
    projection::ProjectionType
    camera::Camera3D
    depth_coding::Bool         # Color by depth?
end

struct PointCloudRender <: Render3DStrategy
    # Keep as point cloud for 3D viewers (Makie)
    point_size::Float64
end

# ============================================================================
# Color Mapping
# ============================================================================

abstract type ColorMapping end

struct SingleColor <: ColorMapping
    # All localizations same color, vary intensity
end

struct FieldColorMapping <: ColorMapping
    field::Symbol              # Which field to color by (:z, :photons, :frame, etc.)
    colormap::Symbol           # ColorSchemes.jl colormap name
    range::Union{Tuple{Float64, Float64}, Symbol}  # Explicit or :auto
    clamp_percentiles::Union{Tuple{Float64, Float64}, Nothing}  # (0.01, 0.99)
end

struct CustomColorMapping <: ColorMapping
    # User provides function: emitter → RGB
    color_function::Function
end

# ============================================================================
# Contrast Enhancement
# ============================================================================

@enum ContrastMethod begin
    LinearContrast
    LogContrast
    SqrtContrast
    HistogramEqualization
    AdaptiveEqualization  # CLAHE-like
end

struct ContrastOptions
    method::ContrastMethod
    clip_percentile::Float64   # Clip before contrast (0.999 = clip top 0.1%)
    gamma::Float64             # For power-law adjustment (default: 1.0)
end

# ============================================================================
# Render Targets (What we're rendering to)
# ============================================================================

abstract type RenderTarget end

struct Image2DTarget <: RenderTarget
    width::Int
    height::Int
    pixel_size::Float64        # nm per pixel
    x_range::Tuple{Float64, Float64}  # Physical coordinates (μm)
    y_range::Tuple{Float64, Float64}
end

struct Volume3DTarget <: RenderTarget
    width::Int
    height::Int
    depth::Int
    voxel_size::NTuple{3, Float64}  # (x, y, z) nm per voxel
    x_range::Tuple{Float64, Float64}
    y_range::Tuple{Float64, Float64}
    z_range::Tuple{Float64, Float64}
end

# ============================================================================
# Camera (for 3D projections)
# ============================================================================

struct Camera3D
    position::NTuple{3, Float64}      # (x, y, z) in μm
    look_at::NTuple{3, Float64}       # Target point
    up_vector::NTuple{3, Float64}     # Up direction
    fov::Float64                       # Field of view (degrees) for perspective
end

@enum ProjectionType begin
    OrthographicProjection
    PerspectiveProjection
    MaximumIntensityProjection  # MIP
    AverageIntensityProjection
end

# ============================================================================
# Render Options (Comprehensive Configuration)
# ============================================================================

struct RenderOptions{S<:RenderingStrategy, C<:ColorMapping}
    strategy::S
    color_mapping::C
    contrast::Union{ContrastOptions, Nothing}
    backend::Symbol            # :cpu, :cuda, :metal, :auto
    output_type::Symbol        # :array, :image (Images.jl), :rgb
end

# ============================================================================
# Results
# ============================================================================

struct RenderResult2D{T}
    image::Matrix{T}           # Or RGB matrix
    target::Image2DTarget
    options::RenderOptions
    render_time::Float64       # Seconds
    n_localizations::Int       # How many were rendered
end

struct RenderResult3D{T}
    volume::Array{T, 3}        # Or 2D projection
    target::Union{Volume3DTarget, Image2DTarget}
    options::RenderOptions
    render_time::Float64
    n_localizations::Int
end
```

---

## Main Interface Design

### Simple 2D Rendering

```julia
using SMLMData, SMLMRender

# Load data
smld = load_smld("data.h5")

# Simplest: histogram render with automatic pixel size
img = render(smld)

# Specify zoom (pixels per camera pixel)
img = render(smld; zoom=20)

# Specify absolute pixel size
img = render(smld; pixel_size=10.0)  # 10 nm/pixel

# Gaussian render with fixed sigma
img = render(smld;
    strategy = GaussianRender(n_sigmas=3.0, use_localization_precision=false,
                             fixed_sigma=20.0, normalization=:integral))

# Gaussian render using localization precision (σ_x, σ_y from data)
img = render(smld;
    strategy = GaussianRender(n_sigmas=3.0, use_localization_precision=true,
                             fixed_sigma=nothing, normalization=:integral))
```

### Color Mapping

```julia
# Color by z-position with viridis colormap
img = render(smld;
    color_mapping = FieldColorMapping(:z, :viridis, :auto, (0.01, 0.99)))

# Color by photon count
img = render(smld;
    color_mapping = FieldColorMapping(:photons, :inferno, (100.0, 10000.0), nothing))

# Color by frame (time)
img = render(smld;
    color_mapping = FieldColorMapping(:frame, :twilight, :auto, (0.0, 1.0)))

# Color by uncertainty (quality metric)
img = render(smld;
    color_mapping = FieldColorMapping(:σ_x, :plasma, (5.0, 30.0), nothing))

# Custom coloring function
img = render(smld;
    color_mapping = CustomColorMapping(
        emitter -> emitter.photons > 5000 ? RGB(1,0,0) : RGB(0,1,0)
    ))
```

### Contrast Enhancement

```julia
# Logarithmic contrast for wide dynamic range
img = render(smld;
    contrast = ContrastOptions(LogContrast, 0.999, 1.0))

# Histogram equalization
img = render(smld;
    contrast = ContrastOptions(HistogramEqualization, 0.995, 1.0))

# Gamma adjustment
img = render(smld;
    contrast = ContrastOptions(LinearContrast, 0.999, 0.7))
```

### ROI Rendering

```julia
# Render specific region (physical coordinates in μm)
img = render(smld, x_range=(10.0, 20.0), y_range=(15.0, 25.0))

# Or filter first, then render
roi_smld = filter_roi(smld, 10.0:20.0, 15.0:25.0)
img = render(roi_smld)
```

### Explicit Pixel Edges (Maximum Control)

```julia
# Define exact pixel edges for non-uniform grids
x_edges = range(0.0, 50.0, length=1001)  # 1000 pixels
y_edges = range(0.0, 30.0, length=601)   # 600 pixels

img = render(smld, x_edges, y_edges)
```

### Backend Selection

```julia
# Automatic (use GPU if available)
img = render(smld; backend=:auto)

# Force CPU (multi-threaded)
img = render(smld; backend=:cpu)

# Use CUDA GPU
img = render(smld; backend=:cuda)

# Use Apple Metal GPU
img = render(smld; backend=:metal)
```

---

## Future 3D Rendering Interface

```julia
# Maximum intensity projection (MIP) with color by z
img = render(smld;
    strategy = ProjectionRender(
        MaximumIntensityProjection,
        Camera3D((0, 0, 10), (0, 0, 0), (0, 1, 0), 45.0),
        depth_coding = true
    ),
    color_mapping = FieldColorMapping(:z, :viridis, :auto, (0.01, 0.99)))

# Volumetric render (returns 3D array)
vol = render(smld;
    strategy = VolumetricRender(3.0, (10.0, 10.0, 20.0)))  # xyz voxel sizes in nm

# Point cloud for Makie visualization
cloud = render(smld;
    strategy = PointCloudRender(2.0))  # Returns Makie-compatible format

# Fly-through animation (future)
animation = render_flythrough(smld, camera_path, n_frames=100)
```

---

## Implementation Roadmap

### Phase 1: Core 2D Rendering (Initial Implementation)

**Goal:** Functional CPU-based 2D rendering with histogram and Gaussian strategies

1. **Type system** (types.jl)
   - Define all abstract types and core structs
   - RenderOptions, ContrastOptions, ColorMapping types
   - Image2DTarget

2. **Histogram rendering** (histogram.jl)
   - Simple binning algorithm
   - Multi-threaded accumulation
   - Field-based color mapping
   - Export `render()` for `HistogramRender`

3. **Gaussian rendering** (gaussian.jl)
   - Implement 2D Gaussian blob generation
   - Fixed sigma and adaptive sigma modes
   - Batch processing for memory efficiency
   - Multi-threaded patch generation and accumulation
   - Export `render()` for `GaussianRender`

4. **Color mapping** (color.jl)
   - FieldColorMapping implementation
   - Integration with ColorSchemes.jl
   - Perceptual colormaps (viridis, cividis, twilight, etc.)
   - Quantile-based range calculation
   - Custom color functions

5. **Contrast enhancement** (contrast.jl)
   - Linear, log, sqrt contrast
   - Percentile clipping
   - Gamma correction
   - Histogram equalization

6. **Main interface** (interface.jl)
   - `render()` dispatch on different argument types
   - Convenience constructors for RenderOptions
   - Keyword argument sugar
   - ROI handling

7. **Utilities** (utils.jl)
   - Coordinate transformations (physical ↔ pixel)
   - Automatic target generation from SMLD bounds
   - Memory estimation
   - Progress reporting

### Phase 2: GPU Acceleration

**Goal:** 10-100× speedup for large datasets using GPUs

1. **Backend abstraction** (backends/abstract.jl)
   - Abstract backend interface
   - Backend capability detection
   - Automatic fallback logic

2. **CUDA backend** (backends/cuda.jl)
   - CUDA.jl integration
   - Kernel for Gaussian blob rendering
   - Atomic operations for accumulation
   - Efficient memory transfers
   - Batch processing on GPU

3. **KernelAbstractions backend** (backends/kernelabstract.jl)
   - Write kernels using KernelAbstractions.jl
   - Portable across CUDA, ROCm, Metal, oneAPI
   - Single kernel implementation for all GPUs
   - Performance tuning per backend

4. **CPU backend optimization** (backends/cpu.jl)
   - Refactor existing CPU code
   - SIMD optimizations
   - LoopVectorization.jl for Gaussian evaluation
   - Cache-friendly access patterns

### Phase 3: 3D Rendering

**Goal:** Volumetric and projection-based 3D rendering

1. **3D Gaussian rendering** (gaussian3d.jl)
   - 3D Gaussian blob generation
   - Volumetric accumulation
   - Efficient z-slicing

2. **Projection rendering** (projection.jl)
   - Camera transformations
   - Orthographic projection
   - Perspective projection
   - Maximum intensity projection (MIP)
   - Average intensity projection

3. **Depth-based coloring** (color3d.jl)
   - Layer-based color accumulation (SMLMVis approach)
   - Depth-weighted blending
   - Per-slice colormaps

4. **Interactive 3D** (interactive.jl)
   - Integration with Makie.jl (GLMakie, WGLMakie)
   - Real-time camera control
   - Progressive rendering (render while moving, refine when still)
   - Level-of-detail (LOD) rendering

### Phase 4: Advanced Features

**Goal:** Production-ready features for publications and analysis

1. **Adaptive rendering** (adaptive.jl)
   - Density-based sigma selection
   - Jittered rendering to reduce aliasing
   - Multi-scale rendering

2. **Fly-through animations** (animation.jl)
   - Camera path specification (splines, waypoints)
   - Frame generation
   - Video export (via VideoIO.jl)
   - Smooth interpolation

3. **Tiled rendering** (tiling.jl)
   - Render arbitrarily large images in tiles
   - Memory-efficient for gigapixel images
   - Parallel tile processing
   - Seamless stitching

4. **Quality metrics** (quality.jl)
   - Fourier Ring Correlation (FRC) on renders
   - Effective resolution estimation
   - Artifact detection

---

## Recommended Perceptual Colormaps

Based on research, we'll include these scientifically-validated perceptual colormaps:

**Sequential (for single-valued fields like z, photons):**
- `:viridis` - Perceptually uniform, colorblind-safe (default)
- `:cividis` - Optimized for colorblind viewers
- `:inferno`, `:magma`, `:plasma` - Matplotlib perceptual maps
- `:turbo` - Google's improved rainbow replacement

**Diverging (for fields with meaningful center, like drift):**
- `:RdBu` - Red-blue (ColorBrewer)
- `:seismic` - Blue-white-red
- `:twilight` - Cyclic colormap for angular data

**Cyclic (for periodic fields like angles):**
- `:twilight` - Perceptually uniform cyclic
- `:phase` - For phase data

**From PerceptualColourMaps.jl (Peter Kovesi):**
- `:linear_kryw_5_100_c67_n256` - Excellent perceptual uniformity
- `:diverging_bwr_40_95_c42_n256` - Diverging with uniform contrast

We'll default to `:viridis` for 2D intensity and depth-based 3D coloring.

---

## Dependencies

### Core
```julia
SMLMData         # Data structures (EmitterFit, BasicSMLD)
ColorSchemes     # Perceptual colormaps
Images           # Output as Image types (optional)
StaticArrays     # Fast fixed-size arrays for coordinates
```

### Performance
```julia
ThreadsX         # Parallel processing utilities
FLoops           # Fast multi-threaded loops
LoopVectorization # SIMD optimization
```

### GPU (Optional, loaded via Requires.jl or extensions)
```julia
CUDA             # NVIDIA GPU support
KernelAbstractions # Portable GPU kernels
Adapt            # Array type adaptation
```

### Visualization (Optional)
```julia
Makie            # For interactive 3D rendering
VideoIO          # For animation export
```

---

## Package Structure

```
SMLMRender.jl/
├── src/
│   ├── SMLMRender.jl          # Main module
│   ├── types.jl               # Type definitions
│   ├── interface.jl           # render() dispatch
│   ├── utils.jl               # Utilities
│   │
│   ├── render/
│   │   ├── histogram.jl       # Histogram rendering
│   │   ├── gaussian.jl        # 2D Gaussian rendering
│   │   ├── gaussian3d.jl      # 3D Gaussian (Phase 3)
│   │   └── projection.jl      # 3D projection (Phase 3)
│   │
│   ├── color/
│   │   ├── mapping.jl         # Color mapping logic
│   │   ├── contrast.jl        # Contrast enhancement
│   │   └── schemes.jl         # Colormap selection and validation
│   │
│   ├── backends/
│   │   ├── abstract.jl        # Backend interface
│   │   ├── cpu.jl             # CPU multi-threaded
│   │   ├── cuda.jl            # CUDA (Phase 2)
│   │   └── kernelabstract.jl  # KernelAbstractions (Phase 2)
│   │
│   └── extensions/            # Julia 1.9+ package extensions
│       ├── MakieExt.jl        # Makie integration
│       └── VideoExt.jl        # Video export
│
├── test/
│   ├── runtests.jl
│   ├── test_histogram.jl
│   ├── test_gaussian.jl
│   ├── test_color.jl
│   ├── test_backends.jl
│   └── benchmarks.jl
│
├── docs/
│   ├── make.jl
│   └── src/
│       ├── index.md
│       ├── quickstart.md
│       ├── rendering_strategies.md
│       ├── colormaps.md
│       ├── gpu_acceleration.md
│       └── api.md
│
├── examples/
│   ├── basic_rendering.jl
│   ├── color_by_field.jl
│   ├── 3d_projection.jl      # Phase 3
│   └── flythrough.jl          # Phase 4
│
└── Project.toml
```

---

## Why This Design is Julian

1. **Multiple Dispatch**: The `render()` function dispatches on:
   - Type of `strategy` (Histogram vs Gaussian vs Projection)
   - Type of `color_mapping` (SingleColor vs FieldColor vs Custom)
   - Type of input (BasicSMLD, filtered SMLD, custom emitter vectors)

2. **Type Stability**: All types are concrete and parameterized for performance

3. **Composability**: Small types (ContrastOptions, ColorMapping) compose into larger ones (RenderOptions)

4. **Extensibility**: Users can define new rendering strategies by subtyping `RenderingStrategy`

5. **No Magic**: Everything is explicit - no hidden global state, no mutable singletons

6. **Generic Programming**: Works with any `AbstractEmitter` type, not just SMLMData types

7. **Minimal Interface**: Core is just `render()` with clear argument types

8. **Package Extensions**: GPU backends and visualization optional (Julia 1.9+)

---

## Performance Targets

Based on typical SMLM datasets:

| Dataset Size | Image Size | Histogram (CPU) | Gaussian (CPU) | Gaussian (GPU) |
|-------------|------------|-----------------|----------------|----------------|
| 100K locs   | 1K × 1K    | <10 ms         | <100 ms        | <10 ms        |
| 1M locs     | 2K × 2K    | <50 ms         | <1 s           | <50 ms        |
| 10M locs    | 5K × 5K    | <500 ms        | <10 s          | <500 ms       |
| 100M locs   | 10K × 10K  | <5 s           | <100 s         | <5 s          |

**Goal**: Interactive rendering (<100ms) for typical datasets (1-10M localizations, 2K×2K images) using GPU acceleration.

---

## Summary

SMLMRender.jl will be a focused, high-performance package for rendering SMLM localization data into 2D images and 3D volumes. By separating rendering from visualization, we create a reusable component with:

- **Clean architecture** based on strategy pattern and multiple dispatch
- **Flexible coloring** by any EmitterFit field with perceptual colormaps
- **Performance** through GPU acceleration and multi-threading
- **Extensibility** for future 3D rendering and advanced features
- **Julian design** leveraging type system and composability

The phased implementation ensures we deliver value quickly (Phase 1) while building toward advanced features (Phases 2-4).

Next steps: Implement Phase 1 (Core 2D Rendering) with histogram and Gaussian rendering, field-based coloring, and the main `render()` interface.
