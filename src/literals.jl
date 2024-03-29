module Literals

import Base.Checked: add_with_overflow, mul_with_overflow

const BASE10::UInt16 = 10
const BASE16::UInt16 = 16
const BASE2::UInt16 = 2

#=
( and ) reserved for s-expressions
:, ., = reserved for pairs
" reserved for strings
; reserved for comments
# reserved for literals
whitespace can't be in symbols in general
', ` reserved for extensions
=# 

function category_code(c::AbstractChar)
    !Base.Unicode.ismalformed(c) ? category_code(UInt32(c)) : Cint(31)
end

function category_code(x::Integer)
    x ≤ 0x10ffff ? ccall(:utf8proc_category, Cint, (UInt32,), x) : Cint(30)
end

const CATEGORY_PC = 12
const CATEGORY_PD = 13
const CATEGORY_CF = 27

function isfmt(char::Char)
    category_code(char) == CATEGORY_CF
end

function issymbolstartbanned(char::Char)
    return isspace(char) ||
        iscntrl(char) || isfmt(char) ||
        char in ['(', ')', '+', '-', '"', '\'', '`', ':', ';', '#', '.', '='] ||
        (!isascii(char) && ispunct(char)) ||
        isnumeric(char)
end

function issymbolstart(char::Char)
    return !issymbolstartbanned(char)
end

function issymbolbody(char::Char)
    return char in ['+', '-'] || category_code(char) == CATEGORY_PC || category_code(char) == CATEGORY_PD || isnumeric(char) || issymbolstart(char)
end

function issymbol(str)
    return !isempty(str) && issymbolstart(str[1]) && all(issymbolbody, str[2:end])
end

const DEC_DIGIT = "0-9"
const HEX_DIGIT = "0-9a-fA-F"
const BIN_DIGIT = "0-1"

const INT_REGEX = Regex("^([+-]?)((0[xX][$(HEX_DIGIT)_]*[$(HEX_DIGIT)][$(HEX_DIGIT)_]*)|(0[bB][$(BIN_DIGIT)_]*[$(BIN_DIGIT)][$(BIN_DIGIT)_]*)|([$(DEC_DIGIT)_]*[$(DEC_DIGIT)][$(DEC_DIGIT)_]*))\$")

const DEC_LITERAL = "([$(DEC_DIGIT)_]*[$(DEC_DIGIT)][$(DEC_DIGIT)_]*)"
const FLOAT_EXPONENT = "[eE][+-]?$DEC_LITERAL"
const FLOAT_MAIN = "($DEC_LITERAL\\.$DEC_LITERAL?|\\.$DEC_LITERAL)"
const FLOAT_REGEX = Regex("^[+-]?($FLOAT_MAIN($FLOAT_EXPONENT)?|($DEC_LITERAL$FLOAT_EXPONENT))\$")

function parseint(s::String; types=[Int64, BigInt])
    types = Vector{Type{<:Signed}}(types)
    s = s*" "
    s = replace(s, '_'=>"")
    if startswith(s, '-')
        return -parseunsigned(s[2:end], types)
    elseif startswith(s, '+')
        return parseunsigned(s[2:end], types)
    end
    return parseunsigned(s, types)
end

function parsefloat(s::String; type::Type{<:AbstractFloat}=Float64)
    return tryparse(type, s)
end

function parseunsigned(s::String, types::Vector{Type{<:Signed}})
    if startswith(s, "0x")
        return parseint(s[3:end], BASE16, types[1], types[2:end], zero(types[1]))
    elseif startswith(s, "0b")
        return parseint(s[3:end], BASE2, types[1], types[2:end], zero(types[1]))
    end
    return parseint(s, BASE10, types[1], types[2:end], zero(types[1]))
end

function parseint(s::String, base::UInt16, ::Type{BigInt}, ::Vector{Type{<:Signed}}, n::BigInt)::Union{BigInt, Nothing}
    i = 0
    base = convert(BigInt, base)

    endpos = length(s)

    c, i = iterate(s,1)::Tuple{Char, Int}
    
    while !isspace(c)
        d = convert(BigInt, parsecharint(c))
        n *= base
        n += d
        
        c, i = iterate(s,i)::Tuple{Char, Int}
        i > endpos && break
    end
    return n
end

function parseint(s::String, base::UInt16, ::Type{T}, overflowtypes::Vector{Type{<:Signed}}, n::T)::Union{Integer, Nothing} where T <: Signed
    i = 0
    m::T = if base == BASE10
        div(typemax(T) - T(9), T(10))
    elseif base == BASE16
        div(typemax(T) - T(15), T(16))
    elseif base == BASE2
        div(typemax(T) - T(1), T(2))
    end
    
    baseT = convert(T, base)

    endpos = length(s)

    c, i = iterate(s,1)::Tuple{Char, Int}

    while n <= m
        d = convert(T, parsecharint(c))

        n *= baseT
        n += d

        c, i = iterate(s,i)::Tuple{Char, Int}
        i >= endpos && break
    end
    
    while !isspace(c)

        nold = n

        d = convert(T, parsecharint(c))
        n, ov_mul = mul_with_overflow(n, baseT)
        n, ov_add = add_with_overflow(n, d)
        if ov_mul || ov_add
            if length(overflowtypes) == 0
                return nothing
            else
                newtype = overflowtypes[1]
                return parseint(s[i-1:end], base, newtype, overflowtypes[2:end], convert(newtype, nold))
            end
        end

        c, i = iterate(s,i)::Tuple{Char, Int}
        i > endpos && break
    end
    return n
end

function parsecharint(c::Char)::UInt32
    i = reinterpret(UInt32, c)>>24
    if i < 0x40
        return i - 0x30
    end
    return i - 0x57
end

end