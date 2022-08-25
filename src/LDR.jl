@doc raw"""
    LDR{T} <: Factorization{T}

Represents the matrix factorization ``A P = L D R`` for a square matrix ``A,`` which may equivalently be
written as ``A = (L D R) P^{-1} = (L D R) P^T``.

In the above ``L`` is a unitary matrix, ``D`` is a diagonal matrix of strictly positive real numbers,
and ``R`` is an upper triangular matrix. Lastly, ``P`` is a permutation matrix, for which ``P^{-1}=P^T``.

This factorization is based on a column-pivoted QR decomposition ``A P = Q R,`` such that
```math
\begin{align*}
L &= Q \\
D &= \vert \textrm{diag}(R) \vert \\
R &= \vert \textrm{diag}(R) \vert^{-1} R \\
P &= P.
\end{align*}
```
"""
struct LDR{T<:Number, E<:Real} <: Factorization{T}

    "The left unitary matrix ``L``."
    L::Matrix{T}

    "Vector representing diagonal matrix ``D``."
    d::Vector{E}

    "The right upper triangular matrix ``R``."
    R::Matrix{T}

    "Permutation vector to represent permuation matrix ``P^T``."
    pᵀ::Vector{Int}

    "Stores the elementary reflectors for calculatng ``AP = QR`` decomposition."
    τ::Vector{T}

    "Workspace for calculating QR decomposition using LAPACK without allocations."
    ws::QRWorkspace{T, E}

    "A matrix for temporarily storing intermediate results so as to avoid dynamic memory allocations."
    M_tmp::Matrix{T}

    "A vector for temporarily storing intermediate results so as to avoid dynamic memory allocations."
    p_tmp::Vector{Int}
end


@doc raw"""
    ldr(A::AbstractMatrix)

Calculate and return the LDR decomposition for the matrix `A`.
"""
function ldr(A::AbstractMatrix{T})::LDR{T} where {T}

    # make sure A is a square matrix
    @assert size(A,1) == size(A,2)

    # matrix dimension
    n = size(A,1)

    # allocate relevant arrays
    L =  zeros(T,n,n)
    R  = zeros(T,n,n)
    if T <: Complex
        E = T.types[1]
        d = zeros(E,n)
    else
        d = zeros(T,n)
    end

    # allocate workspace for QR decomposition
    copyto!(L,A)
    ws = QRWorkspace(L)
    pᵀ = ws.jpvt
    τ  = ws.τ

    # allocate arrays for storing intermediate results to avoid
    # dynamic memory allocations
    M_tmp = zeros(T,n,n)
    p_tmp = zeros(Int,n)

    # instantiate LDR decomposition
    F = LDR(L,d,R,pᵀ,τ,ws,M_tmp,p_tmp)

    # calculate LDR decomposition
    ldr!(F, A)
    
    return F
end


@doc raw"""
    ldr(F::LDR)

Return a new LDR factorization that is a copy of `F`.
"""
function ldr(F::LDR)

    F′ = ldr(F.L)
    copyto!(F′, F)

    return F′
end


@doc raw"""
    ldr!(F::LDR, A::AbstractMatrix)

Calculate the LDR decomposition `F` for the matrix `A`.
"""
function ldr!(F::LDR{T}, A::AbstractMatrix{T}) where {T}

    @assert size(F) == size(A)

    copyto!(F.L, A)
    ldr!(F)

    return nothing
end


@doc raw"""
    ldr!(F::LDR)

Re-calculate the LDR factorization `F` in-place based on the current contents
of the matrix `F.L`.
"""
function ldr!(F::LDR)

    (; L, d, R, ws) = F

    # calclate QR decomposition
    geqp3!(L, ws)

    # extract upper triangular matrix R
    R′ = UpperTriangular(L)
    copyto!(R, R′)

    # set D = Diag(R), represented by vector d
    @inbounds for i in 1:size(L,1)
        d[i] = abs(R[i,i])
    end

    # calculate R = D⁻¹⋅R
    ldiv_D!(d, R)

    # construct L (same as Q) matrix
    orgqr!(L, ws)

    return nothing
end