module Printer

import ..Hrse
import ..Literals
import Base.Unicode

dense(io::IO, obj::AbstractVector) = denseiter(io, obj)

function denseiter(io::IO, obj)
    print(io, '(')
    first = true
    for i in obj
        if !first
            print(io, ' ')
        else
            first = false
        end
        dense(io, i)
    end
    print(io, ')')
end

function dense(io::IO, obj::Pair)
    print(io, '(')
    dense(io, obj.first)
    print(io, " . ")
    dense(io, obj.second)
    print(io, ')')
end

dense(io::IO, obj::AbstractDict) = denseiter(io, obj)

function dense(io::IO, obj::Symbol)
    dense(io, string(obj))
end

function dense(io::IO, obj::AbstractString)
    if !isnothing(match(Literals.FULL_SYMBOL_REGEX, obj))
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

function dense(io::IO, obj::Integer)
    print(io, string(obj, base=10))
end

function dense(io::IO, obj::AbstractFloat)
    print(io, string(obj))
end

function dense(io::IO, obj::Bool)
    print(io, obj ? "true" : "false")
end

function dense(io::IO, obj::Hrse.CommentedElement)
    dense(io, obj.element)
end

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