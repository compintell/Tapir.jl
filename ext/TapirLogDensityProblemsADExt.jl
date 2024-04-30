# This file is largely copy + pasted + modified from the Zygote extension in
# LogDensityProblemsAD.jl. 

module TapirLogDensityProblemsADExt

if isdefined(Base, :get_extension)
    using LogDensityProblemsAD: ADGradientWrapper
    import LogDensityProblemsAD: ADgradient, logdensity_and_gradient, dimension, logdensity
    import Tapir
else
    using ..LogDensityProblemsAD: ADGradientWrapper
    import ..LogDensityProblemsAD: ADgradient, logdensity_and_gradient, dimension, logdensity
    import ..Tapir
end

struct TapirGradientLogDensity{Trule, L} <: ADGradientWrapper
    rule::Trule
    l::L
end

dimension(∇l::TapirGradientLogDensity) = dimension(Tapir.primal(∇l.l))

function logdensity(∇l::TapirGradientLogDensity, x::Vector{Float64})
    return logdensity(Tapir.primal(∇l.l), x)
end

"""
    ADgradient(Val(:Tapir), ℓ)

Gradient using algorithmic/automatic differentiation via Tapir.
"""
function ADgradient(::Val{:Tapir}, l)
    primal_sig = Tuple{typeof(logdensity), typeof(l), Vector{Float64}}
    rule = Tapir.build_rrule(Tapir.TapirInterpreter(), primal_sig)
    return TapirGradientLogDensity(rule, Tapir.uninit_fcodual(l))
end

Base.show(io::IO, ∇ℓ::TapirGradientLogDensity) = print(io, "Tapir AD wrapper for ", ∇ℓ.ℓ)

# We only test Tapir with `Float64`s at the minute, so make strong assumptions about the
# types supported in order to prevent silent errors.
function logdensity_and_gradient(::TapirGradientLogDensity, ::AbstractVector)
    msg = "Only Vector{Float64} presently supported for logdensity_and_gradients."
    throw(ArgumentError(msg))
end

function logdensity_and_gradient(∇l::TapirGradientLogDensity, x::Vector{Float64})
    dx = zeros(length(x))
    y, pb!! = ∇l.rule(Tapir.zero_fcodual(logdensity), ∇l.l, Tapir.CoDual(x, dx))
    @assert Tapir.primal(y) isa Float64
    pb!!(1.0)
    return Tapir.primal(y), dx
end

end