mutable struct BitBuffer{B} <: AbstractVector{UInt}
    len::Int
    buffer::Vector{UInt8}

    function BitBuffer{B}(len, buffer) where B
        if !(B isa Int)
            throw(TypeError(:BitBuffer, Int, typeof(B)))
        end
        if !((B > 0) & (B < 8*sizeof(UInt) - 6))
            throw(ArgumentError("B must be in 1:$(8*sizeof(UInt) - 7)"))
        end
        new(len, buffer)
    end
end

bitsize(n::BitBuffer{B}) where B = B
bytes(n, b::Int) = cld((n-1)*b, 8) + sizeof(UInt)
BitBuffer{B}(::UndefInitializer, n) where B = BitBuffer{B}(n, Vector{UInt8}(undef, bytes(n, B)))
BitBuffer{B}(n) where B = BitBuffer{B}(n, zeros(UInt8, bytes(n, B)))
Base.copy(x::BitBuffer) = typeof(x)(x.len, copy(x.buffer))
Base.size(x::BitBuffer) = (x.len,)
Base.lastindex(x::BitBuffer) = x.len
Base.IndexStyle(x::BitBuffer) = IndexLinear()
@inline Base.checkbounds(::Type{Bool}, x::BitBuffer, i) = (i ≥ firstindex(x)) & (i ≤ lastindex(x))


function byteindex(ui::Unsigned, x::BitBuffer)
    bits = unsigned((ui-1) * bitsize(x))
    return Core.Intrinsics.udiv_int(bits, UInt(8)) + 1
end

function bitoffset(ui::Unsigned, x::BitBuffer)
    bits = unsigned((ui-1) * bitsize(x))
    return Core.Intrinsics.urem_int(bits, UInt(8))
end

bitmask(x::BitBuffer) = (UInt(1) << bitsize(x)) - 1

@inline function loadbits(x::BitBuffer, i::Unsigned)
    buffer = x.buffer
    GC.@preserve buffer begin
        bits = unsafe_load(Ptr{UInt}(pointer(buffer, i)))
    end
    return bits
end

@inline function unsafe_getindex(x::BitBuffer, i)
    index = byteindex(unsigned(i), x)
    bits = loadbits(x, index)
    offset = bitoffset(unsigned(i), x)
    return (bits >>> offset) & bitmask(x)
end

function Base.getindex(x::BitBuffer, i::Int)
    @boundscheck checkbounds(x, i)
    unsafe_getindex(x, i)
end

function unsafe_setindex!(x::BitBuffer, v::UInt, i)
    index = byteindex(unsigned(i), x)
    bits = loadbits(x, index)
    offset = bitoffset(unsigned(i), x)
    mask = ~(bitmask(x) << offset)
    bits &= mask
    bits |= v << offset
    buffer = x.buffer
    GC.@preserve buffer begin
        unsafe_store!(Ptr{UInt}(pointer(buffer, index)), bits)
    end
end

@noinline function throw_indexerr(::Type{BitBuffer{B}}, v::Integer) where B
    throw(ArgumentError("$v has more bits than maximum $B"))
end

function Base.setindex!(x::BitBuffer, v::Integer, i::Int)
    @boundscheck checkbounds(x, i)
    vu = convert(UInt, unsigned(v))
    vu > bitmask(x) && throw_indexerr(typeof(x), v)
    unsafe_setindex!(x, vu, i)
end
