using Printf: @printf

export rotate_gauge

"""
    struct Model

A struct containing the parameters and matrices of the crystal structure.

# Fields
- `lattice`: columns are the lattice vectors
- `atom_positions`: columns are the fractional coordinates of atoms
- `atom_labels`: labels of atoms
- `kgrid`: number of kpoints along 3 lattice vectors
- `kpoints`: columns are the fractional coordinates of kpoints
- `bvectors`: bvectors satisfying the B1 condition
- `frozen_bands`: indicates which bands are frozen
- `M`: `n_bands * n_bands * n_bvecs * n_kpts`, overlap matrix ``M_{\\bm{k},\\bm{b}}``
- `A`: `n_bands * n_wann * n_kpts`, (semi-)unitary gauge rotation matrix ``A_{\\bm{k}}``
- `E`: `n_bands * n_kpts`, energy eigenvalues ``\\epsilon_{n \\bm{k}}``
- `recip_lattice`: columns are the reciprocal lattice vectors
- `n_atoms`: number of atoms
- `n_bands`: number of bands
- `n_wann`: number of wannier functions
- `n_kpts`: number of kpoints
- `n_bvecs`: number of bvectors

!!! note

    This only cotains the necessary information for maximal localization.
    For Wannier interpolation, see [`InterpModel`](@ref InterpModel).
"""
struct Model{T<:Real}
    # unit cell, 3 * 3, Å unit, each column is a lattice vector
    lattice::Mat3{T}

    # atomic positions, 3 * n_atoms, fractional coordinates,
    # each column is a position
    atom_positions::Matrix{T}

    # atomic labels, n_atoms
    atom_labels::Vector{String}

    # number of kpoints along 3 directions
    kgrid::Vec3{Int}

    # kpoints array, fractional coordinates, 3 * n_kpts
    # n_kpts is the last index since julia array is column-major
    kpoints::Matrix{T}

    # b vectors satisfying b1 condition
    bvectors::BVectors{T}

    # is band frozen? n_bands * n_kpts
    frozen_bands::BitMatrix

    # Mmn matrix, n_bands * n_bands * n_bvecs * n_kpts
    M::Array{Complex{T},4}

    # Amn matrix, n_bands * n_wann * n_kpts
    A::Array{Complex{T},3}

    # eigenvalues, n_bands * n_kpts
    E::Matrix{T}

    # I put these frequently used variables in the last,
    # since they are generated by the constructor.

    # reciprocal cell, 3 * 3, Å⁻¹ unit, each column is a lattice vector
    recip_lattice::Mat3{T}

    # number of atoms
    n_atoms::Int

    # number of bands
    n_bands::Int

    # number of Wannier functions (WFs)
    n_wann::Int

    # number of kpoints
    n_kpts::Int

    # number of b vectors
    n_bvecs::Int
end

"""
    Model(lattice, atom_positions, atom_labels, kgrid, kpoints, bvectors, frozen_bands, M, A, E)

Construct a [`Model`](@ref Model) `struct`.

# Arguments
- `lattice`: columns are the lattice vectors
- `atom_positions`: columns are the fractional coordinates of atoms
- `atom_labels`: labels of atoms
- `kgrid`: number of kpoints along 3 lattice vectors
- `kpoints`: columns are the fractional coordinates of kpoints
- `bvectors`: bvectors satisfying the B1 condition
- `frozen_bands`: indicates which bands are frozen
- `M`: `n_bands * n_bands * n_bvecs * n_kpts`, overlap matrix ``M_{\\bm{k},\\bm{b}}``
- `A`: `n_bands * n_wann * n_kpts`, (semi-)unitary gauge rotation matrix ``A_{\\bm{k}}``
- `E`: `n_bands * n_kpts`, energy eigenvalues ``\\epsilon_{n \\bm{k}}``

!!! tip

    This is more user-friendly constructor, only necessary information is required.
    Remaining fields are generated automatically.
"""
function Model(
    lattice::Mat3{T},
    atom_positions::Matrix{T},
    atom_labels::Vector{String},
    kgrid::Vec3{Int},
    kpoints::Matrix{T},
    bvectors::BVectors{T},
    frozen_bands::AbstractMatrix{Bool},
    M::Array{Complex{T},4},
    A::Array{Complex{T},3},
    E::Matrix{T},
) where {T<:Real}
    return Model(
        lattice,
        atom_positions,
        atom_labels,
        kgrid,
        kpoints,
        bvectors,
        BitMatrix(frozen_bands),
        M,
        A,
        E,
        get_recip_lattice(lattice),
        length(atom_labels),
        size(A, 1),
        size(A, 2),
        size(A, 3),
        bvectors.n_bvecs,
    )
end

function Base.show(io::IO, model::Model)
    @printf(io, "lattice: Å\n")
    for i in 1:3
        @printf(io, "  a%d: %8.5f %8.5f %8.5f\n", i, model.lattice[:, i]...)
    end
    println(io)

    @printf(io, "atoms: fractional\n")
    for i in 1:(model.n_atoms)
        l = model.atom_labels[i]
        pos = model.atom_positions[:, i]
        @printf(io, " %3s: %8.5f %8.5f %8.5f\n", l, pos...)
    end
    println(io)

    @printf(io, "n_bands: %d\n", model.n_bands)
    @printf(io, "n_wann : %d\n", model.n_wann)
    @printf(io, "kgrid  : %d %d %d\n", model.kgrid...)
    @printf(io, "n_kpts : %d\n", model.n_kpts)
    @printf(io, "n_bvecs: %d\n", model.n_bvecs)

    println(io)
    show(io, model.bvectors)
    return nothing
end

"""
    rotate_gauge(model::Model, A::Array{T,3}; diag_H=false)

Rotate the gauge of a `Model`.

# Arguments
- `model`: a `Model` `struct`
- `A`: `n_bands * n_wann * n_kpts`, (semi-)unitary gauge rotation matrix ``A_{\\bm{k}}``

# Keyword Arguments
- `diag_H`: if after rotation, the Hamiltonian is not diagonal, then diagonalize it and
    save the eigenvalues to `model.E`, and the inverse of the eigenvectors to `model.A`,
    so that the `model` is still in the input gauge `A`.
    Otherwise, if the rotated Hamiltonian is not diagonal, raise error.

!!! note

    The original `Model.A` will be discarded;
    the `M`, and `E` matrices will be rotated by the input `A`.
    However, since `E` is not the Hamiltonian matrices but only the eigenvalues,
    if `diag_H = false`, this function only support rotations that keep the Hamiltonian
    in diagonal form.
"""
function rotate_gauge(model::Model, A::Array{T,3}; diag_H::Bool=false) where {T<:Number}
    n_bands = model.n_bands
    n_kpts = model.n_kpts
    size(A)[[1, 3]] == (n_bands, n_kpts) || error("A must have size (n_bands, :, n_kpts)")
    # The new n_wann
    n_wann = size(A, 2)

    # the new AMN is just identity
    A2 = eyes_A(eltype(A), n_wann, n_kpts)

    # EIG
    E = model.E
    E2 = zeros(eltype(E), n_wann, n_kpts)
    H = zeros(eltype(model.A), n_wann, n_wann)
    # tolerance for checking Hamiltonian
    atol = 1e-8
    # all the diagonalized kpoints, used if diag_H = true
    diag_kpts = Int[]
    for ik in 1:n_kpts
        Aₖ = A[:, :, ik]
        H .= Aₖ' * diagm(0 => E[:, ik]) * Aₖ
        ϵ = diag(H)
        if norm(H - diagm(0 => ϵ)) > atol
            if diag_H
                # diagonalize the Hamiltonian
                ϵ, v = eigen(H)
                A2[:, :, ik] = v
                push!(diag_kpts, ik)
            else
                error("H is not diagonal after gauge rotation")
            end
        end
        if any(imag(ϵ) .> atol)
            error("H has non-zero imaginary part")
        end
        E2[:, ik] = real(ϵ)
    end

    # MMN
    M = model.M
    kpb_k = model.bvectors.kpb_k
    M2 = rotate_M(M, kpb_k, A)
    if diag_H && length(diag_kpts) > 0
        M2 = rotate_M(M2, kpb_k, A2)
        # A needs to save the inverse of the eigenvectors
        for ik in diag_kpts
            A2[:, :, ik] = inv(A2[:, :, ik])
        end
    end

    model2 = Model(
        model.lattice,
        model.atom_positions,
        model.atom_labels,
        model.kgrid,
        model.kpoints,
        model.bvectors,
        zeros(Bool, n_wann, n_kpts),
        M2,
        A2,
        E2,
    )
    return model2
end
