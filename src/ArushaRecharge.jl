__precompile__()
module ArushaRecharge
    include("kernels.jl")
    using JLD2
    using CSV, DataFrames
    using Dates
    using Statistics
    using Metal
    include("lookuptable_management.jl")
    include("run_water_balance.jl")

    # Datasets are now loaded via a function for precompilation compatibility
    const _datasets_loaded = Ref(false)
    const fnormalized_landuse = Ref{Any}()
    const flanduse_mapping = Ref{Any}()
    const fnormalized_soil = Ref{Any}()
    const fsoiltype_mapping = Ref{Any}()
    const felevation = Ref{Any}()
    const fslope = Ref{Any}()

    function load_datasets()
        if !_datasets_loaded[]
            root = joinpath(@__DIR__, "..")
            landuse_path = joinpath(root, "julia_datasets", "normalized_landuse.jld2")
            soiltype_path = joinpath(root, "julia_datasets", "normalized_soiltype.jld2")
            elev_path = joinpath(root, "julia_datasets", "elevation.jld2")
            slope_path = joinpath(root, "julia_datasets", "slope.jld2")
            @load landuse_path normalized_landuse landuse_mapping
            @load soiltype_path normalized_soil soiltype_mapping
            @load elev_path elevation
            @load slope_path slope
            fnormalized_landuse[] = normalized_landuse
            flanduse_mapping[] = landuse_mapping
            fnormalized_soil[] = normalized_soil
            fsoiltype_mapping[] = soiltype_mapping
            felevation[] = elevation
            fslope[] = slope
            _datasets_loaded[] = true
        end
        return fnormalized_landuse[], flanduse_mapping[], fnormalized_soil[], fsoiltype_mapping[], felevation[], fslope[]
    end

    # # Extract model cells (CPU arrays for now)
    # model_landuse_cpu = normalized_landuse[normalized_landuse .> 1]
    # model_soil_cpu = normalized_soil[normalized_landuse .> 1]
    
    # println("Model statistics:")
    # println("  Minimum landuse: ", minimum(model_landuse_cpu))
    # println("  Maximum landuse: ", maximum(model_landuse_cpu))
    # println("  Number of cells: ", length(model_landuse_cpu))

    # # Lookup tables based on land use codes
    # threshold_precipitation_lookup = Dict(
    #     1 => 12.0,
    #     21 => 15.0,
    #     31 => 17.5,
    #     32 => 16.0,
    #     33 => 18.5,
    #     36 => 17.5,
    #     307 => 17.5,
    # )
    # thresh_prec_array = lookup_table_to_array(threshold_precipitation_lookup, landuse_mapping)
    
    # crop_coefficient_lookup = Dict(
    #     1 => 0.6,
    #     21 => 1.5,
    #     31 => 1.3,
    #     32 => 1.2,
    #     33 => 1.2,
    #     36 => 1.0,
    #     307 => 0.9
    # )
    # crop_coeff_array = lookup_table_to_array(crop_coefficient_lookup, landuse_mapping)
    
    # soil_ext_depth_lookup = Dict(
    #     1 => 300,
    #     21 => 1000,
    #     31 => 1000,
    #     32 => 1000,
    #     33 => 1000,
    #     36 => 600,
    #     307 => 1000
    # )
    # soil_ext_depth_array = lookup_table_to_array(soil_ext_depth_lookup, landuse_mapping)
    
    # # Lookup tables based on soil type codes
    # soil_capacity_lookup = Dict(
    #     10 => 0.13,
    #     11 => 0.12
    # )
    # soil_cap_array = lookup_table_to_array(soil_capacity_lookup, soiltype_mapping)
    
    # prec_df = CSV.read("arusha_recharge/Climate data/Precipitation_2020.csv", DataFrame)
    # pet_df = CSV.read("arusha_recharge/Climate data/ET_2020.csv", DataFrame)
    # prec = prec_df[!, "Precipitation (mm/day)"]
    # prec = MtlArray(Float32.(prec))
    # pet = pet_df[!, "ET (mm/day)"]
    # pet = MtlArray(Float32.(pet))
    # timestamps = prec_df[!, "Date"]
    # timestamps = Date.(timestamps, dateformat"dd/mm/yyyy")
    # months = month.(timestamps)
    # periods = sort(unique(months))
    # # Initialize results DataFrame where we will store monthly water balance results
    # ResultDf = DataFrame(Month = Int[], 
    #     ActET = Float32[],
    #     Recharge = Float32[],
    #     Runoff = Float32[],
    #     Prec = Float32[],
    #     ChangeinStorage = Float32[])

    # # Initialize soil storage as half of the soil capacity
    # # IMPORTANT: Do this on CPU before transferring to GPU
    # n_cells = length(model_landuse_cpu)
    
    # # Compute initial storage on CPU using CPU arrays
    # soil_storage = [soil_cap_array[model_soil_cpu[i]] * 
    #                 soil_ext_depth_array[model_landuse_cpu[i]] / 2.0f0 
    #                 for i in 1:n_cells]
    
    # # Now transfer everything to GPU as Float32
    # println("Transferring arrays to GPU...")
    # model_landuse = MtlArray(Int32.(model_landuse_cpu))
    # model_soil = MtlArray(Int32.(model_soil_cpu))
    # thresh_prec_array = MtlArray(Float32.(thresh_prec_array))
    # crop_coeff_array = MtlArray(Float32.(crop_coeff_array))
    # soil_ext_depth_array = MtlArray(Float32.(soil_ext_depth_array))
    # soil_cap_array = MtlArray(Float32.(soil_cap_array))
    # soil_storage = MtlArray(Float32.(soil_storage))
    # initial_soil_storage = copy(soil_storage)
    # # prepare arrays to hold cumulative results
    # total_actet = MtlArray(zeros(Float32, n_cells))
    # total_recharge = MtlArray(zeros(Float32, n_cells))
    # total_runoff = MtlArray(zeros(Float32, n_cells))
    # total_prec = MtlArray(zeros(Float32, n_cells))
    # #initialize the device
    # backend = get_backend(soil_storage)
    # # Loop over each month
    # for period in periods
    #     println("Processing month: $period")
    #     initial_month_soil_storage = copy(soil_storage)
    #     month_indices = findall(months .== period)
    #     n_timesteps = length(month_indices)
    #     kernel = water_balance_timeseries!(backend, 64)
    #     ev = kernel(
    #         total_actet, total_recharge, total_runoff, total_prec,
    #         soil_storage,
    #         prec[month_indices], pet[month_indices],
    #         model_landuse, model_soil,
    #         thresh_prec_array, crop_coeff_array,
    #         soil_cap_array, soil_ext_depth_array,
    #         n_timesteps;
    #         ndrange = n_cells
    #     )
    #     KernelAbstractions.synchronize(backend)
    #     ## The part below can also be done on the GPU for efficiency
    #     # Calculate monthly totals by subtracting previous totals (on GPU)
    #     monthly_actet = sum(total_actet)./n_cells
    #     monthly_recharge = sum(total_recharge)./n_cells
    #     monthly_runoff = sum(total_runoff)./n_cells
    #     monthly_prec = sum(total_prec)./n_cells
    #     change_in_storage_month = sum(soil_storage .- initial_month_soil_storage)./n_cells
    #     # Append monthly results to DataFrame
    #     push!(ResultDf, (period, monthly_actet, monthly_recharge,
    #         monthly_runoff, monthly_prec, change_in_storage_month))
    #     # Update previous totals for next iteration (on GPU)
    # end
    # final_soil_storage = copy(soil_storage)
    # # Calculate the model error in the water balance
    # change_in_storage = sum(final_soil_storage .- initial_soil_storage)./n_cells
    # println("The change in soil storage over the year (mm) per cell:")
    # println(change_in_storage)
    # total_input = sum(ResultDf.Prec)
    # println("The total precipitation input over the year (mm) per cell:")
    # println(total_input)
    # total_output = sum(ResultDf.ActET .+ ResultDf.Recharge .+ ResultDf.Runoff)
    # println("The total output (ActET + Recharge + Runoff) over the year (mm) per cell:")
    # println(total_output)
    # balance_error = total_input - total_output - change_in_storage
    # println("The water balance error over the simulation: $balance_error mm")
    
    # # Transfer GPU arrays back to CPU for raster creation
    # println("Transferring results back to CPU...")
    # soil_storage_cpu = Array(soil_storage)
    # total_recharge_cpu = Array(total_recharge)
    # total_runoff_cpu = Array(total_runoff)
    # total_actet_cpu = Array(total_actet)
    
    # # Now we have calculated the yearly water balance. 
    # # Save the maps by mapping the results back to the full array
    # final_soil_storage = zeros(size(normalized_landuse))
    # final_soil_storage[normalized_landuse .> 1] = soil_storage_cpu
    # final_recharge = zeros(size(normalized_landuse))
    # final_recharge[normalized_landuse .> 1] = total_recharge_cpu
    # final_runoff = zeros(size(normalized_landuse))
    # final_runoff[normalized_landuse .> 1] = total_runoff_cpu
    # final_actet = zeros(size(normalized_landuse))
    # final_actet[normalized_landuse .> 1] = total_actet_cpu

    # # Plot the maps using ArchGDAL
    # import ArchGDAL as AG
    # @load "julia_datasets/geotransform_landuse.jld2" gt
    # @load "julia_datasets/projection_landuse.jld2" p
    # AG.create(
    # "./julia_datasets/annual_water_balance.tif",
    # driver = AG.getdriver("GTiff"),
    # width=size(normalized_landuse, 2),
    # height=size(normalized_landuse, 1),
    # nbands=4,
    # dtype=Float64
    # ) do dataset
    #     AG.write!(dataset, final_soil_storage, 1)
    #     AG.write!(dataset, final_recharge, 2)
    #     AG.write!(dataset, final_runoff, 3)
    #     AG.write!(dataset, final_actet, 4)
    #     AG.setgeotransform!(dataset, gt)
    #     AG.setproj!(dataset, p)
    # end

    # display(ResultDf)
end