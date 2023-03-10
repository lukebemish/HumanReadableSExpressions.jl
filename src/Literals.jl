module Literals

import Base.Checked: add_with_overflow, mul_with_overflow

const BASE10::UInt16 = 10
const BASE16::UInt16 = 16
const BASE2::UInt16 = 2

function nextoverflow(type::Type{T})::Union{Type{<:Integer},Nothing} where {T <: Integer}
    if T == Int8
        return Int16
    elseif T == Int16
        return Int32
    elseif T == Int32
        return Int64
    elseif T == Int64
        return Int128
    elseif T == Int128
        return BigInt
    end
    return nothing
end

function parseint(s::String)
    s = s*" "
    s = replace(s, '_'=>"")
    if startswith(s, '-')
        return -parseunsigned(s[2:end])
    elseif startswith(s, '+')
        return parseunsigned(s[2:end])
    end
    return parseunsigned(s)
end

function parseunsigned(s::String)
    if startswith(s, "0x")
        return parseint(s[3:end], BASE16, Int, BigInt, 0)
    elseif startswith(s, "0b")
        return parseint(s[3:end], BASE2, Int, BigInt, 0)
    end
    return parseint(s, BASE10, Int, BigInt, 0)
end

function parseint(s::String, base::UInt16, type::Type{BigInt}, ::Nothing, n::BigInt)::BigInt
    i = 0 #TODO: sign
    base = convert(BigInt, base)

    endpos = length(s)

    c, i = iterate(s,1)::Tuple{Char, Int}
    
    while !isspace(c)

        nold = n

        d = convert(BigInt, parsecharint(c))
        n *= base
        n += d
        
        c, i = iterate(s,i)::Tuple{Char, Int}
        i >= endpos && break
    end
    return n
end

function parseint(s::String, base::UInt16, type::Type{T}, overflowtype::Union{Type{V},Nothing}, n::T)::Integer where {T <: Integer, V <: Integer}
    i = 0 #TODO: sign
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
        #if i > endpos
        #    n *= sgn
        #    return n
        #end

        c, i = iterate(s,i)::Tuple{Char, Int}
        i >= endpos && break
    end
    
    while !isspace(c)

        nold = n

        d = convert(T, parsecharint(c))
        n, ov_mul = mul_with_overflow(n, baseT)
        n, ov_add = add_with_overflow(n, d)
        if ov_mul || ov_add
            if isnothing(overflowtype)
                return nothing
            else
                return parseint(s[i-1:end], base, overflowtype, nextoverflow(overflowtype), convert(overflowtype, nold))
            end
        end

        c, i = iterate(s,i)::Tuple{Char, Int}
        i >= endpos && break
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