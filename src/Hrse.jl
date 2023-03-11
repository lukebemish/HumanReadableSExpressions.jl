module Hrse

struct CommentedElement
    element::Any
    comments::Vector{String}
end

include("Literals.jl")
include("Parser.jl")

"""
    parseoptions(kwargs...)

Returns an object storing options for parsing HRSE files.

# Arguments
 - `integertypes = [Int64, BigInt]`: A list of signed integer types to try parsing integers as. The first type that can 
    represent the integer will be used..
 - `floattype = Float64`: The floating point type to parse floating point numbers as.
 - `readcomments = false`: Whether to read comments and store them in `CommentedElement` objects; if false, comments are
    ignored
"""
parseoptions(;
    integertypes = [Int64, BigInt],
    floattype::Type{<:AbstractFloat} = Float64,
    readcomments::Bool = false) = Parser.ParseOptions(
        integertypes,
        floattype,
        readcomments)

"""
    readhrse(hrse::IO; options=parseoptions())
    readhrse(hrse::String; options=parseoptions())

Reads an HRSE file from the given IO object or string and returns the corresponding Julia object. The `options` argument
is an object returned by `parseoptions` and can be used to configure the parser. Lists will be read as vectors, pairs as a
Pair, symbols and strings as a String, and numeric types as the corresponding Julia type defined in the parser options.

# Examples
```jldoctest
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
function readhrse(hrse::IO; options::Parser.ParseOptions=parseoptions())
    tokens = Parser.tokenize(hrse, options)
    parsetree = Parser.parsefile(tokens, options)
    if Parser.tokentype(Parser.peek(tokens)) != Parser.EOF
        throw(Parser.HrseSyntaxException("Unexpected token '$(Parser.tokentext(Parser.peek(tokens)))'", Parser.tokenline(Parser.peek(tokens)), Parser.tokenpos(Parser.peek(tokens))))
    end
    return Parser.translate(parsetree, options)
end

readhrse(hrse::String; options::Parser.ParseOptions=parseoptions()) = readhrse(IOBuffer(hrse), options=options)

end # module Hrse
