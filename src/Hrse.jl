module Hrse

"""
    ParseOptions(kwargs...)

Stores options for parsing HRSE files.

# Arguments
 - `integertypes = [Int64, BigInt]`: A list of signed integer types to try parsing integers as. The first type that can 
    represent the integer will be used..
 - `floattype = Float64`: The floating point type to parse floating point numbers as.
 - `readcomments = false`: Whether to read comments and store them in `CommentedElement` objects; if false, comments are
    ignored
 - `dense = false`: Expects a "dense" HRSE file with a single root-level element instead of a list of elements.
"""
struct ParseOptions
    integertypes
    floattype
    readcomments
    dense
    ParseOptions(;
    integertypes = [Int64, BigInt],
    floattype::Type{<:AbstractFloat} = Float64,
    readcomments::Bool = false,
    dense::Bool = false) = new(
        integertypes,
        floattype,
        readcomments,
        dense)
end

abstract type PrinterOptions end

struct PrintCondensed <: PrinterOptions end

struct PrintPretty <: PrinterOptions
    indent::Integer
    preferparens::Bool
    comments::Bool
    PrintPretty(; indent::Integer=2, preferparens::Bool=false, comments::Bool) = new(indent, preferparens, bomments)
end


struct CommentedElement
    element::Any
    comments::Vector{String}
end

include("literals.jl")
include("parser.jl")
include("printer.jl")


"""
    readhrse(hrse::IO; options=ParseOptions())
    readhrse(hrse::String; options=ParseOptions())

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
function readhrse(hrse::IO; options::ParseOptions=ParseOptions())
    tokens = Parser.tokenize(hrse, options)
    parsetree = Parser.parsefile(tokens, options)
    if Parser.tokentype(Parser.peek(tokens)) != Parser.EOF
        throw(Parser.HrseSyntaxException("Unexpected token '$(Parser.tokentext(Parser.peek(tokens)))'", Parser.tokenline(Parser.peek(tokens)), Parser.tokenpos(Parser.peek(tokens))))
    end
    translated = Parser.translate(parsetree, options)
    if (options.dense && length(translated) != 1)
        throw(Parser.HrseSyntaxException("Expected a single root-level element in dense mode", Parser.tokenline(Parser.peek(tokens)), Parser.tokenpos(Parser.peek(tokens))))
    end
    return options.dense ? translated[1] : translated
end

readhrse(hrse::String; options::ParseOptions=ParseOptions()) = readhrse(IOBuffer(hrse), options=options)

writehrse(io::IO, obj, options::PrintCondensed) = Printer.dense(io, obj)

writehrse(obj, options::PrinterOptions) = writehrse(stdout, obj, options)

hrse(obj, options::PrinterOptions) = begin
    io = IOBuffer()
    writehrse(io, obj, options)
    return String(take!(io))
end

end # module Hrse
