using Test
using ArushaRecharge
using CSV, DataFrames, Dates

@testset "CPU vs GPU water balance results match for 1 year" begin
    # Load base year data (2020)
    root = joinpath(@__DIR__, "..")
    prec_path = joinpath(root, "input_data", "Precipitation_2020.csv")
    pet_path = joinpath(root, "input_data", "ET_2020.csv")
    if !isfile(prec_path)
        error("Missing precipitation file: $prec_path. Please ensure the file exists and the path is correct.")
    end
    if !isfile(pet_path)
        error("Missing ET file: $pet_path. Please ensure the file exists and the path is correct.")
    end
    prec_df = CSV.read(prec_path, DataFrame)
    pet_df = CSV.read(pet_path, DataFrame)
    base_prec = prec_df[!, "Precipitation (mm/day)"]
    base_pet = pet_df[!, "ET (mm/day)"]
    base_timestamps = Date.(prec_df[!, "Date"], dateformat"dd/mm/yyyy")

    # Run model on CPU
    cpu_result = ArushaRecharge.run_water_balance(base_prec, base_pet, base_timestamps, :CPU)
    # Run model on GPU
    gpu_result = ArushaRecharge.run_water_balance(base_prec, base_pet, base_timestamps, :GPU)

    # Compare DataFrames (allowing for small floating point differences)
    @test size(cpu_result[1]) == size(gpu_result[1])
    for col in names(cpu_result[1])
        if eltype(cpu_result[1][!, col]) <: Number
            @test isapprox(cpu_result[1][!, col], gpu_result[1][!, col]; rtol=1e-4, atol=1e-4)
        else
            @test cpu_result[1][!, col] == gpu_result[1][!, col]
        end
    end
end
