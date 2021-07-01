using LinearAlgebra: isapprox
include("constants.jl")
include("utilities.jl")
include("bvectors.jl")

function read_win(filename)
    println("Reading $filename")
    fwin = open(filename)

    num_wann = missing
    num_bands = missing
    num_kpts = missing
    kpts_size = zeros(3)
    unit_cell = zeros(3, 3)
    kpts = zeros(3, 1)

    read_array(f) = map(x -> parse(Float64, x), split(readline(f)))

    while !eof(fwin)
        line = readline(fwin)
        # handle case insensitive win files (relic of Fortran)
        line = strip(lowercase(line))
        line = replace(line, "=" => " ")
        line = replace(line, ":" => " ")
        line = replace(line, "," => " ")
        if startswith(line, r"!|#")
            continue
        elseif occursin("mp_grid", line)
            kpts_size = map(x -> parse(Int, x), split(line)[2:4])
            num_kpts = prod(kpts_size)
            kpts = zeros(3, num_kpts)
        elseif occursin("num_bands", line)
            num_bands = parse(Int, split(line)[2])
        elseif occursin("num_wann", line)
            num_wann = parse(Int, split(line)[2])
        elseif occursin("begin unit_cell_cart", line)
            unit = strip(lowercase(readline(fwin)))
            for i = 1:3
                # in win file, each line is a lattice vector, here it is stored as column vec
                unit_cell[:, i] = read_array(fwin)
            end
            if startswith(unit, r"b")
                # convert to angstrom
                unit_cell .*= bohr
            end
        elseif occursin("begin kpoints", line)
            for i = 1:num_kpts
                kpts[:, i] = read_array(fwin)
            end
        end
    end
    close(fwin)

    @assert !ismissing(num_wann)
    @assert num_wann > 0

    if ismissing(num_bands)
        num_bands = num_wann
    end
    @assert num_bands > 0

    @assert all(i -> i > 0, num_kpts)

    @assert all(x -> !ismissing(x), unit_cell)

    recip_cell = get_recipcell(unit_cell)

    println("$filename OK, num_wann = $num_wann, num_bands = $num_bands, num_kpts = $num_kpts")

    return Dict(
        "num_wann" => num_wann,
        "num_bands" => num_bands,
        "num_kpts" => num_kpts,
        "kpts_size" => kpts_size,
        "kpts" => kpts,
        "unit_cell" => unit_cell,
        "recip_cell" => recip_cell
    )
end

function read_mmn(filename)
    println("Reading $filename")
    fmmn = open(filename)

    # skip header
    readline(fmmn)
    line = readline(fmmn)
    num_bands, num_kpts, num_bvecs = map(x -> parse(Int64, x), split(line))

    # overlap matrix
    mmn = zeros(ComplexF64, num_bands, num_bands, num_bvecs, num_kpts)
    # for each point, list of neighbors, (K) representation
    bvecs = zeros(Int64, num_bvecs, num_kpts)
    bvecs_disp = zeros(Int64, 3, num_bvecs, num_kpts)

    while !eof(fmmn)
        for ib = 1:num_bvecs
            line = readline(fmmn)
            arr = split(line)
            k = parse(Int64, arr[1])
            kpb = parse(Int64, arr[2])
            bvecs_disp[:, ib, k] = map(x -> parse(Int64, x), arr[3:5])
            bvecs[ib, k] = kpb
            for n = 1:num_bands
                for m = 1:num_bands
                    line = readline(fmmn)
                    arr = split(line)
                    o = parse(Float64, arr[1]) + im * parse(Float64, arr[2])
                    mmn[m, n, ib, k] = o
                    @assert !isnan(o)
                end
            end
        end
    end
    close(fmmn)
    println("$filename OK, size = ", size(mmn))

    return mmn, bvecs, bvecs_disp
end

function read_amn(filename)
    println("Reading $filename")

    famn = open("$filename.amn")
    readline(amn)
    arr = split(readline(amn))
    num_bands = parse(Int64, arr[1])
    num_kpts = parse(Int64, arr[2])
    num_wann = parse(Int64, arr[3])
    amn = zeros(ComplexF64, num_bands, num_wann, num_kpts)

    while !eof(famn)
        line = readline(famn)
        arr = split(line)
        m = parse(Int64, arr[1])
        n = parse(Int64, arr[2])
        k = parse(Int64, arr[3])
        a = parse(Float64, arr[4]) + im * parse(Float64, arr[5])
        amn[m, n, k] = a
    end
    close(famn)

    # FIX: normalization should be done later
    # for k = 1:num_kpts
    #     amn[:, :, k] = orthonormalize_lowdin(amn[:, :, k])
    # end

    println("$filename OK, size = ", size(amn))
    return amn
end

function read_eig(filename)
    println("Reading $filename")
    eig = zeros(Ntot, nband)

    feig = open(filename)
    lines = readlines(filename)
    close(feig)

    len = length(lines)
    indexb = zeros(len)
    indexk = zeros(len)
    eig = zeros(len)

    for i = 1:len
        arr = split(lines[i])
        indexb[i] = parse(Int, arr[1])
        indexk[i] = parse(Int, arr[2])
        eig[i] = parse(Float64, arr[3])
    end
    
    # find unique elements
    num_bands = length(Set(indexb))
    num_kpts = length(Set(indexk))
    eig = reshape(eig, (num_bands, num_kpts))
    
    println("$filename OK, size = ", size(eig))
    return eig
end

function read_seedname(seedname, read_amn = true, read_eig=true)
    # read win, mmn and optionally amn
    win = read_win("$seedname.win")
    num_bands = win["num_bands"]
    num_wann = win["num_wann"]
    num_kpts = win["num_kpts"]

    kpbs, kpbs_disp, kpbs_weight = generate_bvectors(win["kpts"], win["recip_cell"])
    num_bvecs = size(kpbs_weight, 1)

    mmn, kpbs2, kpbs_disp2 = read_mmn("$seedname.mmn")
    # check consistency for mmn
    @assert num_bands == size(mmn)[1]
    @assert num_bvecs == size(mmn)[3]
    @assert num_kpts == size(mmn)[4]
    @assert kpbs == kpbs2
    @assert kpbs_disp == kpbs_disp2

    if read_amn
        amn = read_amn("$seedname.amn")
        @assert num_bands == size(amn)[1]
        @assert num_wann == size(amn)[2]
        @assert num_kpts == size(amn)[3]
    else
        # TODO: not tested
        amn = zeros(ComplexF64, num_bands, num_wann, num_kpts)
        for n = 1:num_wann
            amn[n, n, :] .= 1
        end
    end

    if read_eig
        eig = read_eig("$seedname.eig")
        @assert num_bands == size(eig)[1]
        @assert num_kpts == size(eig)[2]
    else
        eig = zeros(num_bands, num_kpts)
    end

    # FIX: not tested
    # map = true
    # logMethod = true

    println("num_bands = $num_bands, num_wann = $num_wann, kpt = ", 
    win["kpts_size"], " num_bvecs = $num_bvecs")

    return WannierParameters(
        seedname,
        win["unit_cell"],
        win["recip_cell"],
        win["num_bands"],
        win["num_wann"],
        win["num_kpts"],
        win["kpts_size"],
        win["kpts"],
        num_bvecs,
        kpbs,
        kpbs_weight,
        kpbs_disp,
        mmn,
        amn,
        eig
    )
end

read_seedname("/home/junfeng/git/Wannier.jl/test/silicon/example27/pao_w90/si")