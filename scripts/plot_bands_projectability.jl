#!/usr/bin/env julia
import ArgParse
import Wannier as Wan
import Plots as Pl

function parse_commandline()
    s = ArgParse.ArgParseSettings()
    @ArgParse.add_arg_table s begin
        # "--opt1"
        #     help = "an option with an argument"
        "--fermi_energy", "-f"
            help = "Fermi energy"
            arg_type = Union{Int, Float64}
            default = 0
        # "--flag1"
        #     help = "an option without argument, i.e. a flag"
        #     action = :store_true
        "qebands"
            help = "Filename of QE bands.x output bands.dat file"
            required = true
        "qeprojs"
            help = "Filename of QE projwfc.x output prefix.proj.dat.projwfc_up file"
            required = true
    end
    return ArgParse.parse_args(s)
end

function main()
    parsed_args = parse_commandline()
    
    f_qe_bands = parsed_args["qebands"]
    f_qe_projs = parsed_args["qeprojs"]
    fermi_energy = parsed_args["fermi_energy"]

    qe_bands = Wan.InOut.read_qe_bands(f_qe_bands)
    qe_projs = Wan.InOut.read_qe_projwfcup(f_qe_projs)

    # need to add labels
    qe_bands.symm_points_label = ["G", "X", "P", "N", "G", "M", "S", "S0", "G", "X", "R", "G", "M"]
    fermi_energy = 1.5135500000e+01

    thres = .92
    qe_projs.proj[qe_projs.proj .>= thres] .= 1
    qe_projs.proj[qe_projs.proj .< thres] .= 0

    #Pl.plotly()
    plt = Wan.plot_bands_projectabilities(qe_bands, qe_projs; fermi_energy=fermi_energy, show_gui=false)
    emin, emax = 15, 18
    Pl.ylims!(plt, (emin, emax))
    Pl.gui(plt)

    # print("Hit <enter> to continue")
    # readline()
    print("Save figure to PDF? (Y/n)")
    y = lowercase(strip(readline()))
    if y == "y" || y == ""
        pdfname = "$(basename(f_qe_bands))+$(basename(f_qe_projs)).pdf"
        Pl.savefig(pdfname)
        println("Saved to $pdfname")
    end
end

main()
