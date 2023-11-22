function CLEARSWI.clearswi_main(args; version="1.3")
    settings = getargs(args, version)
    if isnothing(settings) return end
    
    writedir = settings["output"]
    filename = "clearswi"
    if occursin(r"\.nii$", writedir)
        filename = basename(writedir)
        writedir = dirname(writedir)
    end

    if endswith(settings["phase"], ".gz") || endswith(settings["magnitude"], ".gz")
        settings["no-mmap"] = true
    end

    mkpath(writedir)
    saveconfiguration(writedir, settings, args, version)

    mag = readmag(settings["magnitude"]; mmap=!settings["no-mmap"])
    phase = readphase(settings["phase"]; mmap=!settings["no-mmap"], rescale=!settings["no-phase-rescale"])
    hdr = CLEARSWI.MriResearchTools.header(mag)
    neco = size(mag, 4)

    ## Echoes for unwrapping
    echoes = try
        getechoes(settings, neco)
    catch y
        if isa(y, BoundsError)
            error("echoes=$(join(settings["unwrap-echoes"], " ")): specified echo out of range! Number of echoes is $neco")
        else
            error("echoes=$(join(settings["unwrap-echoes"], " ")) wrongly formatted!")
        end
    end
    settings["verbose"] && println("Echoes are $echoes")
    
    TEs = getTEs(settings, neco, echoes)
    settings["verbose"] && println("TEs are $TEs")

    ## Error messages
    if 1 < length(echoes) && length(echoes) != length(TEs)
        error("Number of chosen echoes is $(length(echoes)) ($neco in .nii data), but $(length(TEs)) TEs were specified!")
    end
    
    echoes = getechoes(settings, neco)
    if echoes != 1:neco
        phase = phase[:,:,:,echoes]
        mag = mag[:,:,:,echoes]
        settings["verbose"] && println("Selecting echoes $echoes")
    end

    data = Data(mag, phase, hdr, TEs)
    mag_combine =   if settings["mag-combine"][1] == "SNR"
                        :SNR
                    elseif settings["mag-combine"][1] == "average"
                        :average
                    elseif settings["mag-combine"][1] == "echo"
                        :echo => parse(Int, last(settings["mag-combine"]))
                    elseif settings["mag-combine"][1] == "SE"
                        :SE => parse(Float32, last(settings["mag-combine"]))
                    else
                        error("The setting for mag-combine is not valid: $(settings["mag-combine"])")
                    end
    mag_sens =  if settings["mag-sensitivity-correction"] == "on"
                    nothing
                elseif settings["mag-sensitivity-correction"] == "off"
                    [1]
                elseif isfile(settings["mag-sensitivity-correction"])
                    settings["mag-sensitivity-correction"]
                else
                    error("The setting for mag-sensitivity-correction is not valid: $(settings["mag-sensitivity-correction"])")
                end
    mag_softplus =  if settings["mag-softplus-scaling"] == "on"
                        true
                    elseif settings["mag-softplus-scaling"] == "off"
                        false
                    else
                        error("The setting for mag-softplus-scaling is not valid: $(settings["mag-softplus-scaling"])")
                    end
    phase_unwrap = Symbol(settings["unwrapping-algorithm"])
    phase_hp_sigma = eval(Meta.parse(join(settings["filter-size"], " ")))
    phase_scaling_type = Symbol(settings["phase-scaling-type"])
    phase_scaling_strength = try parse(Int, settings["phase-scaling-strength"]) catch; parse(Float32, settings["phase-scaling-strength"]) end
    writesteps = settings["writesteps"]
    qsm = settings["qsm"]

    options = Options(;mag_combine, mag_sens, mag_softplus, phase_unwrap, phase_hp_sigma, phase_scaling_type, phase_scaling_strength, writesteps, qsm)

    swi = calculateSWI(data, options)
    mip = createIntensityProjection(swi, minimum)
    
    savenii(swi, filename, writedir, hdr)
    savenii(mip, "mip", writedir, hdr)

    return 0
end
