using Printf: @printf

export read_eig, write_eig

"""
    read_eig(filename::AbstractString)

Read the `eig` file.

Returns a `n_bands * n_kpts` array.
"""
function read_eig(filename::AbstractString)
    @info "Reading $filename"

    lines = open(filename) do io
        readlines(io)
    end

    n_lines = length(lines)
    idx_b = zeros(Int, n_lines)
    idx_k = zeros(Int, n_lines)
    eig = zeros(Float64, n_lines)

    for i in 1:n_lines
        arr = split(lines[i])
        idx_b[i] = parse(Int, arr[1])
        idx_k[i] = parse(Int, arr[2])
        eig[i] = parse(Float64, arr[3])
    end

    # find unique elements
    n_bands = length(Set(idx_b))
    n_kpts = length(Set(idx_k))
    E = reshape(eig, (n_bands, n_kpts))

    # check eigenvalues should be in order
    # some times there are small noise
    round_digits(x) = round(x; digits=7)
    for ik in 1:n_kpts
        if !issorted(E[:, ik]; by=round_digits)
            @warn "Eigenvalues are not sorted at " ik E[:, ik]
        end
    end

    println("  n_bands = ", n_bands)
    println("  n_kpts  = ", n_kpts)
    println()

    return E
end

"""
    write_eig(filename::AbstractString, E::AbstractArray)

Write `eig` file.
"""
function write_eig(filename::AbstractString, E::AbstractMatrix{T}) where {T<:Real}
    n_bands, n_kpts = size(E)

    open(filename, "w") do io
        for ik in 1:n_kpts
            for ib in 1:n_bands
                @printf(io, "%5d%5d%18.12f\n", ib, ik, E[ib, ik])
            end
        end
    end

    @info "Written to file: $(filename)"
    println()

    return nothing
end
