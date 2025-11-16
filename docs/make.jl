using SMLMRender
using Documenter

DocMeta.setdocmeta!(SMLMRender, :DocTestSetup, :(using SMLMRender); recursive=true)

makedocs(;
    modules=[SMLMRender],
    authors="klidke@unm.edu",
    sitename="SMLMRender.jl",
    format=Documenter.HTML(;
        canonical="https://JuliaSMLM.github.io/SMLMRender.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaSMLM/SMLMRender.jl",
    devbranch="main",
)
