push!(LOAD_PATH,"../src/")

using Documenter
using HumanReadableSExpressions

makedocs(
    sitename = "HumanReadableSExpressions.jl",
    format = Documenter.HTML(),
    modules = [HumanReadableSExpressions]
)

deploydocs(
    repo   = "github.com/lukebemish/HumanReadableSExpressions.jl.git",
    target = "build",
    push_preview = true
)
