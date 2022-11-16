# functions used to estimate start values of the parameters

"""
    reference_holdup_time(prog, L, d, gas; control="Pressure")

Calculate the reference holdup time for the GC program `prog` for a column with length `L` and diameter `d` and `gas` as mobile phase.
"""
function reference_holdup_time(col, prog; control="Pressure")
    Tref = 150.0
    # estimate the time of the temperature program for T=Tref
    t_ = prog.time_steps
    T_ = prog.temp_steps
    interp = interpolate(Interpolations.deduplicate_knots!((T_ .- Tref, )), cumsum(t_), Gridded(Linear()))
	tref = interp(0.0)
    # inlet and outlet pressure at time tref
    Fpin_ref = prog.Fpin_itp(tref)
    pout_ref = prog.pout_itp(tref)
    # hold-up time calculated for the time of the program, when T=Tref
    tMref = GasChromatographySimulator.holdup_time(Tref+273.15, Fpin_ref, pout_ref, col.L, col.d, col.gas, control=control)
    return tMref
end

"""
    elution_temperature(tRs, prog)

Calculate the elution temperatures from retention times `tRs` and GC programs `prog`.
"""
function elution_temperature(tRs, prog)
    Telus = Array{Float64}(undef, length(tRs))
    for i=1:length(tRs)
        Telus[i] = prog.T_itp(0.0, tRs[i])
    end
    return Telus
end

function estimate_start_parameter_single_ramp(tRs::DataFrame, col, prog; time_unit="min", control="Pressure")
    if time_unit == "min"
		a = 60.0
	else
		a = 1.0
	end
    tR_meas = Array(tRs[:,2:end]).*a
    nt, ns = size(tR_meas)
    tMref = Array{Float64}(undef, nt)
    RT = Array{Float64}(undef, nt) 
    Telu_meas = Array{Float64}(undef, nt, ns)
    for i=1:nt
        tMref[i] = reference_holdup_time(col, prog[i]; control=control)/a
        RT[i] = (prog[i].temp_steps[(end-1)] - prog[i].temp_steps[2])/(prog[i].time_steps[(end-1)] - prog[i].time_steps[2]) # single-ramp temperature programs with 4 time_steps are assumed
        Telu_meas[i,:] = elution_temperature(tR_meas[i,:], prog[i])
    end 
    rT = RT.*tMref./θref
    Telu_max = Array{Float64}(undef, ns)
    Tchar_est = Array{Float64}(undef, ns)
    θchar_est = Array{Float64}(undef, ns)
    ΔCp_est = Array{Float64}(undef, ns)
    for i=1:ns
        interp = interpolate((rT, ), Interpolations.deduplicate_knots!(Telu_meas[:,i]), Gridded(Linear()))
        Telu_max[i] = maximum(Telu_meas[:,i])
        Tchar_est[i] = interp(rT_nom)
        θchar_est[i] = 22.0*(Tchar_est[i]/Tst)^0.7*(1000*col.df/col.d)^0.09
        ΔCp_est[i] = 100.0
    end
    return Tchar_est, θchar_est, ΔCp_est, Telu_max
end

function estimate_start_parameter_mean_elu_temp(tRs::DataFrame, col, prog; time_unit="min")
	if time_unit == "min"
		a = 60.0
	else
		a = 1.0
	end
    tR_meas = Array(tRs[:,2:end]).*a
    
    nt, ns = size(tR_meas)
	Telu_max = Array{Float64}(undef, ns)
	Tchar_elu = Array{Float64}(undef, ns)
	θchar_elu = Array{Float64}(undef, ns)
	for j=1:ns
		Telu = Array{Float64}(undef, nt)
		for i=1:nt
			Telu[i] = elution_temperature(tR_meas[i,j], prog[i])[1]
		end
		Telu_max[j] = maximum(Telu)
		Tchar_elu[j] = mean(Telu)
		θchar_elu[j] = 22.0*(Tchar_elu[j]/273.15)^0.7*(1000*col.df/col.d)^0.09
	end
	ΔCp_elu = 100.0.*ones(ns)
	return Tchar_elu, θchar_elu, ΔCp_elu, Telu_max
end

function estimate_start_parameter(tR_meas::DataFrame, col, prog; time_unit="min", control="Pressure")
    try
        Tchar_est, θchar_est, ΔCp_est, Telu_max = estimate_start_parameter_single_ramp(tR_meas, col, prog; time_unit=time_unit, control=control)
    catch 
        Tchar_est, θchar_est, ΔCp_est, Telu_max = estimate_start_parameter_mean_elu_temp(tR_meas, col, prog; time_unit=time_unit)
    end
    return Tchar_est, θchar_est, ΔCp_est, Telu_max
end