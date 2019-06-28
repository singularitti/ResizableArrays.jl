module ResizableArraysTests

using Test
using ResizableArrays
using ResizableArrays: checkdimension, checkdimensions

@testset "Basic methods" begin
    @testset "Utilities" begin
        @test checkdimension(Bool, π) == false
        @test checkdimensions(Bool, ()) == true
        @test checkdimensions(Bool, (1,)) == true
        @test checkdimensions(Bool, (1,2,0)) == true
        @test checkdimensions(Bool, (1,-2,0)) == false
        @test_throws ErrorException checkdimensions((1,-2,0))
        @test isgrowable(π) == false
        @test isgrowable((1,2,3)) == false
        @test isgrowable([1,2,3]) == true
    end
    @testset "Dimensions: $dims" for dims in ((), (3,), (2,3), (2,3,4))
        N = length(dims)
        if N > 0
            A = rand(dims...)
            T = eltype(A)
        else
            T = Float64
            A = Array{T}(undef, dims)
            A[1] = rand(dims...)
        end
        B = ResizableArray{T}(undef, size(A))
        @test IndexStyle(typeof(B)) == IndexLinear()
        @test eltype(B) == eltype(A)
        @test ndims(B) == ndims(A) == N
        @test size(B) == size(A)
        @test all(d -> size(B,d) == size(A,d), 1:(N+2))
        @test axes(B) == axes(A)
        @test length(B) == length(A) == prod(dims)
        @test maxlength(B) == length(B)
        @test all(d -> axes(B,d) == axes(A,d), 1:(N+2))
        copyto!(B, A)
        @test all(i -> A[i] == B[i], 1:length(A))
        @test all(i -> A[i] == B[i], CartesianIndices(A))
        @test all(i -> A[i] == B.vals[i], 1:length(A))
        @test A == B
        for i in eachindex(B)
            B[i] = rand()
        end
        copyto!(A, B)
        @test A == B
        if N > 0
            tmpdims = collect(size(B))
            tmpdims[end] += 1
            resize!(B, tmpdims...)
            @test maxlength(B) == length(B) == prod(tmpdims)
            @test A != B
            @test all(i -> B[i] == A[i], 1:length(A))
            dims16b = map(Int16, size(A))
        end
        @test_throws BoundsError B[0]
        @test_throws BoundsError B[length(B) + 1]
        @test_throws ErrorException resize!(B, (dims..., 5))

        # Check various constructors and custom buffer (do not splat dimensions if N=0).
        buf = Vector{T}(undef, length(A))
        for arg in (undef, buf)
            C = copyto!(ResizableArray{T}(arg, dims), A)
            @test eltype(C) == eltype(A) && C == A
            C = copyto!(ResizableArray{T,N}(arg, dims), A)
            @test eltype(C) == eltype(A) && C == A
            if N > 0
                C = copyto!(ResizableArray{T}(arg, dims...), A)
                @test eltype(C) == eltype(A) && C == A
                C = copyto!(ResizableArray{T,N}(arg, dims...), A)
                @test eltype(C) == eltype(A) && C == A
                C = copyto!(ResizableArray{T}(arg, dims16b), A)
                @test eltype(C) == eltype(A) && C == A
                C = copyto!(ResizableArray{T}(arg, dims16b...), A)
                @test eltype(C) == eltype(A) && C == A
                C = copyto!(ResizableArray{T,N}(arg, dims16b), A)
                @test eltype(C) == eltype(A) && C == A
                C = copyto!(ResizableArray{T,N}(arg, dims16b...), A)
                @test eltype(C) == eltype(A) && C == A
            end
        end

        # Use constructor to convert array.
        C = ResizableArray(A)
        @test eltype(C) == eltype(A) && C == A
        C = ResizableArray{T}(A)
        @test eltype(C) == eltype(A) && C == A
        C = ResizableArray{T,N}(A)
        @test eltype(C) == eltype(A) && C == A

        # Use convert to convert array.
        C = convert(ResizableArray, A)
        @test eltype(C) == eltype(A) && C == A
        C = convert(ResizableArray{T}, A)
        @test eltype(C) == eltype(A) && C == A
        C = convert(ResizableArray{T,N}, A)
        @test eltype(C) == eltype(A) && C == A
    end
end

end # module