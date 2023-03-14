push!(LOAD_PATH,"../src/")

using Documenter
using Hrse

makedocs(
    sitename = "Hrse.jl",
    format = Documenter.HTML(),
    modules = [Hrse]
)

deploydocs(
    repo   = "github.com/lukebemish/Hrse.jl.git",
    target = "build",
    push_preview = true
)
