module Printer

import ..Hrse
import ..Hrse: PrinterOptions
import ..Literals
import Base.Unicode

isprimitive(obj) = false
isprimitive(::Integer) = true
isprimitive(::AbstractFloat) = true
isprimitive(::Bool) = true
isprimitive(::Symbol) = true
isprimitive(::AbstractString) = true

const RESERVED_SYMBOLS = ["true", "false"]

function pretty(io::IO, obj::AbstractVector, options::PrinterOptions, indent::Integer, imode::Bool; kwargs...)
    prettyiter(io, obj, options, indent, imode; kwargs...)
end

function prettyiter(io::IO, obj, options::PrinterOptions, indent::Integer, imode::Bool; noparenprimitive=false, root=false, kwargs...)
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

function pretty(io::IO, obj::Pair, options::PrinterOptions, indent::Integer, imode::Bool; forcegroup=false, kwargs...)
    if options.pairmode == Hrse.DOT_MODE || forcegroup
        print(io, '(')
        pretty(io, obj.first, options, indent, false)
        print(io, " . ")
        pretty(io, obj.second, options, indent, false)
        print(io, ')')
    elseif options.pairmode == Hrse.EQUALS_MODE
        pretty(io, obj.first, options, indent, false; forcegroup=true)
        print(io, " = ")
        pretty(io, obj.second, options, indent, false)
    elseif options.pairmode == Hrse.COLON_MODE
        pretty(io, obj.first, options, indent, false; forcegroup=true)
        print(io, ": ")
        pretty(io, obj.second, options, indent, true; allownewlinecomments=false)
    end
end

pretty(io::IO, obj::AbstractDict, options::PrinterOptions, indent::Integer, imode::Bool; kwargs...) = prettyiter(io, obj, options, indent, imode; kwargs...)

pretty(io::IO, obj::Symbol, options::PrinterOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)
pretty(io::IO, obj::AbstractString, options::PrinterOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)
pretty(io::IO, obj::Integer, options::PrinterOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)
pretty(io::IO, obj::AbstractFloat, options::PrinterOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)
pretty(io::IO, obj::Bool, options::PrinterOptions, indent::Integer, imode::Bool; kwargs...) = primitiveprint(io, obj, options)

function pretty(io::IO, obj::Hrse.CommentedElement, options::PrinterOptions, indent::Integer, imode::Bool; allownewlinecomments=true, kwargs...)
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

condensed(io::IO, obj::AbstractVector, options::PrinterOptions) = denseiter(io, obj, options)

function denseiter(io::IO, obj, options::PrinterOptions)
    print(io, '(')
    first = true
    for i in obj
        if !first && needsspace(i, false)
            print(io, ' ')
        else
            first = false
        end
        condensed(io, i, options)
    end
    print(io, ')')
end

function condensed(io::IO, obj::Pair, options::PrinterOptions)
    print(io, '(')
    condensed(io, obj.first, options)
    print(io, needsspaceafter(obj.first) ? ' ' : "", ".", needsspace(obj.second, true) ? ' ' : "")
    condensed(io, obj.second, options)
    print(io, ')')
end

condensed(io::IO, obj::AbstractDict, options::PrinterOptions) = denseiter(io, obj, options)

condensed(io::IO, obj::Symbol, options::PrinterOptions) = primitiveprint(io, obj, options)
needsspace(obj::Symbol, dot::Bool) = !dot && (string(obj) in RESERVED_SYMBOLS || isnothing(match(Literals.FULL_SYMBOL_REGEX, string(obj))))
condensed(io::IO, obj::AbstractString, options::PrinterOptions) = primitiveprint(io, obj, options)
needsspace(obj::AbstractString, dot::Bool) = !dot && (obj in RESERVED_SYMBOLS || isnothing(match(Literals.FULL_SYMBOL_REGEX, obj)))
condensed(io::IO, obj::Integer, options::PrinterOptions) = primitiveprint(io, obj, options)
needsspace(obj::Integer, dot::Bool) = true
condensed(io::IO, obj::AbstractFloat, options::PrinterOptions) = primitiveprint(io, obj, options)
needsspace(obj::AbstractFloat, dot::Bool) = true
condensed(io::IO, obj::Bool, options::PrinterOptions) = primitiveprint(io, obj, options)
needsspace(obj::Bool, dot::Bool) = !dot

function primitiveprint(io::IO, obj::Symbol, options::PrinterOptions)
    primitiveprint(io, string(obj), options)
end

function primitiveprint(io::IO, obj::AbstractString, options::PrinterOptions)
    if obj in RESERVED_SYMBOLS
        print(io, '"', obj, '"')
    elseif !isnothing(match(Literals.FULL_SYMBOL_REGEX, obj))
        print(io, obj)
    else
        print(io, '"')
        for c in obj
            if haskey(ESCAPES, c)
                print(io, '\\', ESCAPES[c])
            elseif Base.Unicode.category_code(c) == Base.Unicode.UTF8PROC_CATEGORY_CC
                print(io, escapesingle(c))
            else
                print(io, c)
            end
        end
        print(io, '"')
    end
end

function primitiveprint(io::IO, obj::Integer, options::PrinterOptions)
    print(io, string(obj, base=10))
end

function primitiveprint(io::IO, obj::AbstractFloat, options::PrinterOptions)
    print(io, string(obj))
end

function primitiveprint(io::IO, obj::Bool, options::PrinterOptions)
    print(io, obj ? "#t" : "#f")
end

function condensed(io::IO, obj::Hrse.CommentedElement, options::PrinterOptions)
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
    condensed(io, obj.element, options)
end

needsspace(obj::Hrse.CommentedElement, dot::Bool) = false
needsspaceafter(obj) = needsspace(obj, true)
needsspaceafter(obj::Hrse.CommentedElement) = needsspace(obj.element, true)

const escapesingle(c) = if c <= Char(0o777)
    "\\" * string(UInt32(c), base=8, pad=3)
elseif c <= Char(0xFFFF)
    "\\u" * string(UInt32(c), base=16, pad=4)
else
    "\\U" * string(UInt32(c), base=16, pad=8)
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