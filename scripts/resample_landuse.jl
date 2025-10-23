"""
Resample landuse raster to a smaller cell size.

This script uses GDAL command line tool for reliable resampling.
"""

"""
    resample_raster(input_file, output_file, target_resolution; method="near")

Resample a raster to a target resolution using gdalwarp command line tool.

# Arguments
- `input_file`: Path to input raster file
- `output_file`: Path to output raster file
- `target_resolution`: Target cell size (e.g., 30 for 30m, 100 for 100m)
- `method`: Resampling method, default is "near" for nearest neighbor

# Example
```julia
resample_raster("arusha_recharge/LULC Input/2020_Landuse.asc", 
                "arusha_recharge/LULC Input/2020_Landuse_100m.tif", 
                100)
```
"""
function resample_raster(input_file::String, output_file::String, target_resolution::Real; method::String="near")
    println("=" ^ 70)
    println("Resampling Raster")
    println("=" ^ 70)
    println("Input: $input_file")
    println("Output: $output_file")
    println("Target resolution: $target_resolution")
    println("Method: $method")
    println()
    
    # Build gdalwarp command - convert resolution to string
    res_str = string(target_resolution)
    
    # Build command as array to handle spaces in filenames properly
    # -overwrite flag allows overwriting existing files
    cmd = Cmd(["gdalwarp", "-overwrite", "-tr", res_str, res_str, "-r", method, "-co", "COMPRESS=LZW", input_file, output_file])
    
    println("Running command:")
    println(cmd)
    println()
    println("Resampling in progress...")
    
    # Run the command
    run(cmd)
    
    println("✓ Resampling complete!")
    println()
    println("Output saved to: $output_file")
    println("=" ^ 70)
end

# Resample all datasets to 30m resolution
target_res = 30

println("\n" * "=" ^ 70)
println("Resampling all datasets to $(target_res)m resolution")
println("=" ^ 70 * "\n")

# 1. Landuse
input_file = "arusha_recharge/LULC Input/2020_Landuse.asc"
output_file = "arusha_recharge/LULC Input/2020_Landuse_$(target_res)m.tif"
resample_raster(input_file, output_file, target_res)

# 2. Soil
println("\n")
soil_input = "arusha_recharge/Other input/soil.asc"
soil_output = "arusha_recharge/Other input/soil_$(target_res)m.tif"
resample_raster(soil_input, soil_output, target_res)

# 3. Elevation (use bilinear for continuous data)
println("\n")
elevation_input = "arusha_recharge/Other input/elevation.asc"
elevation_output = "arusha_recharge/Other input/elevation_$(target_res)m.tif"
resample_raster(elevation_input, elevation_output, target_res, method="bilinear")

# 4. Slope (use bilinear for continuous data)
println("\n")
slope_input = "arusha_recharge/Other input/slope.asc"
slope_output = "arusha_recharge/Other input/slope_$(target_res)m.tif"
resample_raster(slope_input, slope_output, target_res, method="bilinear")

println("\n" * "=" ^ 70)
println("All datasets resampled to $(target_res)m!")
println("=" ^ 70)
