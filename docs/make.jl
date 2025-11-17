using Documenter
using SMLMRender

DocMeta.setdocmeta!(SMLMRender, :DocTestSetup, :(using SMLMRender); recursive=true)

makedocs(;
    modules=[SMLMRender],
    authors="klidke@unm.edu",
    repo="https://github.com/JuliaSMLM/SMLMRender.jl/blob/{commit}{path}#{line}",
    sitename="SMLMRender.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaSMLM.github.io/SMLMRender.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Examples" => "examples.md",
        "API Reference" => "api.md",
    ],
    doctest = true,
    checkdocs = :exports,  # Only check that exported items are documented
)

deploydocs(;
    repo="github.com/JuliaSMLM/SMLMRender.jl",
    devbranch="main",
)
