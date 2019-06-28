#
# ResizableArrays.jl --
#
# Implement arrays which are resizable.
#

module ResizableArrays

export
    ResizableArray,
    ResizableMatrix,
    ResizableVector,
    isgrowable,
    maxlength

using Base: tail, OneTo, throw_boundserror

"""
## Create unitialized resizable array

```julia
ResizableArray{T}(undef, dims)
```

yields a resizable array with uninitialized elements of type `T` and dimensions
`dims`.  Dimensions may be a tuple of integers or a a list of integers.  The
number `N` of dimensions may be explictely specified:

```julia
ResizableArray{T,N}(undef, dims)
```

A resizable array stores its elements contiguously in a vector so linear
indexing is fast.

The dimensions of a resizable array `A` may be changed:

```julia
resize!(A, dims)
```

with `dims` the new dimensions.  The number of dimensions must remain unchanged
but the length of the array may change.  Depending on the type of the object
backing the storage of the array, it may be possible or not to augment the
number of elements of the array.  When array elements are stored in a regular
Julia vector, the number of element can be augmented.  When such a resizable
array is resized, its contents is preserved if only the last dimension is
changed.

Resizable arrays are designed to re-use workspace arrays if possible to avoid
calling the garbage collector.  This may be useful for


## Convert to resizable arrays

The [`convert`](@ref) and `ResizableArray` methods can be used to convert an
array `A` to a resizable array:

```julia
convert(ResizableArray, A)
ResizableArray(A)
```

Element type `T` and number of dimensions `N` may be specified:

```julia
convert(ResizableArray{T}, A)
ResizableArray{T}(A)
convert(ResizableArray{T,N}, A)
ResizableArray{T,N}(A)
```

`N` must match `ndims(A)` but `T` may be different from `eltype(A)`.

When using the [`convert`](@ref) or the `ResizableArray` methods to convert an
array into a resizable array, the buffer for backing storage is always an
instance of `Vector{T}`.


## Custom storage

The default storage of the elements of a resizable array is provided by a
regular Julia vector.  To use an object `buf` to store the elements of a
resizable array, use one of the following:

```julia
A = ResizableArray(buf, dims)
A = ResizableArray{T}(buf, dims)
A = ResizableArray{T,N}(buf, dims)
```

The buffer `buf` must store its elements contiguously using linear indexing
style with 1-based indices and have element type `T`, that is
`IndexStyle(typeof(buf))` and `eltype(buf)` must yield `IndexLinear()` and `T`
respectively.  The methods, `IndexStyle`, `eltype`, `length`, `getindex` and
`setindex!` must be applicable for the type of `buf`.  If the method `resize!`
is applicable for `buf`, the number of elements of `A` can be augmented;
otherwise the maximum number of elements of `A` is `length(buf)`.

!!! warning
    When explictely providing a resizable buffer `buf` for backing the
    storage of a resizable array `A`, you have the responsibility to make
    sure that the same buffer is not resized elsewhere.  Otherwise a
    segmentation fault may occur because `A` might assume a wrong buffer
    size.  To avoid this, the best is to make sure that only `A` owns `buf`
    and only `A` manages its size.  In the current implementation, the size
    of the internal buffer is never reduced so the same buffer may be
    safely shared by different resizable arrays.

"""
mutable struct ResizableArray{T,N,B} <: DenseArray{T,N}
    len::Int
    dims::NTuple{N,Int}
    vals::B
    # Inner constructor for provided storage buffer.
    function ResizableArray{T,N}(buf::B,
                                 dims::NTuple{N,Int}) where {T,N,B}
        eltype(B) === T || error("buffer has a different element type")
        IndexStyle(B) === IndexLinear() ||
            error("buffer must have linear indexing style")
        checkdimensions(dims)
        len = prod(dims)
        length(buf) ≥ len || error("buffer is too small")
        return new{T,N,B}(len, dims, buf)
    end
    # Inner constructor using regular Julia's vector to store elements.
    function ResizableArray{T,N}(::UndefInitializer,
                                 dims::NTuple{N,Int}) where {T,N}
        checkdimensions(dims)
        len = prod(dims)
        buf = Vector{T}(undef, len)
        return new{T,N,Vector{T}}(len, dims, buf)
    end

end

ResizableArray(arg, dims::Integer...) =
    ResizableArray(arg, dims)
ResizableArray(arg, dims::Tuple{Vararg{Integer}}) =
    ResizableArray(arg, map(Int, dims))
ResizableArray(buf::B, dims::NTuple{N,Int}) where {N,B} =
    ResizableArray{eltype(B),N}(buf, dims)

ResizableArray{T}(arg, dims::Integer...) where {T} =
    ResizableArray{T}(arg, dims)
ResizableArray{T}(arg, dims::Tuple{Vararg{Integer}}) where {T} =
    ResizableArray{T}(arg, map(Int, dims))
ResizableArray{T}(arg, dims::NTuple{N,Int}) where {T,N} =
    ResizableArray{T,N}(arg, dims)

ResizableArray{T,N}(arg, dims::Integer...) where {T,N} =
    ResizableArray{T,N}(arg, dims)
ResizableArray{T,N}(arg, dims::Tuple{Vararg{Integer}}) where {T,N} =
    ResizableArray{T,N}(arg, map(Int, dims))
ResizableArray{T,N}(arg, dims::Tuple{Vararg{Int}}) where {T,N} =
    error("mismatching number of dimensions")

ResizableArray{T,N,Vector{T}}(A::AbstractArray{<:Any,N}) where {T,N} =
    copyto!(ResizableArray{T,N}(undef, size(A)), A)
ResizableArray{T,N}(A::AbstractArray{<:Any,N}) where {T,N} =
    copyto!(ResizableArray{T,N}(undef, size(A)), A)
ResizableArray{T}(A::AbstractArray) where {T} =
    copyto!(ResizableArray{T}(undef, size(A)), A)
ResizableArray(A::AbstractArray{T}) where {T} =
    copyto!(ResizableArray{T}(undef, size(A)), A)

Base.convert(::Type{ResizableArray{T,N}}, A::ResizableArray{T,N}) where {T,N} = A
Base.convert(::Type{ResizableArray{T}}, A::ResizableArray{T}) where {T} = A
Base.convert(::Type{ResizableArray}, A::ResizableArray) = A

Base.convert(::Type{ResizableArray{T,N,Vector{T}}}, A::AbstractArray{<:Any,N}) where {T,N} =
    ResizableArray{T,N}(A)
Base.convert(::Type{ResizableArray{T,N}}, A::AbstractArray{<:Any,N}) where {T,N} =
    ResizableArray{T,N}(A)
Base.convert(::Type{ResizableArray{T}}, A::AbstractArray) where {T} =
    ResizableArray{T}(A)
Base.convert(::Type{ResizableArray}, A::AbstractArray{T}) where {T} =
    ResizableArray(A)

"""
```julia
ResizableVector{T}
```

Supertype for one-dimensional resizable arrays with elements of type `T`.
Alias for [`ResizableArray{T,1}`](@ref).

"""
const ResizableVector{T,B} = ResizableArray{T,1,B}

"""
```julia
ResizableMatrix{T}
```

Supertype for two-dimensional resizable arrays with elements of type `T`.
Alias for [`ResizableArray{T,2}`](@ref).

"""
const ResizableMatrix{T,B} = ResizableArray{T,2,B}

"""
```julia
checkdimension(Bool, dim) -> boolean
```

yields whether `dim` is a valid dimension length (that is a nonnegative
integer).

"""
@inline checkdimension(::Type{Bool}, dim::Integer) = (dim ≥ 0)
@inline checkdimension(::Type{Bool}, dim) = false

"""
```julia
checkdimensions(Bool, dims) -> boolean
```

yields whether `dims` is a valid list of dimensions.

```julia
checkdimensions(dims)
```
throws an error if `dims` is not a valid list of dimensions.

"""
@inline checkdimensions(::Type{Bool}, dims::Tuple) =
    checkdimension(Bool, dims[1]) & checkdimensions(Bool, tail(dims))
@inline checkdimensions(::Type{Bool}, ::Tuple{}) = true
@inline checkdimensions(dims::Tuple) =
    checkdimensions(Bool, dims) || throw_invalid_dimensions()

@noinline throw_invalid_dimensions() =
    error("invalid dimension(s)")

"""
```julia
isgrowable(x) -> boolean
```

yields whether `x` is a growable object, that is its size can be augmented.

"""
isgrowable(A::ResizableArray) = isgrowable(A.vals)
isgrowable(::Vector) = true
isgrowable(::Any) = false

"""
```julia
maxlength(A)
```

yields the maximum number of elements which can be stored in resizable
array `A` without resizing its internal buffer.

See also: [`ResizableArray`](@ref).

"""
maxlength(A::ResizableArray) = length(A.vals)

Base.eltype(::Type{<:ResizableArray{T}}) where {T} = T
Base.ndims(::ResizableArray{T,N}) where {T,N} = N
Base.length(A::ResizableArray) = A.len
Base.size(A::ResizableArray) = A.dims
Base.size(A::ResizableArray{T,N}, d::Integer) where {T,N} =
    (d > N ? 1 : d ≥ 1 ? A.dims[d] : error("out of range dimension"))
Base.axes(A::ResizableArray) = map(OneTo, A.dims)
Base.axes(A::ResizableArray, d::Integer) = Base.OneTo(size(A, d))
@inline Base.axes1(A::ResizableArray{<:Any,0}) = OneTo(1)
@inline Base.axes1(A::ResizableArray) = OneTo(A.dims[1])
Base.IndexStyle(::Type{<:ResizableArray}) = IndexLinear()

Base.:(==)(::ResizableArray, ::AbstractArray) = false

Base.:(==)(A::ResizableVector{<:Any}, B::ResizableVector{<:Any}) =
    (length(A) == length(B) && _same_elements(A.vals, B.vals, length(A)))

Base.:(==)(A::ResizableArray{<:Any,N}, B::ResizableArray{<:Any,N}) where {N} =
    (size(A) == size(B) && _same_elements(A.vals, B.vals, length(A)))

Base.:(==)(A::ResizableVector{<:Any}, B::Vector{<:Any}) =
    (length(A) == length(B) && _same_elements(A.vals, B, length(A)))
Base.:(==)(A::Vector{<:Any}, B::ResizableVector{<:Any}) =
    (length(A) == length(B) && _same_elements(A, B.vals, length(A)))

Base.:(==)(A::ResizableArray{<:Any,N}, B::Array{<:Any,N}) where {N} =
    (size(A) == size(B) && _same_elements(A.vals, B, length(A)))
Base.:(==)(A::Array{<:Any,N}, B::ResizableArray{<:Any,N}) where {N} =
    (size(A) == size(B) && _same_elements(A, B.vals, length(A)))

Base.:(==)(A::ResizableArray{<:Any,N}, B::AbstractArray{<:Any,N}) where {N} =
    (axes(A) == axes(B) && _same_elements(A.vals, B, length(A)))
Base.:(==)(A::AbstractArray{<:Any,N}, B::ResizableArray{<:Any,N}) where {N} =
    (axes(A) == axes(B) && _same_elements(A, B.vals, length(A)))

# Yields whether the `n` first elements of `A` and `B` are identical.  This
# method is unsafe as it assumes that `A` and `B` have at least `n` elements.
_same_elements(A, B, n::Integer) =
    _same_elements(IndexStyle(A), A, IndexStyle(B), B, n)

function _same_elements(::IndexLinear, A, ::IndexLinear, B, n::Integer)
    @inbounds for i in 1:n
        A[i] == B[i] || return false
    end
    return true
end

function _same_elements(::IndexLinear, A, ::IndexStyle, B, n::Integer)
    i = 0
    @inbounds for j in eachindex(B)
        (i += 1) ≤ n || break
        A[i] == B[j] || return false
    end
    return (i > n)
end

function _same_elements(::IndexStyle, A, ::IndexLinear, B, n::Integer)
    j = 0
    @inbounds for i in eachindex(A)
        (j += 1) ≤ n || break
        A[i] == B[j] || return false
    end
    return (j > n)
end

function _same_elements(::IndexStyle, A, ::IndexStyle, B, n::Integer)
    # this case should never occur
    j = 0
    @inbounds for i in eachindex(A,B)
        (j += 1) ≤ n || break
        A[i] == B[i] || return false
    end
    return (j > n)
end

Base.resize!(A::ResizableArray, dims::Integer...) = resize!(A, dims)
Base.resize!(A::ResizableArray{T,N}, dims::NTuple{N,Integer}) where {T,N} =
    resize!(A, map(Int, dims))
function Base.resize!(A::ResizableArray{T,N}, dims::NTuple{N,Int}) where {T,N}
    if dims != size(A)
        checkdimensions(dims)
        newlen = prod(dims)
        newlen > length(A.vals) && resize!(A.vals, newlen)
        A.dims = dims
        A.len = newlen
    end
    return A
end
Base.resize!(A::ResizableArray, dims::Tuple{Vararg{Int}}) =
    error("changing the number of dimensions is not allowed")

@inline Base.getindex(A::ResizableArray, i::Int) =
    (@boundscheck checkbounds(A, i);
     @inbounds r = getindex(A.vals, i);
     return r)

@inline Base.setindex!(A::ResizableArray, x, i::Int) =
    (@boundscheck checkbounds(A, i);
     @inbounds r = setindex!(A.vals, x, i);
     return r)

@inline Base.checkbounds(A::ResizableArray, i::Int) =
    1 ≤ i ≤ length(A) || throw_boundserror(A, i)

Base.copyto!(dst::ResizableArray{T}, src::Array{T}) where {T} =
    copyto!(dst, 1, src, 1, length(src))
Base.copyto!(dst::Array{T}, src::ResizableArray{T}) where {T} =
    copyto!(dst, 1, src, 1, length(src))
Base.copyto!(dst::ResizableArray{T}, src::ResizableArray{T}) where {T} =
    copyto!(dst, 1, src, 1, length(src))

function Base.copyto!(dst::ResizableArray{T}, doff::Integer,
                      src::Array{T}, soff::Integer, n::Integer) where {T}
    if n != 0
        checkcopyto(length(dst), doff, length(src), soff, n)
        unsafe_copyto!(dst.vals, doff, src, soff, n)
    end
    return dst
end

function Base.copyto!(dst::Array{T}, doff::Integer,
                      src::ResizableArray{T}, soff::Integer,
                      n::Integer) where {T}
    if n != 0
        checkcopyto(length(dst), doff, length(src), soff, n)
        unsafe_copyto!(dst, doff, src.vals, soff, n)
    end
    return dst
end

function Base.copyto!(dst::ResizableArray{T}, doff::Integer,
                      src::ResizableArray{T}, soff::Integer,
                      n::Integer) where {T}
    if n != 0
        checkcopyto(length(dst), doff, length(src), soff, n)
        unsafe_copyto!(dst.vals, doff, src.vals, soff, n)
    end
    return dst
end

@inline function checkcopyto(dlen::Integer, doff::Integer,
                             slen::Integer, soff::Integer, n::Integer)
     @noinline throw_invalid_length() =
        throw(ArgumentError("number of elements to copy must be nonnegative"))
    n ≥ 0 || throw_invalid_length()
    (doff > 0 && doff - 1 + n ≤ dlen &&
     soff > 0 && soff - 1 + n ≤ slen) || throw(BoundsError())
end

Base.unsafe_convert(::Type{Ptr{T}}, A::ResizableArray{T}) where {T} =
    Base.unsafe_convert(Ptr{T}, A.vals)

Base.pointer(A::ResizableArray, i::Integer) = pointer(A.vals, i)

end # module