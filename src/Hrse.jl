module Hrse

import StructTypes

"""
An extension to HRSE's syntax that affects parsing and/or printing.

See also [`DENSE`](@ref).
"""
@enum Extension DENSE=1

"""
An extension to HRSE; axpects a "dense" HRSE file with a single root-level element instead of a list of elements.

See also [`Extension`](@ref).
"""
DENSE;

"""
    ReadOptions(kwargs...)

Stores options for parsing HRSE files.

# Arguments
 - `integertypes = [Int64, BigInt]`: A list of signed integer types to try parsing integers as. The first type that can 
    represent the integer will be used.
 - `floattype = Float64`: The floating point type to parse floating point numbers as.
 - `readcomments = false`: Whether to read comments and store them in `CommentedElement` objects; if false, comments are
    ignored.
 - `extensions`: A collection of [`Extension`](@ref)s to HRSE.

See also [`readhrse`](@ref).
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

"""
A flag that decides how pairs are displayed while printing a HRSE structure.

See also [`CONDENSED_MODE`](@ref), [`DOT_MODE`](@ref), [`EQUALS_MODE`](@ref), [`COLON_MODE`](@ref).
"""
@enum PairMode CONDENSED_MODE=1 DOT_MODE=2 EQUALS_MODE=3 COLON_MODE=4

"""
A pair printing mode; pairs should all be condensed to a single line using classic s-expressions, eleminating as many spaces
as possible.

See also [`PairMode`](@ref).
"""
CONDENSED_MODE;

"""
A pair printing mode; pairs should all be displayed using classic s-expressions with dot-deliminated pairs, using
indentation to show nesting.

See also [`PairMode`](@ref).
"""
DOT_MODE;

"""
A pair printing mode; pairs should all be displayed using equals-sign-deliminated pairs with implied parentheses, using
indentation to show nesting.

See also [`PairMode`](@ref).
"""
EQUALS_MODE;

"""
A pair printing mode; pairs should all be displayed using colon-deliminated pairs with implied parentheses, using
indentation to show nesting and avoiding parentheses around lists as possible.

See also [`PairMode`](@ref).
"""
COLON_MODE;

"""
    PrinterOptions(kwargs...)

Stores options for printing HRSE structures to text.

# Arguments
 - `indent = "  "`: The string to use for indentation.
 - `comments = true`: Whether to print comments from `CommentedElement` objects; if false, comments are ignored.
 - `extensions`: A collection of [`Extension`](@ref)s to HRSE.
 - `pairmode = COLON_MODE`: The [`PairMode`](@ref) to use when printing pairs.
 - `inlineprimitives = 20`: The maximum string length of a list of primitives to print on a single line instead of adding
    a new indentation level.
 - `trailingnewline = true`: Whether to print a trailing newline at the end of the file.

See also [`writehrse`](@ref), [`ashrse`](@ref).
"""
struct PrinterOptions
    indent::String
    comments::Bool
    extensions
    pairmode::PairMode
    inlineprimitives::Integer
    trailingnewline::Bool
    PrinterOptions(;
    indent::String="  ",
    comments::Bool=true,
    extensions=[],
    trailingnewline::Bool=true,
    pairmode::PairMode=COLON_MODE,
    inlineprimitives::Integer=20) = new(
        indent,
        comments,
        extensions,
        pairmode,
        inlineprimitives,
        trailingnewline)
end

"""
    CommentedElement(element, comments)

Wraps an element with a list of comments which directly precede it attached to it.
"""
struct CommentedElement
    element::Any
    comments::Vector{String}
end

include("literals.jl")
include("parser.jl")
include("structures.jl")
include("printer.jl")


"""
    readhrse(hrse::IO; options=ReadOptions(); type=nothing)
    readhrse(hrse::String; options=ReadOptions(); type=nothing)

Reads an HRSE file from the given IO object or string and returns the corresponding Julia object. The `options` argument can
be used to configure the parser. Lists will be read as vectors, pairs as a Pair, symbols and strings as a String, and 
numeric types as the corresponding Julia type defined in the parser options. If `type` is given, the result will be parsed
as the given type using its StructTypes.StructType.

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

See also [`ReadOptions`](@ref).
"""
function readhrse(hrse::IO; options::ReadOptions=ReadOptions(), type::Union{Type, Nothing}=nothing)
    dense = DENSE in options.extensions
    tokens = Parser.Tokens(Parser.tokenize(hrse, options), nothing, [])
    parsetree = Parser.parsefile(tokens, options)
    # discard trailing comments
    Parser.parsecomments(tokens, options)
    Parser.stripindent(tokens)
    if Parser.tokentype(Parser.peek(tokens)) != Parser.EOF
        throw(Parser.HrseSyntaxException("Unexpected token '$(Parser.tokentext(Parser.peek(tokens)))'", Parser.tokenline(Parser.peek(tokens)), Parser.tokenpos(Parser.peek(tokens))))
    end
    translated = Parser.translate(parsetree, options)
    if (dense && length(translated) != 1)
        throw(Parser.HrseSyntaxException("Expected a single root-level element in dense mode", Parser.tokenline(Parser.peek(tokens)), Parser.tokenpos(Parser.peek(tokens))))
    end
    obj = dense ? translated[1] : translated
    if type !== nothing
        return Structures.deserialize(StructTypes.StructType(type), obj, type, options)
    end
    return obj
end

readhrse(hrse::String; options::ReadOptions=ReadOptions(), type::Union{Type, Nothing}=nothing) = readhrse(IOBuffer(hrse), options=options, type=type)

"""
    writehrse(io::IO, obj, options::PrinterOptions)
    writehrse(obj, options::PrinterOptions)

Writes the given Julia object to the given IO object as a HRSE file. The `options` argument can be used to configure the
behavior of the printer. If no IO object is given, the output is written to `stdout`. Arbitrary objects are serialized
using their StructTypes.StructType.

# Examples
```jldoctest
julia> import Hrse

julia> hrse = [
           :alpha => [
               [1, 2, 3, 4],
               [5, 6],
               [7, 8, 9]
           ],
           :beta => (0 => 3),
           :gamma => [
               :a => 1
               :b => 2
               :c => :c
           ]
       ];

julia> Hrse.writehrse(hrse, Hrse.PrinterOptions())
alpha: 
  1 2 3 4
  5 6
  7 8 9
beta: 0: 3
gamma: 
  a: 1
  b: 2
  c: c
```

See also [`PrinterOptions`](@ref).
"""
function writehrse(io::IO, obj, options::PrinterOptions)
    toprint = (DENSE in options.extensions) ? [obj] : obj
    if options.pairmode == CONDENSED_MODE
        Printer.condensed(io, toprint, options)
    else
        Printer.pretty(io, toprint, options, 0, true; root=true)
        if options.trailingnewline
            println(io)
        end
    end
end

writehrse(obj, options::PrinterOptions) = writehrse(stdout, obj, options)

"""
    ashrse(obj, options::PrinterOptions)

Returns the given Julia object as a string containing a HRSE file. The `options` argument can be used to configure the
behavior of the printer.

See also [`writehrse`](@ref), [`PrinterOptions`](@ref).
"""
ashrse(obj, options::PrinterOptions) = begin
    io = IOBuffer()
    writehrse(io, obj, options)
    return String(take!(io))
end

end # module Hrse
