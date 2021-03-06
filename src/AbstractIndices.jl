"""
    AbstractIndices{I} <: AbstractDictionary{I, I}

Abstract type for the unique keys of an `AbstractDictionary`. It is itself an `AbstractDictionary` for
which `getindex` is idempotent, such that `indices[i] = i`. (This is a generalization of
`Base.Slice`).

At minimum, an `AbstractIndices{I}` must implement:

 * The `iterate` protocol, returning unique values of type `I`.
 * `in`, such that `in(i, indices)` implies there is an element of `indices` which `isequal` to `i`.
 * Either `length`, or override `IteratorSize` to `SizeUnknown`.

While an `AbstractIndices` object is a dictionary, the value corresponding to each index is
fixed, so `issettable(::AbstractIndices) = false` and `setindex!` is never defined.

If arbitrary indices can be added or removed from the set, implement:

* `isinsertable(::AbstractIndices)` (returning `true`)
* `insert!(indices::AbstractIndices{I}, ::I}` (returning `indices`)
* `delete!(indices::AbstractIndices{I}, ::I}` (returning `indices`)
"""
abstract type AbstractIndices{I} <: AbstractDictionary{I, I}; end

@inline function Base.getindex(indices::AbstractIndices{I}, i::I) where {I}
    @boundscheck checkindex(indices, i)
    return i
end

function Base.setindex!(i::AbstractIndices{I}, ::I, ::I) where {I}
    error("Indices are not settable: $(typeof(i))")
end

function Base.isassigned(indices::AbstractIndices{I}, i::I) where {I}
    return i in indices
end

Base.keys(i::AbstractIndices) = i

@inline function Base.iterate(inds::AbstractIndices, s...)
    if istokenizable(inds)
        tmp = iteratetoken(keys(inds), s...)
        tmp === nothing && return nothing
        (t, s2) = tmp
        return (gettokenvalue(inds, t), s2)
    else
        error("All AbstractIndices must define `iterate`: $(typeof(inds))")
    end
end

function Base.in(i::I, indices::AbstractIndices{I}) where I
    if !istokenizable(indices)
        # A fallback definition based on iteration would be rediculously slow. There
        # shouldn't be many `AbstractIndex` types that rely on iteration for this.
        error("All AbstractIndices must define `in`: $(typeof(indices))")
    end

    return gettoken(indices, i)[1]
end

function Base.in(i, indices::AbstractIndices{I}) where I
    return convert(I, i) in indices
end

# Match the default setting from Base - the majority of containers will know their size
Base.IteratorSize(indices::AbstractIndices) = Base.HasLength() 

function Base.length(indices::AbstractIndices)
    if Base.IteratorSize(indices) isa Base.SizeUnknown
        out = 0
        for _ in tokens(indices)
            out += 1
        end
        return out
    end

    error("All AbstractIndices must define `length` or else have `IteratorSize` of `SizeUnknown`: $(typeof(indices))")
end

Base.unique(i::AbstractIndices) = i

struct IndexError <: Exception
	msg::String
end

function Base.checkindex(indices::AbstractIndices{I}, i::I) where {I}
	if i ∉ indices
		throw(IndexError("Index $i not found in indices $indices"))
	end
end
Base.checkindex(indices::AbstractIndices{I}, i) where {I} = checkindex(indices, convert(I, i))

function checkindices(indices::AbstractIndices, inds)
    if !(inds ⊆ indices)
        throw(IndexError("Indices $inds are not a subset of $indices"))
    end
end

# Indices are isequal if they iterate in the same order
function Base.isequal(i1::AbstractIndices, i2::AbstractIndices)
    if sharetokens(i1, i2)
        return true
    end

    if length(i1) != length(i2)
        return false
    end

    for (j1, j2) in zip(i1, i2)
        if !isequal(j1, j2)
            return false
        end
    end

    return true
end

# Use `issetequal` semantics
function Base.:(==)(i1::AbstractIndices, i2::AbstractIndices)
    if sharetokens(i1, i2)
        return true
    end

    if length(i1) != length(i2)
        return false
    end

    for i in i1
        if !(i in i2)
            return false
        end
    end

    return true
end

# Lexical ordering based on iteration
function Base.isless(inds1::AbstractIndices, inds2::AbstractIndices)
    if sharetokens(inds1, inds2)
        return false # they are isequal
    end

    # We want to iterate... until one is longer than the other (no `zip`)
    tmp1 = iterate(inds1)
    tmp2 = iterate(inds2)
    while tmp1 !== nothing
        if tmp2 === nothing
            return false # shorter collections are isless in lexical ordering
        end
        (i1, s1) = tmp1
        (i2, s2) = tmp2
        !isequal(i1, i2)
        c = cmp(i1, i2)
        
        if c == -1
            return true
        elseif c == 1
            return false
        end

        tmp1 = iterate(inds1, s1)
        tmp2 = iterate(inds2, s2)
    end
    return tmp2 !== nothing # shorter collections are isless in lexical ordering, otherwise isequal
end

function Base.cmp(inds1::AbstractIndices, inds2::AbstractIndices)
    if sharetokens(inds1, inds2)
        return 0 # they are isequal
    end

    # We want to iterate... until one is longer than the other (no `zip`)
    tmp1 = iterate(inds1)
    tmp2 = iterate(inds2)
    while tmp1 !== nothing
        if tmp2 === nothing
            return 1 # shorter collections are isless in lexical ordering
        end
        (i1, s1) = tmp1
        (i2, s2) = tmp2
        !isequal(i1, i2)
        c = cmp(i1, i2)
        
        if c == -1
            return -1
        elseif c == 1
            return 1
        end

        tmp1 = iterate(inds1, s1)
        tmp2 = iterate(inds2, s2)
    end
    if tmp2 === nothing
        return 0
    else
        return -1 # shorter collections are isless in lexical ordering
    end
end

## Hashing - matches the dictionary case (matching keys and matching values)
function Base.hash(inds::AbstractIndices, h::UInt)
    h1 = h
    for i in inds
        h1 = hash(i, h1)
    end
    
    return hash(hash(UInt === UInt64 ? 0x8955a87bc313a509 : 0xa9cff5d1, h1), h1)
end
