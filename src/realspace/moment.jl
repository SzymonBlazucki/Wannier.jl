@doc """
Compute WF moment (mean, variance, ...) in realspace.

Note WFs are defined in a supercell that is n_kpts times unit cell,
however, usuall we only calculate realspace WFs in a smaller supercell
that is 2^3 or 3^3 times unit cell (as defined by the `n_supercells` of
`read_realspace_wf`). Some times this is not sufficient if the WFs are
truncated by the boundries of the smaller supercell, thus the center
calculated by this function is inexact. In principle, we should calculate
centers in the n_kpts supercell, however, this is memory-consuming.

rgrid: realspace grid on which W is defined
W: Wannier functions
n: order of moment, e.g., 1 for WF center, 2 for variance, etc.
"""
function moment(rgrid::RGrid, W::AbstractArray{T,3}, n::U) where {T<:Complex,U<:Integer}
    Xᶜ, Yᶜ, Zᶜ = cartesianize_xyz(rgrid)
    x = sum(conj(W) .* Xᶜ .^ n .* W)
    y = sum(conj(W) .* Yᶜ .^ n .* W)
    z = sum(conj(W) .* Zᶜ .^ n .* W)
    r = [x, y, z]
    return real(r)
end

function moment(rgrid::RGrid, W::AbstractArray{T,4}, n::U) where {T<:Complex,U<:Integer}
    n_wann = size(W, 4)
    r = Matrix{real(T)}(undef, 3, n_wann)
    for i in 1:n_wann
        r[:, i] = moment(rgrid, W[:, :, :, i], n)
    end
    return r
end

center(rgrid::RGrid, W::AbstractArray) = moment(rgrid, W, 1)
omega(rgrid::RGrid, W::AbstractArray) = moment(rgrid, W, 2) - center(rgrid, W) .^ 2

@doc """Position operator matrices computed with realspace WFs"""
function position(rgrid::RGrid, W::AbstractArray{T,4}) where {T<:Complex}
    Xᶜ, Yᶜ, Zᶜ = cartesianize_xyz(rgrid)
    n_wann = size(W, 4)
    # last index is x,y,z
    r = zeros(T, n_wann, n_wann, 3)
    for i in 1:n_wann
        for j in 1:n_wann
            Wᵢ = W[:, :, :, i]
            Wⱼ = W[:, :, :, j]
            r[i, j, 1] = sum(conj(Wᵢ) .* Xᶜ .* Wⱼ)
            r[i, j, 2] = sum(conj(Wᵢ) .* Yᶜ .* Wⱼ)
            r[i, j, 3] = sum(conj(Wᵢ) .* Zᶜ .* Wⱼ)
        end
    end
    return r
end
