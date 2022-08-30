@doc raw"""
    size(F::LDR)
    size(F::LDR, dims)

Return the size of the LDR decomposition `F`.
"""
size(F::LDR)       = size(F.L)
size(F::LDR, dims) = size(F.L, dims)


@doc raw"""
    copyto!(A::AbstractMatrix, F::LDR)

Copy the matrix represented by the LDR decomposition `F` into the matrix `A`.
"""
function copyto!(A::AbstractMatrix{T}, F::LDR{T}) where {T}

    @assert size(A) == size(F)

    (; L, pᵀ) = F
    d = F.d
    R = UpperTriangular(F.R)
    A′ = F.M_tmp

    # A = L⋅D⋅R⋅Pᵀ
    mul_D!(A′, L, d) # A = L⋅D
    rmul!(A′, R) # A = (L⋅D)⋅R
    mul_P!(A, A′, pᵀ) # A = (L⋅D⋅R)⋅Pᵀ

    return nothing
end


@doc raw"""
    copyto!(F::LDR, A)

Copy the matrix `A` to the LDR factorization `F`, calculating the
LDR factorization to represent `A`.
"""
copyto!(F::LDR, A::AbstractMatrix) = ldr!(F,A)
copyto!(F::LDR, I::UniformScaling) = ldr!(F,I)


@doc raw"""
    copyto!(F′::LDR{T}, F::LDR{T}) where {T}

Copy `F` LDR factorization to `F′`.
"""
function copyto!(F′::LDR{T,E}, F::LDR{T,E}) where {T,E}

    copyto!(F′.L,  F.L)
    copyto!(F′.d,  F.d)
    copyto!(F′.R,  F.R)
    copyto!(F′.pᵀ, F.pᵀ)

    return nothing
end


@doc raw"""
    lmul!(B::AbstractMatrix, F::LDR; tmp=similar(B))

Calculate the numerically stable product ``A = B A,`` where the matrix ``A`` is
represented by the LDR factorization `F`, updating `F` in-place to represent the product ``B A.``

# Algorithm

Given a matrix ``A`` represented by an LDR factorization, update the LDR factorization to reflect
the matrix product ``A=BA`` using the procedure
```math
\begin{align*}
A = & BA\\
  = & \overset{L_{1}D_{1}R_{1}P_{1}^{T}}{\overbrace{B[L_{0}D_{0}}}R_{0}P_{0}^{T}]\\
  = & [\overset{L_{2}}{\overbrace{L_{1}^{\phantom{\dagger}}}}\,\overset{D_{2}}{\overbrace{D_{1}^{\phantom{\dagger}}}}\,\overset{R_{2}}{\overbrace{R_{1}P_{1}^{T}]R_{0}}}\,\overset{P_{2}^{T}}{\overbrace{P_{0}^{T}}}\\
  = & L_{2}D_{2}R_{2}P_{2}^{T}.
\end{align*}
```
"""
function lmul!(B::AbstractMatrix{T}, F::LDR{T}; tmp::AbstractMatrix{T}=similar(B)) where {T}

    # B⋅L
    mul!(F.M_tmp, B, F.L)

    # B⋅L⋅D
    mul_D!(F.L, F.M_tmp, F.d)

    # store current R and pᵀ arrays
    pᵀ_prev = F.p_tmp
    R_prev = F.M_tmp
    copyto!(R_prev, F.R)
    copyto!(pᵀ_prev, F.pᵀ)

    # calculate new L′⋅D′⋅R′⋅P′ᵀ decomposition
    ldr!(F)

    # R′ = R′⋅P′ᵀ⋅R
    mul_P!(tmp, F.R, F.pᵀ) # R′⋅P′ᵀ
    mul!(F.R, tmp, R_prev) # R′⋅P′ᵀ⋅R

    # P′ᵀ = Pᵀ
    copyto!(F.pᵀ, pᵀ_prev)

    return nothing
end


@doc raw"""
    lmul!(F₂::LDR{T}, F₁::LDR{T}) where {T}

Calculate the matrix product ``C = B C,`` represented by the LDR factorization `F₂` and `F₁`
respectively, where `F₁` is updated in-place.

# Algorithm

Calculate the numerically stable matrix product ``C = B C`` using the procedure
```math
\begin{align*}
C = & B C\\
    = & [L_{b}D_{b}\overset{M}{\overbrace{R_{b}P_{b}^{T}][L_{c}}}D_{c}R_{c}P_{c}^{T}]\\
    = & L_{b}D_{b}\overset{M'}{\overbrace{MD_{c}}}R_{c}P_{c}^{T}\\
    = & L_{b}\overset{M''}{\overbrace{D_{b}M'}}R_{c}P_{c}^{T}\\
    = & \overset{L_{0}D_{0}R_{0}P_{0}^{T}}{L_{b}\overbrace{M''}R_{c}}P_{c}^{T}\\
    = & \overset{L_{c}}{\overbrace{L_{c}L_{0}^{\phantom{T}}}}\,\overset{D_{c}}{\overbrace{D_{0}^{\phantom{T}}}}\,\overset{R_{c}}{\overbrace{R_{0}P_{0}^{T}R_{c}}}\,\overset{P_{c}^{T}}{\overbrace{P_{c}^{T}}}\\
    = & L_{c}D_{c}R_{c}P_{c}^{T}.
\end{align*}
```
"""
function lmul!(F₂::LDR{T}, F₁::LDR{T}) where {T}

    # store R₁ and P₁ᵀ
    copyto!(F₁.M_tmp, F₁.R)
    R₁ = UpperTriangular(F₁.M_tmp)
    copyto!(F₁.p_tmp, F₁.pᵀ)
    p₁ᵀ = F₁.p_tmp

    # calculate R₂⋅P₂ᵀ⋅L₁
    mul_P!(F₁.L, F₂.pᵀ, F₁.L) # P₂ᵀ⋅L₁
    R₂ = UpperTriangular(F₂.R)
    lmul!(R₂, F₁.L)
 
    # calculate D₂⋅[R₂⋅P₂ᵀ⋅L₁]⋅D₁
    @inbounds @fastmath for i in eachindex(F₁.d)
        for j in eachindex(F₂.d)
            F₁.L[j,i] *= F₁.d[i] * F₂.d[j]
        end
    end

    # calculate LDR factorization L₃⋅D₃⋅R₃⋅P₃ᵀ = D₂⋅[R₂⋅P₂ᵀ⋅L₁]⋅D₁
    ldr!(F₁)
    F₃ = F₁

    # calcualte L₃ = L₂⋅L₃
    L₂L₃ = F₂.M_tmp
    mul!(L₂L₃, F₂.L, F₃.L)
    copyto!(F₃.L, L₂L₃)

    # calcualte R₃ = R₃⋅P₃ᵀ⋅R₁
    R₃P₃ᵀ = F₂.M_tmp
    mul_P!(R₃P₃ᵀ, F₃.R, F₃.pᵀ) # R₃⋅P₃ᵀ
    mul!(F₃.R, R₃P₃ᵀ, R₁) # R₃⋅P₃ᵀ⋅R₁

    # calculate P₃ᵀ = P₁ᵀ
    copyto!(F₃.pᵀ, p₁ᵀ)

    return nothing
end


@doc raw"""
    rmul!(F::LDR, B::AbstractMatrix; tmp=similar(B))

Calculate the numerically stable product ``A = A B,`` where the matrix ``A`` is
represented by the LDR factorization `F`, updating `F` in-place to represent the product ``A B.``

# Algorithm

Given a matrix ``A`` represented by an LDR factorization, update the LDR factorization to reflect
the matrix product ``A=AB`` using the procedure
```math
\begin{align*}
A = & AB\\
  = & [L_{0}\overset{L_{1}D_{1}R_{1}P_{1}^{T}}{\overbrace{D_{0}R_{0}P_{0}^{T}]B}}\\
  = & \overset{L_{2}}{\overbrace{L_{0}[L_{1}^{\phantom{T}}}}\,\overset{D_{2}}{\overbrace{D_{1}^{\phantom{T}}}}\,\overset{R_{2}}{\overbrace{R_{1}^{\phantom{T}}}}\,\overset{P_{2}^{T}}{\overbrace{P_{1}^{T}}}]\\
  = & L_{2}D_{2}R_{2}P_{2}^{T}.
\end{align*}
```
"""
function rmul!(F::LDR{T}, B::AbstractMatrix{T}; tmp::AbstractMatrix{T}=similar(B)) where {T}

    (; L, d, pᵀ, M_tmp) = F
    R = UpperTriangular(F.R)

    # P₀ᵀ⋅B
    mul_P!(tmp, pᵀ, B)

    # R₀⋅P₀ᵀ⋅B
    lmul!(R, tmp)

    # D₀⋅R₀⋅P₀ᵀ⋅B
    mul_D!(F.R, d, tmp)
    copyto!(tmp, L) # store L₀ for later use
    copyto!(L, F.R)

    # caluclate new LDR decmposition given by [L₁⋅D₁⋅R₁⋅P₁ᵀ] = (D₀⋅R₀⋅P₀ᵀ⋅B)
    ldr!(F)

    # update LDR decomposition such that L₁ = L₀⋅L₁
    mul!(M_tmp, tmp, L)
    copyto!(L, M_tmp)

    return nothing
end


@doc raw"""
    rmul!(F₂::LDR{T}, F₁::LDR{T}) where {T}

Calculate the matrix product ``B = B C,`` represented by the LDR factorization `F₂` and `F₁`
respectively, where `F₂` is updated in-place.

# Algorithm

Calculate the numerically stable matrix product ``B = B C`` using the procedure
```math
\begin{align*}
B = & B C\\
  = & [L_{b}D_{b}\overset{M}{\overbrace{R_{b}P_{b}^{T}][L_{c}}}D_{c}R_{c}P_{c}^{T}]\\
  = & L_{b}D_{b}\overset{M'}{\overbrace{MD_{c}}}R_{c}P_{c}^{T}\\
  = & L_{b}\overset{M''}{\overbrace{D_{b}M'}}R_{c}P_{c}^{T}\\
  = & \overset{L_{0}D_{0}R_{0}P_{0}^{T}}{L_{b}\overbrace{M''}R_{c}}P_{c}^{T}\\
  = & \overset{L_{b}}{\overbrace{L_{b}L_{0}^{\phantom{T}}}}\,\overset{D_{b}}{\overbrace{D_{0}^{\phantom{T}}}}\,\overset{R_{b}}{\overbrace{R_{0}P_{0}^{T}R_{c}}}\,\overset{P_{b}^{T}}{\overbrace{P_{c}^{T}}}\\
  = & L_{b}D_{b}R_{b}P_{b}^{T}.
\end{align*}
```
"""
function rmul!(F₂::LDR{T}, F₁::LDR{T}) where {T}

    # store L₂
    L₂ = F₂.M_tmp
    copyto!(L₂, F₂.L)

    # calculate R₂⋅P₂ᵀ⋅L₁
    mul_P!(F₂.L, F₂.pᵀ, F₁.L) # P₂ᵀ⋅L₁
    R₂ = UpperTriangular(F₂.R)
    lmul!(R₂, F₂.L)

    # calculate D₂⋅[R₂⋅P₂ᵀ⋅L₁]⋅D₁
    @inbounds @fastmath for i in eachindex(F₁.d)
        for j in eachindex(F₂.d)
            F₂.L[j,i] *= F₁.d[i] * F₂.d[j]
        end
    end

    # calculate LDR factorization L₃⋅D₃⋅R₃⋅P₃ᵀ = D₂⋅[R₂⋅P₂ᵀ⋅L₁]⋅D₁
    ldr!(F₂)
    F₃ = F₂

    # calcualte L₃ = L₂⋅L₃
    L₂L₃ = F₁.M_tmp
    mul!(L₂L₃, L₂, F₃.L)
    copyto!(F₃.L, L₂L₃)

    # calcualte R₃ = R₃⋅P₃ᵀ⋅R₁
    R₃P₃ᵀ = F₁.M_tmp
    mul_P!(R₃P₃ᵀ, F₃.R, F₃.pᵀ) # R₃⋅P₃ᵀ
    mul!(F₃.R, R₃P₃ᵀ, F₁.R) # R₃⋅P₃ᵀ⋅R₁

    # calculate P₃ᵀ = P₁ᵀ
    copyto!(F₃.pᵀ, F₁.pᵀ)

    return nothing
end


@doc raw"""
    mul!(A::AbstractMatrix, F::LDR, B::AbstractMatrix)

Calculate the matrix product ``A = M B,`` where the matrix ``M`` is represented
by the LDR factorization `F`.
"""
function mul!(A::AbstractMatrix{T}, F::LDR{T}, B::AbstractMatrix{T}) where {T}

    (; L, d, pᵀ, M_tmp) = F
    R = UpperTriangular(F.R)

    # calculate A = (L⋅D⋅R⋅Pᵀ)⋅B
    mul_P!(M_tmp, pᵀ, B)
    lmul!(R, M_tmp)
    lmul_D!(d, M_tmp)
    mul!(A, L, M_tmp)

    return nothing
end


@doc raw"""
    mul!(F′::LDR, B::AbstractMatrix, F::LDR)

Calculate the numerically stable product ``C = B A,`` where the matrices
``C`` and ``A`` are represented by the LDR decompositions `F′` and `F` respectively.

# Algorithm

Calculate the matrix product using the procedure
```math
\begin{align*}
C = & BA\\
  = & \overset{L_{1}D_{1}R_{1}P_{1}^{T}}{\overbrace{B[L_{0}D_{0}}}R_{0}P_{0}^{T}]\\
  = & [\overset{L_{2}}{\overbrace{L_{1}^{\phantom{\dagger}}}}\,\overset{D_{2}}{\overbrace{D_{1}^{\phantom{\dagger}}}}\,\overset{R_{2}}{\overbrace{R_{1}P_{1}^{T}]R_{0}}}\,\overset{P_{2}^{T}}{\overbrace{P_{0}^{T}}}\\
  = & L_{2}D_{2}R_{2}P_{2}^{T}.
\end{align*}
```
"""
function mul!(F′::LDR{T}, B::AbstractMatrix{T}, F::LDR{T}) where {T}

    L  = F.L
    d  = F.d
    R  = UpperTriangular(F.R)
    pᵀ = F.pᵀ

    L′  = F′.L
    R′  = UpperTriangular(F′.R)
    p′ᵀ = F′.pᵀ

    # calculate L′ = B⋅L⋅D
    mul_D!(F.M_tmp, L, d) # L⋅D
    mul!(L′, B, F.M_tmp) # B⋅(L⋅D)

    # update/calculate F′ = [L′⋅D′⋅R′⋅P′ᵀ] decomposition for (B⋅L⋅D)
    ldr!(F′)

    # calculate R′ = R′⋅P′ᵀ⋅R
    mul_P!(F′.M_tmp, p′ᵀ, R′) # (R′⋅P′ᵀ)
    mul!(F′.R, F′.M_tmp, R) # (R′⋅P′ᵀ)⋅R

    # set P′ᵀ = Pᵀ (P′ = P)
    copyto!(p′ᵀ, pᵀ)

    return nothing
end


@doc raw"""
    mul!(F′::LDR, F::LDR, B::AbstractMatrix)
    
Calculate the numerically stable product ``C = A B,`` where the matrices
``C`` and ``A`` are represented by the LDR decompositions `F′` and `F` respectively.

# Algorithm

Calculate the matrix product using the procedure
```math
\begin{align*}
C = & AB\\
  = & [L_{0}\overset{L_{1}D_{1}R_{1}P_{1}^{T}}{\overbrace{D_{0}R_{0}P_{0}^{T}]B}}\\
  = & \overset{L_{2}}{\overbrace{L_{0}[L_{1}^{\phantom{T}}}}\,\overset{D_{2}}{\overbrace{D_{1}^{\phantom{T}}}}\,\overset{R_{2}}{\overbrace{R_{1}^{\phantom{T}}}}\,\overset{P_{2}^{T}}{\overbrace{P_{1}^{T}}}]\\
  = & L_{2}D_{2}R_{2}P_{2}^{T}.
\end{align*}
```
"""
function mul!(F′::LDR{T}, F::LDR{T}, B::AbstractMatrix{T}) where {T}

    L  = F.L
    d  = F.d
    R  = UpperTriangular(F.R)
    pᵀ = F.pᵀ
    M  = F.M_tmp
    L′  = F′.L

    # calculate D⋅R⋅Pᵀ⋅B
    mul_P!(L′, pᵀ, B)
    lmul!(R, L′)
    lmul_D!(d, L′)

    # calculate L′⋅D′⋅R′⋅P′ᵀ = D⋅R⋅Pᵀ⋅B
    ldr!(F′)
    
    # calculate L′=L⋅L′
    mul!(M, L, L′)
    copyto!(L′, M)

    return nothing
end


@doc raw"""
    mul!(F₃::LDR, F₂::LDR, F₁::LDR)

Calculate the numerically stable product ``A = B C,`` where
each matrix is represented by the LDR decompositions `F₃`, `F₂` and `F₁` respectively.

# Algorithm

Calculate the numerically stable matrix product ``A = B C`` using the procedure
```math
\begin{align*}
A = & BC\\
  = & [L_{b}D_{b}\overset{M}{\overbrace{R_{b}P_{b}^{T}][L_{c}}}D_{c}R_{c}P_{c}^{T}]\\
  = & L_{b}D_{b}\overset{M'}{\overbrace{MD_{c}}}R_{c}P_{c}^{T}\\
  = & L_{b}\overset{M''}{\overbrace{D_{b}M'}}R_{c}P_{c}^{T}\\
  = & \overset{L_{0}D_{0}R_{0}P_{0}^{T}}{L_{b}\overbrace{M''}R_{c}}P_{c}^{T}\\
  = & \overset{L_{a}}{\overbrace{L_{b}L_{0}^{\phantom{T}}}}\,\overset{D_{a}}{\overbrace{D_{0}^{\phantom{T}}}}\,\overset{R_{a}}{\overbrace{R_{0}P_{0}^{T}R_{c}}}\,\overset{P_{a}^{T}}{\overbrace{P_{c}^{T}}}\\
  = & L_{a}D_{a}R_{a}P_{a}^{T}.
\end{align*}
```
"""
function mul!(F₃::LDR{T}, F₂::LDR{T}, F₁::LDR{T}) where {T}

    M_tmp = F₃.M_tmp

    # calulcate R₂⋅P₂ᵀ⋅L₁
    mul_P!(F₃.L, F₂.pᵀ, F₁.L) # P₂ᵀ⋅L₁
    R₂ = UpperTriangular(F₂.R)
    lmul!(R₂, F₃.L) # R₂⋅(P₂ᵀ⋅L₁)

    # calculate (R₂⋅P₂ᵀ⋅L₁)⋅D₁
    rmul_D!(F₃.L, F₁.d)

    # calculate D₂⋅(R₂⋅P₂ᵀ⋅L₁⋅D₁)
    lmul_D!(F₂.d, F₃.L)

    # calculate the decomposition of (D₂⋅R₂⋅P₂ᵀ⋅L₁⋅D₁)
    ldr!(F₃)

    # calculate L₃ = L₂⋅L₃
    mul!(M_tmp, F₂.L, F₃.L)
    copyto!(F₃.L, M_tmp)

    # calculate R₃ = R₃⋅P₃ᵀ⋅R₁
    mul_P!(M_tmp, F₃.R, F₃.pᵀ) # R′⋅Pᵀ
    mul!(F₃.R, M_tmp, F₁.R) # (R′⋅Pᵀ)⋅R₁

    # P₃ᵀ = P₁ᵀ
    copyto!(F₃.pᵀ, F₁.pᵀ)

    return nothing
end


@doc raw"""
    det(F::LDR)

Return the determinant of the LDR factorization `F`.
"""
function det(F::LDR)

    return sign_det(F) * abs_det(F, as_log=false)
end