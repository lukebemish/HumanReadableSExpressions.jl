module Hrse

"""
An extension to HRSE; axpects a "dense" HRSE file with a single root-level element instead of a list of elements.
"""
const DENSE = :DENSE

"""
    ReadOptions(kwargs...)

Stores options for parsing HRSE files.

# Arguments
 - `integertypes = [Int64, BigInt]`: A list of signed integer types to try parsing integers as. The first type that can 
    represent the integer will be used..
 - `floattype = Float64`: The floating point type to parse floating point numbers as.
 - `readcomments = false`: Whether to read comments and store them in `CommentedElement` objects; if false, comments are
    ignored
 - `extensions`: A collection of symbols representing extensions to HRSE.
"""
struct ReadOptions
    integertypes
    floattype::Type{<:AbstractFloat}
    readcomments::Bool
    extensions
    ReadOptions(;
    integertypes = [Int64, BigInt],
    floattype::Type{<:AbstractFloat} = Float64,
    readcomments::Bool = false,
    extensions=[]) = new(
        integertypes,
        floattype,
        readcomments,
        extensions)
end

@enum PairMode CONDENSED_MODE=1 DOT_MODE=2 EQUALS_MODE=3 COLON_MODE=4

struct PrinterOptions
    indent::String
    comments::Bool
    extensions
    pairmode::PairMode
    inlineprimitives::Integer
    PrinterOptions(;
    indent::String="  ",
    comments::Bool=true,
    extensions=[],
    pairmode::PairMode=COLON_MODE,
    inlineprimitives::Integer=20) = new(
        indent,
        comments,
        extensions,
        pairmode,
        inlineprimitives)
end

struct CommentedElement
    element::Any
    comments::Vector{String}
end

include("literals.jl")
include("parser.jl")
include("printer.jl")


"""
    readhrse(hrse::IO; options=ReadOptions())
    readhrse(hrse::String; options=ReadOptions())

Reads an HRSE file from the given IO object or string and returns the corresponding Julia object. The `options` argument can
be used to configure the parser. Lists will be read as vectors, pairs as a Pair, symbols and strings as a String, and 
numeric types as the corresponding Julia type defined in the parser options.

# Examples
```jldoctest
julia> import Hrse

julia> hrse = \"\"\"
       alpha:
           1 2 3 4
           5 6
           7 8 9
       beta: (0 . 3)
       gamma:
           a: 1
           b: 2
           c: "c"
       \"\"\";

julia> Hrse.readhrse(hrse)
3-element Vector{Pair{String}}:
 "alpha" => [[1, 2, 3, 4], [5, 6], [7, 8, 9]]
  "beta" => (0 => 3)
 "gamma" => Pair{String}["a" => 1, "b" => 2, "c" => "c"]
```
"""
function readhrse(hrse::IO; options::ReadOptions=ReadOptions())
    dense = DENSE in options.extensions
    tokens = Parser.Tokens(Parser.tokenize(hrse, options), nothing, [])
    parsetree = Parser.parsefile(tokens, options)
    if Parser.tokentype(Parser.peek(tokens)) != Parser.EOF
        throw(Parser.HrseSyntaxException("Unexpected token '$(Parser.tokentext(Parser.peek(tokens)))'", Parser.tokenline(Parser.peek(tokens)), Parser.tokenpos(Parser.peek(tokens))))
    end
    translated = Parser.translate(parsetree, options)
    if (dense && length(translated) != 1)
        throw(Parser.HrseSyntaxException("Expected a single root-level element in dense mode", Parser.tokenline(Parser.peek(tokens)), Parser.tokenpos(Parser.peek(tokens))))
    end
    return dense ? translated[1] : translated
end

readhrse(hrse::String; options::ReadOptions=ReadOptions()) = readhrse(IOBuffer(hrse), options=options)

function writehrse(io::IO, obj, options::PrinterOptions)
    toprint = (DENSE in options.extensions) ? [obj] : obj
    if options.pairmode == CONDENSED_MODE
        Printer.condensed(io, toprint, options)
    else
        Printer.pretty(io, toprint, options, 0, true; root=true)
    end
end

writehrse(obj, options::PrinterOptions) = writehrse(stdout, obj, options)

ashrse(obj, options::PrinterOptions) = begin
    io = IOBuffer()
    writehrse(io, obj, options)
    return String(take!(io))
end

end # module Hrse
