module Printer

import ..HumanReadableSExpressions
import ..HumanReadableSExpressions: HrsePrintOptions
import ..Literals
import ..Structures
import StructTypes: StructType
import Base.Unicode

isprimitive(obj) = false
isprimitive(::Integer) = true
isprimitive(::AbstractFloat) = true
isprimitive(::Bool) = true
isprimitive(::Symbol) = true
isprimitive(::AbstractString) = true

function pretty(io::IO, obj::AbstractVector, options::HrsePrintOptions, indent::Integer, imode::Bool; kwargs...)
    prettyiter(io, obj, options, indent, imode; kwargs...)
end

function prettyiter(io::IO, obj, options::HrsePrintOptions, indent::Integer, imode::Bool; noparenprimitive=false, root=false, kwargs...)
    if all(isprimitive(i) for i in obj)
        values = [begin
            i = IOBuffer()
            pretty(i, j, options, indent, imode)
            String(take!(i))
        end for j in obj]
        if length(values) == 0 || sum(length.(values)) + length(values) - 1 <= options.inlineprimitives
            if !noparenprimitive || length(obj) <= 1
                print(io, '(')
            end
            print(io, join(values, ' '))
            if !noparenprimitive || length(obj) <= 1
                print(io, ')')
            end
            return
        else
            if !imode
                print(io, '(')
            end
            first = true
            for i in values
                if !root || !first
                    println(io)
                    print(io, options.indent^(indent))
                else
                    first = false
                end
                print(io, i)
            end
        end
    else
        if !imode
            print(io, '(')
        end
        first = true
        for i in obj
            if !root || !first
                println(io)
                print(io, options.indent^(indent))
            else
                first = false
            end
            pretty(io, i, options, indent+1, false; noparenprimitive=imode)
        end
    end
    if !imode
        println(io)
        print(io, options.indent^(indent-1), ')')
    end
end

function pretty(io::IO, obj::Pair, options::HrsePrintOptions, indent::Integer, imode::Bool; forcegroup=false, kwargs...)
    if options.pairmode == HumanReadableSExpressions.DOT_MODE || forcegroup
        print(io, '(')
        pretty(io, obj.first, options, indent, false)
        print(io, " . ")
        pretty(io, obj.second, options, indent, false)
        print(io, ')')
    elseif options.pairmode == HumanReadableSExpressions.EQUALS_MODE
        pretty(io, obj.first, options, indent, false; forcegroup=true)
        print(io, " = ")
        pretty(io, obj.second, options, indent, false)
    elseif options.pairmode == HumanReadableSExpressions.COLON_MODE
        pretty(io, obj.first, options, indent, false; forcegroup=true)
        print(io, ": ")
        pretty(io, obj.second, options, indent, true; allownewlinecomments=false)
    end
end

pretty(io::IO, obj::AbstractDict, options::HrsePrintOptions, indent::Integer, imode::Bool; kwargs...) = prettyiter(io, obj, options, indent, imode; kwargs...)

pretty(io::IO, obj::Symbol, options::HrsePrintOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)
pretty(io::IO, obj::AbstractString, options::HrsePrintOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)
pretty(io::IO, obj::Integer, options::HrsePrintOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)
pretty(io::IO, obj::AbstractFloat, options::HrsePrintOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)
pretty(io::IO, obj::Bool, options::HrsePrintOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)

function pretty(io::IO, obj::T, options::HrsePrintOptions, indent::Integer, imode::Bool; kwargs...) where T
    translated = Structures.serialize(StructType(T), obj, options)
    pretty(io, translated, options, indent, imode; kwargs...)
end

function pretty(io::IO, obj::HumanReadableSExpressions.CommentedElement, options::HrsePrintOptions, indent::Integer, imode::Bool; allownewlinecomments=true, kwargs...)
    lines = split(join(obj.comments, '\n'), '\n')
    if allownewlinecomments && length(lines) == 1 && !isprimitive(obj.element)
        println(io, "; ", lines[1])
        print(io, options.indent^(indent-1))
    else
        count = 1
        disallowed = Iterators.flatten((length(i) for i in findall(r"(?![^;]);*\)", line)) for line in lines)
        while count in disallowed
            count += 1
        end
        first = true
        print(io, '(', ';'^count, ' ')
        for line in lines
            if !first
                println(io)
                print(io, options.indent^(indent-1), ' '^(count+2))
            else
                first = false
            end
            print(io, line)
        end
        print(io, ' ', ';'^count, ')')
        if allownewlinecomments
            println(io)
            print(io, options.indent^(indent-1))
        else print(io, ' ') end
    end
    pretty(io, obj.element, options, indent, imode)
end

needsspace(obj::AbstractVector, dot::Bool) = false
needsspace(obj::AbstractDict, dot::Bool) = false
needsspace(obj::Pair, dot::Bool) = false

condensed(io::IO, obj::AbstractVector, options::HrsePrintOptions) = denseiter(io, obj, options)

function denseiter(io::IO, obj, options::HrsePrintOptions)
    print(io, '(')
    first = true
    for i in obj
        t = translate(i, options)
        if !first && needsspace(t, false)
            print(io, ' ')
        else
            first = false
        end
        condensed(io, t, options)
    end
    print(io, ')')
end

function condensed(io::IO, obj::Pair, options::HrsePrintOptions)
    print(io, '(')
    tfirst = translate(obj.first, options)
    tsecond = translate(obj.second, options)
    condensed(io, tfirst, options)
    print(io, needsspaceafter(tfirst) ? ' ' : "", ".", needsspace(tsecond, true) ? ' ' : "")
    condensed(io, tsecond, options)
    print(io, ')')
end

condensed(io::IO, obj::AbstractDict, options::HrsePrintOptions) = denseiter(io, obj, options)

condensed(io::IO, obj::Symbol, options::HrsePrintOptions) = primitiveprint(io, obj, options)
needsspace(obj::Symbol, dot::Bool) = !dot && Literals.issymbol(string(obj))
condensed(io::IO, obj::AbstractString, options::HrsePrintOptions) = primitiveprint(io, obj, options)
needsspace(obj::AbstractString, dot::Bool) = !dot && Literals.issymbol(string(obj))
condensed(io::IO, obj::Integer, options::HrsePrintOptions) = primitiveprint(io, obj, options)
needsspace(obj::Integer, dot::Bool) = true
condensed(io::IO, obj::AbstractFloat, options::HrsePrintOptions) = primitiveprint(io, obj, options)
needsspace(obj::AbstractFloat, dot::Bool) = true
condensed(io::IO, obj::Bool, options::HrsePrintOptions) = primitiveprint(io, obj, options)
needsspace(obj::Bool, dot::Bool) = !dot

translate(obj::AbstractDict, options::HrsePrintOptions) = obj
translate(obj::Pair, options::HrsePrintOptions) = obj
translate(obj::AbstractVector, options::HrsePrintOptions) = obj
translate(obj::Symbol, options::HrsePrintOptions) = obj
translate(obj::AbstractString, options::HrsePrintOptions) = obj
translate(obj::Integer, options::HrsePrintOptions) = obj
translate(obj::AbstractFloat, options::HrsePrintOptions) = obj
translate(obj::Bool, options::HrsePrintOptions) = obj
translate(obj::HumanReadableSExpressions.CommentedElement, options::HrsePrintOptions) = obj
translate(obj::T, options::HrsePrintOptions) where T = Structures.serialize(StructType(T), obj, options)

function primitiveprint(io::IO, obj::Symbol, options::HrsePrintOptions)
    primitiveprint(io, string(obj), options)
end

function primitiveprint(io::IO, obj::AbstractString, options::HrsePrintOptions)
    if Literals.issymbol(string(obj))
        print(io, obj)
    else
        print(io, '"')
        for c in obj
            if haskey(ESCAPES, c)
                print(io, '\\', ESCAPES[c])
            elseif iscntrl(c) && c != '\t'
                print(io, escapesingle(c))
            else
                print(io, c)
            end
        end
        print(io, '"')
    end
end

function primitiveprint(io::IO, obj::Integer, options::HrsePrintOptions)
    print(io, string(obj, base=10))
end

function primitiveprint(io::IO, obj::AbstractFloat, options::HrsePrintOptions)
    if isinf(obj)
        print(io, obj < 0 ? "-#inf" : "#inf")
    elseif isnan(obj)
        print(io, "#nan")
    else
        print(io, string(obj))
    end
end

function primitiveprint(io::IO, obj::Bool, options::HrsePrintOptions)
    print(io, obj ? "#t" : "#f")
end

function condensed(io::IO, obj::HumanReadableSExpressions.CommentedElement, options::HrsePrintOptions)
    if options.comments
        for comment in obj.comments
            count = 1
            disallowed = [length(i) for i in findall(r"(?![^;]);*\)", comment)]
            while count in disallowed
                count += 1
            end
            print(io, '(', ';'^count, startswith(comment,';') ? ' ' : "", comment, endswith(comment,';') ? ' ' : "", ';'^count, ')')
        end
    end
    condensed(io, translate(obj.element, options), options)
end

condensed(io, obj::T, options::HrsePrintOptions) where T = condensed(io, translate(obj, options), options)

needsspace(obj::HumanReadableSExpressions.CommentedElement, dot::Bool) = false
needsspaceafter(obj) = needsspace(obj, true)
needsspaceafter(obj::HumanReadableSExpressions.CommentedElement) = needsspace(obj.element, true)

const escapesingle(c) = if c <= Char(0o777)
    "\\" * string(UInt32(c), base=8, pad=3)
else
    "\\u{$(string(UInt32(c), base=16))}"
end

const ESCAPES = Dict(
    '\n' => "n",
    '\t' => "t",
    '\r' => "r",
    '\b' => "b",
    '\f' => "f",
    '\v' => "v",
    '\a' => "a",
    '\e' => "e",
    '"' => "\"",
    '\\' => "\\",
)

end