
"""
    NoFwdsData

Singleton type which indicates that there is nothing to be propagated on the forwards-pass
in addition to the primal data.
"""
struct NoFwdsData end

"""
    FwdsData(data::NamedTuple)

The component of a `struct` which is propagated alongside the primal on the forwards-pass of
AD. For example, the tangents for `Float64`s do not need to be propagated on the forwards-
pass of reverse-mode AD, so any `Float64` fields of `Tangent` do not need to appear in the
associated `FwdsData`.
"""
struct FwdsData{T<:NamedTuple}
    data::T
end

"""
    forwards_data_type(T)

Returns the type of the forwards data associated to a tangent of type `T`.
"""
forwards_data_type(T)

forwards_data_type(x) = throw(error("$x is not a type. Perhaps you meant typeof(x)?"))

forwards_data_type(::Type{T}) where {T<:IEEEFloat} = NoFwdsData

function forwards_data_type(::Type{PossiblyUninitTangent{T}}) where {T}
    Tfields = forwards_data_type(T)
    return PossiblyUninitTangent{Tfields}
end

@generated function forwards_data_type(::Type{T}) where {T}

    # If the tangent type is NoTangent, then the forwards-component must be `NoFwdsData`.
    T == NoTangent && return NoFwdsData

    # This method can only handle struct types. Tell user to implement their own method.
    isprimitivetype(T) && throw(error(
        "$T is a primitive type. Implement a method of `forwards_data_type` for it."
    ))

    # If the type is a Union, then take the union type of its arguments.
    T isa Union && return Union{forwards_data_type(T.a), forwards_data_type(T.b)}

    # If the type is itself abstract, it's forward data could be anything.
    # The same goes for if the type has any undetermined type parameters.
    (isabstracttype(T) || !isconcretetype(T)) && return Any

    # If `P` is a mutable type, then its forwards data is its tangent.
    ismutabletype(T) && return T

    # If `P` is an immutable type, then some of its fields may not need to be propagated
    # on the forwards-pass.
    if T <: Tangent
        Tfields = fields_type(T)
        fwds_data_field_types = map(1:fieldcount(Tfields)) do n
            return forwards_data_type(fieldtype(Tfields, n))
        end
        all(==(NoFwdsData), fwds_data_field_types) && return NoFwdsData
        return FwdsData{NamedTuple{fieldnames(Tfields), Tuple{fwds_data_field_types...}}}
    end

    return :(error("Unhandled type $T"))
end

forwards_data_type(::Type{Ptr{P}}) where {P} = Ptr{tangent_type(P)}

@generated function forwards_data_type(::Type{P}) where {P<:Tuple}
    isa(P, Union) && return Union{forwards_data_type(P.a), forwards_data_type(P.b)}
    isempty(P.parameters) && return NoFwdsData
    isa(last(P.parameters), Core.TypeofVararg) && return Any
    all(p -> forwards_data_type(p) == NoFwdsData, P.parameters) && return NoFwdsData
    return Tuple{map(forwards_data_type, fieldtypes(P))...}
end

@generated function forwards_data_type(::Type{NamedTuple{names, T}}) where {names, T<:Tuple}
    if forwards_data_type(T) == NoFwdsData
        return NoFwdsData
    elseif isconcretetype(forwards_data_type(T))
        return NamedTuple{names, forwards_data_type(T)}
    else
        return Any
    end
end

"""
    forwards_data(t)::forwards_data_type(typeof(t))

Extract the forwards data from tangent `t`.
"""
@generated function forwards_data(t::T) where {T}

    # Ask for the forwards-data type. Useful catch-all error checking for unexpected types.
    F = forwards_data_type(T)

    # Catch-all for anything with no forwards-data.
    F == NoFwdsData && return :(NoFwdsData())

    # Catch-all for anything where we return the whole object (mutable structs, arrays...).
    F == T && return :(t)

    # T must be a `Tangent` by now. If it's not, something has gone wrong.
    !(T <: Tangent) && return :(error("Unhandled type $T"))
    # return :(F(forwards_data(t.fields)))
    return :($F(forwards_data(t.fields)))
end

@generated function forwards_data(t::Union{Tuple, NamedTuple})
    forwards_data_type(t) == NoFwdsData && return NoFwdsData()
    return :(tuple_map(forwards_data, t))
end

uninit_fdata(p) = forwards_data(uninit_tangent(p))

"""
    NoRvsData()

Nothing to propagate backwards on the reverse-pass.
"""
struct NoRvsData end

increment!!(::NoRvsData, ::NoRvsData) = NoRvsData()

"""
    RvsData(data::NamedTuple)

"""
struct RvsData{T<:NamedTuple}
    data::T
end

increment!!(x::RvsData{T}, y::RvsData{T}) where {T} = RvsData(increment!!(x.data, y.data))

"""
    reverse_data_type(T)

Returns the type of the reverse data of a tangent of type T.
"""
reverse_data_type(T)

reverse_data_type(x) = throw(error("$x is not a type. Perhaps you meant typeof(x)?"))

reverse_data_type(::Type{T}) where {T<:IEEEFloat} = T

function reverse_data_type(::Type{PossiblyUninitTangent{T}}) where {T}
    return NoRvsData
    # return PossiblyUninitTangent{reverse_data_type(T)}
end

@generated function reverse_data_type(::Type{T}) where {T}

    # If the tangent type is NoTangent, then the reverse-component must be `NoRvsData`.
    T == NoTangent && return NoRvsData

    # This method can only handle struct types. Tell user to implement their own method.
    isprimitivetype(T) && throw(error(
        "$T is a primitive type. Implement a method of `reverse_data_type` for it."
    ))

    # If the type is a Union, then take the union type of its arguments.
    T isa Union && return Union{reverse_data_type(T.a), reverse_data_type(T.b)}

    # If the type is itself abstract, it's reverse data could be anything.
    # The same goes for if the type has any undetermined type parameters.
    (isabstracttype(T) || !isconcretetype(T)) && return Any

    # If `P` is a mutable type, then all tangent info is propagated on the forwards-pass.
    ismutabletype(T) && return NoRvsData

    # If `T` is an immutable type, then some of its fields may not have been propagated on
    # the forwards-pass.
    if T <: Tangent
        Tfs = fields_type(T)
        rvs_types = map(n -> reverse_data_type(fieldtype(Tfs, n)), 1:fieldcount(Tfs))
        all(==(NoRvsData), rvs_types) && return NoRvsData
        return RvsData{NamedTuple{fieldnames(Tfs), Tuple{rvs_types...}}}
    end
end

reverse_data_type(::Type{<:Ptr}) = NoRvsData

@generated function reverse_data_type(::Type{P}) where {P<:Tuple}
    isa(P, Union) && return Union{reverse_data_type(P.a), reverse_data_type(P.b)}
    isempty(P.parameters) && return NoRvsData
    isa(last(P.parameters), Core.TypeofVararg) && return Any
    all(p -> reverse_data_type(p) == NoRvsData, P.parameters) && return NoRvsData
    return Tuple{map(reverse_data_type, fieldtypes(P))...}
end

function reverse_data_type(::Type{NamedTuple{names, T}}) where {names, T<:Tuple}
    if reverse_data_type(T) == NoRvsData
        return NoRvsData
    elseif isconcretetype(reverse_data_type(T))
        return NamedTuple{names, reverse_data_type(T)}
    else
        return Any
    end
end

"""
    reverse_data(t)::reverse_data_type(typeof(t))

Extract the reverse data from tangent `t`.
"""
@generated function reverse_data(t::T) where {T}

    # Ask for the reverse-data type. Useful catch-all error checking for unexpected types.
    R = reverse_data_type(T)

    # Catch-all for anything with no reverse-data.
    R == NoRvsData && return :(NoRvsData())

    # Catch-all for anything where we return the whole object (Float64, isbits structs, ...)
    R == T && return :(t)

    # T must be a `Tangent` by now. If it's not, something has gone wrong.
    !(T <: Tangent) && return :(error("Unhandled type $T"))
    return :($(reverse_data_type(T))(reverse_data(t.fields)))
end

@generated function reverse_data(t::Union{Tuple, NamedTuple})
    reverse_data_type(t) == NoRvsData && return NoRvsData()
    return :(tuple_map(reverse_data, t))
end

"""
    zero_reverse_data(p)

Given value `p`, return the zero element associated to its reverse data type.
"""
zero_reverse_data(p)

zero_reverse_data(p::IEEEFloat) = zero(p)

@generated function zero_reverse_data(p::P) where {P}

    # Get types associated to primal.
    T = tangent_type(P)
    R = reverse_data_type(T)

    # If there's no reverse data, return no reverse data, e.g. for mutable types.
    R == NoRvsData && return :(NoRvsData())

    # T ought to be a `Tangent`. If it's not, something has gone wrong.
    !(T <: Tangent) && Expr(:call, error, "Unhandled type $T")
    names = fieldnames(P)
    getfield_exprs = map(n -> Expr(:call, getfield, :p, QuoteNode(n)), names)
    zs = Expr(:tuple, map(x -> Expr(:call, zero_reverse_data, x), getfield_exprs)...)
    return :($R(NamedTuple{$names}($zs)))
end

@generated function zero_reverse_data(p::Union{Tuple, NamedTuple})
    reverse_data_type(tangent_type(p)) == NoRvsData && return NoRvsData()
    return :(tuple_map(zero_reverse_data, p))
end

"""

"""
zero_reverse_data_from_type(::Type{P}) where {P}

zero_reverse_data_from_type(::Type{P}) where {P<:IEEEFloat} = zero(P)

@generated function zero_reverse_data_from_type(::Type{P}) where {P}

    # Get types associated to primal.
    T = tangent_type(P)
    R = reverse_data_type(T)

    # If there's no reverse data, return no reverse data, e.g. for mutable types.
    R == NoRvsData && return NoRvsData()

    # If the type is itself abstract, it's reverse data could be anything.
    # The same goes for if the type has any undetermined type parameters.
    (isabstracttype(T) || !isconcretetype(T)) && return Any

    # T ought to be a `Tangent`. If it's not, something has gone wrong.
    !(T <: Tangent) && return Expr(:call, error, "Unhandled type $T")
    return quote
        zs = tuple_map(zero_reverse_data_from_type, $(fieldtypes(P)))
        return $R(NamedTuple{$(fieldnames(P))}(zs))
    end
end

@generated function zero_reverse_data_from_type(::Type{P}) where {P<:Tuple}
    # Get types associated to primal.
    T = tangent_type(P)
    R = reverse_data_type(T)

    # If there's no reverse data, return no reverse data, e.g. for mutable types.
    R == NoRvsData && return NoRvsData()

    return Expr(:call, tuple, map(p -> :(zero_reverse_data_from_type($p)), P.parameters)...)
end

@generated function zero_reverse_data_from_type(::Type{NamedTuple{names, Pt}}) where {names, Pt}

    # Get types associated to primal.
    P = NamedTuple{names, Pt}
    T = tangent_type(P)
    R = reverse_data_type(T)

    # If there's no reverse data, return no reverse data, e.g. for mutable types.
    R == NoRvsData && return NoRvsData()

    return :(NamedTuple{$names}(zero_reverse_data_from_type($Pt)))
end

"""
    combine_data(tangent_type, forwards_data, reverse_data)


"""
combine_data(::Type{NoTangent}, ::NoFwdsData, ::NoRvsData) = NoTangent()
combine_data(::Type{T}, ::NoFwdsData, r::T) where {T} = r
combine_data(::Type{T}, f::T, ::NoRvsData) where {T} = f

# General structs.
function combine_data(::Type{T}, f::FwdsData{F}, r::RvsData{R}) where {T<:Tangent, F, R}
    nt = fields_type(T)
    Ts = fieldtypes(nt)
    return T(nt(tuple(map(combine_data, Ts, f.data, r.data)...)))
end

function combine_data(::Type{T}, f::FwdsData{F}, ::NoRvsData) where {T<:Tangent, names, F<:NamedTuple{names}}
    return combine_data(T, f, RvsData(NamedTuple{names}(tuple_map(_ -> NoRvsData(), names))))
end


# Tuples and NamedTuples
function combine_data(::Type{T}, f::Tuple, r::Tuple) where {T}
    return T(map(combine_data, fieldtypes(T), f, r))
end
function combine_data(::Type{T}, f::NamedTuple{ns}, r::NamedTuple{ns}) where {T, ns}
    return T(map(combine_data, fieldtypes(T), f, r))
end
function combine_data(::Type{T}, f::Union{Tuple, NamedTuple}, r::NoRvsData) where {T}
    return combine_data(T, f, map(_ -> NoRvsData(), f))
end
function combine_data(::Type{T}, f::NoFwdsData, r::Union{Tuple, NamedTuple}) where {T}
    return combine_data(T, map(_ -> NoFwdsData(), r), r)
end


"""
    zero_tangent(p, ::NoFwdsData)


"""
zero_tangent(p, ::NoFwdsData) = zero_tangent(p)

function zero_tangent(p::P, f::F) where {P, F}
    T = tangent_type(P)
    T == F && return f
    r = reverse_data(zero_tangent(p))
    return combine_data(tangent_type(P), f, r)
end

zero_tangent(p::Tuple, f::Union{Tuple, NamedTuple}) = tuple_map(zero_tangent, p, f)