module Structures

import ..Hrse: ReadOptions, PrinterOptions
import StructTypes
import StructTypes: StructType, NumberType, BoolType, numbertype, StringType, construct, DictType, ArrayType, Mutable, OrderedStruct, UnorderedStruct, NullType, CustomStruct, AbstractType

function deserialize(::StructType, obj, ::Type{T}, options::ReadOptions)::T where T
    throw(ArgumentError("Cannot translate object of type $(typeof(obj)) to type $T"))
end

function deserialize(::NumberType, obj::Number, ::Type{T}, options::ReadOptions)::T where T
    n = convert(numbertype(T), obj)
    return construct(T, n)
end

function deserialize(::BoolType, obj::Bool, ::Type{T}, options::ReadOptions)::T where T
    return construct(T, obj)
end

function deserialize(::StringType, obj::String, ::Type{T}, options::ReadOptions)::T where T
    return construct(T, obj)
end

function deserialize(::DictType, obj::Vector, ::Type{T}, options::ReadOptions)::T where T
    dict = Dict(obj)
    return construct(T, dict)
end

function deserialize(::DictType, obj::Pair, ::Type{T}, options::ReadOptions)::Pair where T <: Pair
    return Pair(
        pairfirst(T, obj),
        pairsecond(T, obj)
    )
end

function pairfirst(::Type{<:Pair}, obj::Pair)
    return obj.first
end

function pairfirst(::Type{<:Pair{A}}, obj::Pair) where A
    return deserialize(StructType(A), obj.first, A, options)
end

function pairfirst(::Type{<:Pair{A,B}}, obj::Pair) where {A,B}
    return deserialize(StructType(A), obj.first, A, options)
end

function pairsecond(::Type{<:Pair}, obj::Pair)
    return obj.second
end

function pairsecond(::Type{<:Pair{A,B}}, obj::Pair) where {A,B}
    return deserialize(StructType(B), obj.second, B, options)
end

function deserialize(::ArrayType, obj::Vector, ::Type{T}, options::ReadOptions)::T where T
    return construct(T, obj)
end

function deserialize(::NullType, obj::Vector, ::Type{T}, options::ReadOptions)::T where T
    if length(obj) > 0
        throw(ArgumentError("Null must be represented by an empty list!"))
    end
    return T()
end

function deserialize(::Mutable, obj::Vector, ::Type{T}, options::ReadOptions)::T where T
    dict = try
        Dict(obj)
    catch
        throw(ArgumentError("Vector contains non-dict entries!"))
    end
    out = T()
    for (k, v) in dict
        fn = deserialize(StructType(Symbol), k, Symbol, options)
        applied = StructType.applyfield!(out, fn) do i, name, ft
            deserialize(StructType(ft), v, ft, options)
        end
        if !applied
            throw(ArgumentError("Cannot apply field $fn to type $T"))
        end
    end
    return out
end

function deserialize(::OrderedStruct, obj::Vector, ::Type{T}, options::ReadOptions)::T where T
    out = []
    StructTypes.foreachfield(T) do i, name, ft
        if i > length(obj)
            throw(ArgumentError("Too few elements in vector for type $T"))
        end
        push!(out, deserialize(StructType(ft), obj[i], ft, options))
    end
    return construct(T, out...)
end

function deserialize(::UnorderedStruct, obj::Vector, ::Type{T}, options::ReadOptions)::T where T
    dict = try
        Dict(obj)
    catch
        throw(ArgumentError("Vector contains non-dict entries!"))
    end
    out = []
    StructTypes.foreachfield(T) do i, name, ft
        if haskey(dict, String(name))
            push!(out, deserialize(StructType(ft), dict[String(name)], ft, options))
        else
            push!(out, nothing)
        end
    end
    return construct(T, out...)
end

function deserialize(::CustomStruct, obj::Vector, ::Type{T}, options::ReadOptions)::T where T
    lowered = StructTypes.lowertype(T)
    return construct(T, deserialize(StructType(lowered), obj, lowered, options))
end

function deserialize(::AbstractType, obj::Vector, ::Type{T}, options::ReadOptions)::T where T
    key = String(StructTypes.subtypekey(T))
    i = findfirst(j -> (j isa Pair && first(j) == key), obj)
    v = obj[i]
    translated = deserialize(StructType(Symbol), last(v), Symbol, options)
    if !haskey(StructTypes.subtypes(T), translated)
        throw(ArgumentError("Cannot translate object to to type $T with key $translated"))
    end
    newtype = StructTypes.subtypes(T)[translated]
    return deserialize(StructType(newtype), obj, newtype, options)
end

function serialize(::StructType, obj, options::PrinterOptions)
    throw(ArgumentError("Cannot translate object of type $(typeof(obj)) to a serializable form"))
end

function serialize(::NumberType, obj::T, options::PrinterOptions) where T
    return numbertype(T)(obj)
end

function serialize(::BoolType, obj, options::PrinterOptions)
    return Bool(obj)
end

function serialize(::StringType, obj, options::PrinterOptions)
    return string(obj)
end

function serialize(::DictType, obj, options::PrinterOptions)
    return [serialize(StructType(typeof(k)), k, options) => serialize(StructType(typeof(v)), v, options) for (k, v) in StructTypes.keyvaluepairs(obj)]
end

function serialize(::DictType, obj::Pair, options::PrinterOptions)
    return serialize(StructType(typeof(obj.first)), obj.first, options) => serialize(StructType(typeof(obj.second)), obj.second, options)
end

function serialize(::ArrayType, obj, options::PrinterOptions)
    return [serialize(StructType(typeof(v)), v, options) for v in obj]
end

function serialize(::NullType, obj, options::PrinterOptions)
    return []
end

function serialize(::Mutable, obj, options::PrinterOptions)
    out = []
    StructTypes.foreachfield(obj) do i, name, ft, v
        push!(out, serialize(StructType(Symbol), name, options) => serialize(StructType(ft), v, options))
    end
end

function serialize(::OrderedStruct, obj, options::PrinterOptions)
    out = []
    StructTypes.foreachfield(obj) do i, name, ft, v
        push!(out, serialize(StructType(ft), v, options))
    end
    return out
end

function serialize(::UnorderedStruct, obj, options::PrinterOptions)
    out = []
    StructTypes.foreachfield(obj) do i, name, ft, v
        push!(out, serialize(StructType(Symbol), name, options) => serialize(StructType(ft), v, options))
    end
    return out
end

function serialize(::CustomStruct, obj, options::PrinterOptions)
    lowered = StructTypes.lower(obj)
    return serialize(StructType(lowered), lowered, options)
end

end