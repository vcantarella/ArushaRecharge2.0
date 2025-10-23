using Test
using ArushaRecharge
using CSV, DataFrames, Dates

@testset "CPU vs GPU water balance results match for 1 year" begin
    # Load base year data (2020)
    prec_df = CSV.read("arusha_recharge/Climate data/Precipitation_2020.csv", DataFrame)
    pet_df = CSV.read("arusha_recharge/Climate data/ET_2020.csv", DataFrame)
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
