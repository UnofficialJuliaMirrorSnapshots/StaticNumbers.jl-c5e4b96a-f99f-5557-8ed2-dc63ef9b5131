module StaticNumbers

using Requires

export Static, static,
       StaticBool, StaticInteger, StaticReal, StaticNumber, StaticOrInt, StaticOrBool,
       @staticnumbers, ofstatictype

function __init__()
    @require StaticArrays="90137ffa-7385-5640-81b9-e52037218182" include("StaticArrays_glue.jl")
end

const StaticError = ErrorException("Illegal type parameter for Static.")

"""
A `StaticInteger` is an `Integer` whose value is stored in the type, and which
contains no runtime data.
"""
struct StaticInteger{X} <: Integer
    function StaticInteger{X}() where {X}
        X isa Integer && !(X isa Static) && isimmutable(X) || throw(StaticError)
        new{X}()
    end
end
StaticInteger{X}(x::Number) where {X} = x==X ? StaticInteger{X}() : throw(InexactError(:StaticInteger, StaticInteger{X}, x))
Base.@pure StaticInteger(x::Number) = StaticInteger{Integer(x)}()

"""
A `StaticReal` is a `Real` whose value is stored in the type, and which
contains no runtime data.
"""
struct StaticReal{X} <: Real
    function StaticReal{X}() where {X}
        X isa Real && !(X isa Integer) && !(X isa Static) && isimmutable(X) || throw(StaticError)
        new{X}()
    end
end
StaticReal{X}(x::Number) where {X} = x==X ? StaticReal{X}() : throw(InexactError(:StaticReal, StaticReal{X}, x))
Base.@pure StaticReal(x::Number) = StaticReal{Real(x)}()

"""
A `StaticNumber` is a `Number` whose value is stored in the type, and which
contains no runtime data.
"""
struct StaticNumber{X} <: Number
    function StaticNumber{X}() where {X}
        X isa Number && !(X isa Real) && !(X isa Static) && isimmutable(X) || throw(StaticError)
        new{X}()
    end
end
StaticNumber{X}(x::Number) where {X} = x==X ? StaticNumber{X}() : throw(InexactError(:StaticNumber, StaticReal{X}, x))
Base.@pure StaticNumber(x::Number) = StaticNumber{x}()

"""
`Static{X}` is short-hand for the `Union` of `StaticInteger{X}`, `StaticReal{X}`
and `StaticNumber{X}`.
"""
const Static{X} = Union{StaticInteger{X}, StaticReal{X}, StaticNumber{X}}

# We'll define this constructor, but not recommend it.
Static{X}() where X = static(X)

# This is the recommended constructor.
"""
`static(X)` is shorthand for `StaticInteger{X}()`, `StaticReal{X}()` or `StaticNumber{X}()`,
depending on the type of `X`.
"""
static(x::StaticInteger) = x
static(x::StaticReal) = x
static(x::StaticNumber) = x
Base.@pure static(x::Integer) = StaticInteger(x)
Base.@pure static(x::Real) = StaticReal(x)
Base.@pure static(x::Number) = StaticNumber(x)
static(x::Irrational) = x # These are already defined by their type.
Base.@pure static(x::Bool) = x ? StaticInteger{true}() : StaticInteger{false}() # help inference

# There's no point crating a Val{Static{X}} since any function that would accept
# it should treat it as equivalent to Val{X}.
Base.@pure Base.Val(::Static{X}) where X = Val(X)

# Functions that take only `Int` may be too restrictive.
# The StaticOrInt type union is often a better choice.
const StaticOrInt = Union{StaticInteger, Int}

# Promotion
Base.promote_rule(::Type{<:Static{X}}, ::Type{<:Static{X}}) where {X} =
    typeof(X)
Base.promote_rule(::Type{<:AbstractIrrational}, ::Type{<:Static{X}}) where {X} =
    promote_type(Float64, typeof(X))

# Loop over all three types specifically, instead of dispatching on the Union.
for ST in (StaticInteger, StaticReal, StaticNumber)
    # We need to override promote and promote_typeof because they don't even call
    # promote_rule for all-same types.
    Base.promote(::ST{X}, ys::ST{X}...) where {X} = ntuple(i->X, 1+length(ys))
    Base.promote_type(::Type{ST{X}}, ::Type{ST{X}}) where {X} = typeof(X)
    Base.promote_typeof(::ST{X}, ::ST{X}...) where {X} = typeof(X)
    # To avoid infinite recursion, we need this:
    Base.promote_type(::Type{ST{X}}, T::Type...) where {X} = promote_type(typeof(X), promote_type(T...))

    Base.promote_rule(::Type{<:ST{X}}, ::Type{T}) where {X,T<:Number} = promote_type(typeof(X), T)

    # Constructors
    (::Type{Complex{T}})(::ST{X}) where {T<:Real, X} = Complex{T}(X)
    (::Type{Rational{T}})(::ST{X}) where {T<:Integer, X} = Rational{T}(X)
end

Base.promote_rule(::Type{<:Static{X}}, ::Type{<:Static{Y}}) where {X,Y} =
    promote_type(typeof(X),typeof(Y))

# Bool has a special rule that we need to override?
#Base.promote_rule(::Type{Bool}, ::Type{StaticInteger{X}}) where {X} = promote_type(Bool, typeof(X))

#Base.BigInt(::Static{X}) where {X} = BigInt(X)

"ofstatictype(x,y) - like oftype(x,y), but return a `Static` `x` is a `Static`."
ofstatictype(::Static{X}, y) where {X} = static(oftype(X, y))
ofstatictype(x, y) = oftype(x, y)

# TODO: Constructors to avoid Static{Static}

# Some of the more common constructors that do not default to `convert`
# Note:  We cannot have a (::Type{T})(x::Static) where {T<:Number} constructor
# instead of all of these, because of ambiguities with user-defined types.

for T in (:Bool, :Int32, :UInt32, :Int64, :UInt64, :Int128, :BigInt, :Unsigned, :Integer)
    @eval Base.$T(::StaticInteger{X}) where X = $T(X)
end
(::Type{T})(x::Union{StaticReal{X}, StaticInteger{X}}) where {T<:AbstractFloat, X} = T(X)

# big(x) still defaults to convert.

# Single-argument functions that do not already work.
# Note: We're not attempting to support every function in Base.
# TODO: Should have a macro for easily extending support.
for fun in (:-, :zero, :one, :oneunit, :trailing_zeros, :widen, :decompose)
    @eval Base.$fun(::Static{X}) where X = Base.$fun(X)
end
for fun in (:trunc, :floor, :ceil, :round)
    @eval Base.$fun(::Union{StaticReal{X}, StaticNumber{X}}) where {X} = Base.$fun(X)
end
for fun in (:zero, :one, :oneunit)
    @eval Base.$fun(::Type{<:Static{X}}) where {X} = Base.$fun(typeof(X))
end

# It's a pity there's no AbstractBool supertype.
const StaticBool = Union{StaticInteger{false}, StaticInteger{true}}
const StaticOrBool = Union{StaticBool, Bool}

Base.:!(x::StaticBool) = !Bool(x)

# Because Base does not widen Bool
Base.widemul(x::StaticBool, y::Number) = x*y
Base.widemul(x::Number, y::StaticBool) = x*y

# false is a strong zero
for T in (Integer, Real, Number, Complex{<:Real}, StaticInteger, StaticReal, StaticNumber)
    Base.:*(::StaticInteger{false}, y::T) = zero(y)
    Base.:*(x::T, ::StaticInteger{false}) = zero(x)
end
Base.:*(::StaticInteger{false}, ::StaticInteger{false}) = false # disambig

# Handle static(Inf)*false
Base.:*(x::Bool, ::StaticReal{Y}) where Y = x*Y
Base.:*(::StaticReal{X}, y::Bool) where X = X*y

# Until https://github.com/JuliaLang/julia/pull/32117 is merged
Base.:*(::StaticInteger{false}, ::AbstractIrrational) = 0.0
Base.:*(::AbstractIrrational, ::StaticInteger{false}) = 0.0

# For complex-valued inputs, there's no auto-convert to floating-point.
# We only support a limited subset of functions, which the user can extend
# as needed.
# TODO: Should have a macro for making functions accept Static input.
for fun in (:abs, :abs2, :cos, :sin, :exp, :log, :isinf, :isfinite, :isnan)
    @eval Base.$fun(::StaticNumber{X}) where {X} = Base.$fun(X)
end
Base.sign(::StaticInteger{X}) where {X} = Base.sign(X) # work around problem with Bool

# Other functions that do not already work
Base.:(<<)(::StaticInteger{X}, y::UInt64) where {X} = X << y
Base.:(>>)(::StaticInteger{X}, y::UInt64) where {X} = X >> y

# Two-argument functions that have methods in promotion.jl that give no_op_err:
for f in (:+, :-, :*, :/, :^)
    @eval Base.$f(::Static{X}, ::Static{X}) where {X} = $f(X,X)
end
# ...where simplifications are possible:
Base.:&(::StaticInteger{X}, ::StaticInteger{X}) where {X} = X
Base.:|(::StaticInteger{X}, ::StaticInteger{X}) where {X} = X
Base.:xor(::StaticInteger{X}, ::StaticInteger{X}) where {X} = zero(X)
Base.:<(::Static{X}, ::Static{X}) where {X} = false
Base.:<=(::Static{X}, ::Static{X}) where {X} = true
Base.:rem(::Static{X}, ::Static{X}) where {X} = (X==0 || isinf(X)) ? X isa AbstractFloat ? oftype(X, NaN) : throw(DivideError()) : zero(X)
Base.:mod(::Static{X}, ::Static{X}) where {X} = (X==0 || isinf(X)) ? X isa AbstractFloat ? oftype(X, NaN) : throw(DivideError()) : zero(X)

# Three-argument function that gives no_op_err
fma(x::Static{X}, y::Static{X}, z::Static{X}) where {X} = fma(X,X,X)

# Static powers using Base.literal_pow.
# This avoids DomainError in some cases?
for T in (Bool, Int32, Int64, Float32, Float64, ComplexF32, ComplexF64, Irrational)
    Base.:^(x::T, ::StaticInteger{p}) where {p} = Base.literal_pow(^, x, Val(p))
end
Base.:^(x::Static{X}, ::StaticInteger{p}) where {X,p} = Base.literal_pow(^, X, Val(p))
Base.:^(x::Static{X}, ::StaticInteger{X}) where {X} = Base.literal_pow(^, X, Val(X)) #disambig

# ntuple accepts Val, so it should also accept static
@inline Base.ntuple(f::F, ::StaticInteger{N}) where {F,N} = Base.ntuple(f, Val(N))

# For brevity, all `Static` numbers are displayed as `static(X)`, rather than, for
# example, `StaticInteger{X}()`. It is possible to discern between the different
# types of `Static` by looking at `X`.
# To get the default behaviour back, run:
#   methods(Base.show, (IO, Static{X} where X)) |> first |> Base.delete_method
function Base.show(io::IO, x::Static{X}) where X
    print(io, "static(")
    show(io, X)
    print(io, ")")
end

# Dont promote when it's better to treat real and imaginary parts separately
Base.:/(::StaticNumber{X}, y::Real) where {X} = X/y
Base.:*(::StaticNumber{X}, y::Real) where {X} = X*y
Base.:*(x::Real, ::StaticNumber{Y}) where {Y} = x*Y

include("macros.jl")

include("LengthRanges.jl")

include("trystatic.jl")

end # module
