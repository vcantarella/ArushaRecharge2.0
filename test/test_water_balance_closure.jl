using Test
using ArushaRecharge
using CSV, DataFrames, Dates

@testset "Water balance closure for 1 year (CPU)" begin
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
    result, balance_error = ArushaRecharge.run_water_balance(base_prec, base_pet, base_timestamps, :CPU)

    # The error should be very small (numerical tolerance)
    @test isapprox(balance_error, 0.0; atol=1e-2, rtol=1e-2)
end
