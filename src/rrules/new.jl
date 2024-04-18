@inline @generated function _new_(::Type{T}, x::Vararg{Any, N}) where {T, N}
    return Expr(:new, :T, map(n -> :(x[$n]), 1:N)...)
end

@is_primitive MinimalCtx Tuple{typeof(_new_), Vararg}

function rrule!!(
    ::CoDual{typeof(_new_)}, ::CoDual{Type{P}}, x::Vararg{CoDual, N}
) where {P, N}
    y = _new_(P, tuple_map(primal, x)...)
    F = fdata_type(tangent_type(P))
    R = rdata_type(tangent_type(P))
    dy = F == NoFData ? NoFData() : build_fdata(P, tuple_map(primal, x), tuple_map(tangent, x))
    pb!! = if ismutabletype(P)
        if F == NoFData
            NoPullback((NoRData(), NoRData(), tuple_map(zero_rdata ∘ tangent, x)...))
        else
            function _mutable_new_pullback!!(::NoRData)
                rdatas = tuple_map(rdata ∘ _value,  Tuple(dy.fields)[1:N])
                return NoRData(), NoRData(), rdatas...
            end
        end
    else
        if R == NoRData
            NoPullback((NoRData(), NoRData(), tuple_map(zero_rdata ∘ tangent, x)...))
        else
            function _new_pullback_for_immutable!!(dy::T) where {T}
                data = Tuple(T <: NamedTuple ? dy : dy.data)[1:N]
                return NoRData(), NoRData(), map(_value, data)...
            end
        end
    end
    return CoDual(y, dy), pb!!
end

@generated function build_fdata(::Type{P}, x::Tuple, fdata::Tuple) where {P}
    names = fieldnames(P)
    fdata_exprs = map(eachindex(names)) do n
        F = fdata_field_type(P, n)
        if n <= length(fdata.parameters)
            data_expr = Expr(:call, __get_data, P, :x, :fdata, n)
            return F <: PossiblyUninitTangent ? Expr(:call, F, data_expr) : data_expr
        else
            return :($F())
        end
    end
    F_out = fdata_type(tangent_type(P))
    return :($F_out(NamedTuple{$names}($(Expr(:call, tuple, fdata_exprs...)))))
end

# Helper for build_fdata
@inline function __get_data(::Type{P}, x, f, n) where {P}
    tmp = getfield(f, n)
    return ismutabletype(P) ? zero_tangent(getfield(x, n), tmp) : tmp
end

@inline function build_fdata(::Type{P}, x::Tuple, fdata::Tuple) where {P<:NamedTuple}
    return fdata_type(tangent_type(P))(fdata)
end

function generate_hand_written_rrule!!_test_cases(rng_ctor, ::Val{:new})

    # Specialised test cases for _new_.
    specific_test_cases = Any[
        (false, :stability_and_allocs, nothing, _new_, @NamedTuple{}),
        (false, :stability_and_allocs, nothing, _new_, @NamedTuple{y::Float64}, 5.0),
        (false, :stability_and_allocs, nothing, _new_, @NamedTuple{y::Int, x::Int}, 5, 4),
        (
            false, :stability_and_allocs, nothing,
            _new_, @NamedTuple{y::Float64, x::Int}, 5.0, 4,
        ),
        (
            false, :stability_and_allocs, nothing,
            _new_, @NamedTuple{y::Vector{Float64}, x::Int}, randn(2), 4,
        ),
        (
            false, :stability_and_allocs, nothing,
            _new_, @NamedTuple{y::Vector{Float64}}, randn(2),
        ),
        (
            false, :stability_and_allocs, nothing,
            _new_, TestResources.TypeStableStruct{Float64}, 5, 4.0,
        ),
        (false, :stability_and_allocs, nothing, _new_, UnitRange{Int64}, 5, 4),
        (
            false, :stability_and_allocs, nothing,
            _new_, TestResources.TypeStableMutableStruct{Float64}, 5.0, 4.0,
        ),
        (
            false, :none, nothing,
            _new_, TestResources.TypeStableMutableStruct{Any}, 5.0, 4.0,
        ),
        (false, :none, nothing, _new_, TestResources.StructFoo, 6.0, [1.0, 2.0]),
        (false, :none, nothing, _new_, TestResources.StructFoo, 6.0),
        (false, :none, nothing, _new_, TestResources.MutableFoo, 6.0, [1.0, 2.0]),
        (false, :none, nothing, _new_, TestResources.MutableFoo, 6.0),
        (false, :stability_and_allocs, nothing, _new_, TestResources.StructNoFwds, 5.0),
        (false, :stability_and_allocs, nothing, _new_, TestResources.StructNoRvs, [5.0]),
        (
            false, :stability_and_allocs, nothing,
            _new_, LowerTriangular{Float64, Matrix{Float64}}, randn(2, 2),
        ),
        (
            false, :stability_and_allocs, nothing,
            _new_, UpperTriangular{Float64, Matrix{Float64}}, randn(2, 2),
        ),
        (
            false, :stability_and_allocs, nothing,
            _new_, UnitLowerTriangular{Float64, Matrix{Float64}}, randn(2, 2),
        ),
        (
            false, :stability_and_allocs, nothing,
            _new_, UnitUpperTriangular{Float64, Matrix{Float64}}, randn(2, 2),
        ),
    ]
    general_test_cases = map(TestTypes.PRIMALS) do (interface_only, P, args)
        return (interface_only, :none, nothing, _new_, P, args...)
    end
    test_cases = vcat(specific_test_cases, general_test_cases)
    memory = Any[]
    return test_cases, memory
end

function generate_derived_rrule!!_test_cases(rng_ctor, ::Val{:new})
    test_cases = Any[]
    memory = Any[]
    return test_cases, memory
end
