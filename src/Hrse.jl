module Hrse

export CommentedElement

struct CommentedElement
    element::Any
    comments::Vector{String}
end

include("Literals.jl")
include("Parser.jl")

read = Parser.read

end # module Hrse
