module Hrse

struct CommentedElement
    element::Any
    comments::Vector{String}
end

include("Literals.jl")
include("Parser.jl")

function parseoptions(;integertypes = [Int64, BigInt], floattype = Float64, readcomments = false)
    return Parser.ParseOptions(integertypes, floattype, readcomments)
end

function readhrse(io::IO; options::Parser.ParseOptions=parseoptions())
    tokens = Parser.tokenize(io, options)
    parsetree = Parser.parsefile(tokens, options)
    if Parser.tokentype(Parser.peek(tokens)) != Parser.EOF
        throw(Parser.HrseSyntaxException("Unexpected token '$(Parser.tokentext(Parser.peek(tokens)))'", Parser.tokenline(Parser.peek(tokens)), Parser.tokenpos(Parser.peek(tokens))))
    end
    return Parser.translate(parsetree, options)
end

readhrse(s::String; options::Parser.ParseOptions=parseoptions()) = readhrse(IOBuffer(s), options=options)

end # module Hrse
