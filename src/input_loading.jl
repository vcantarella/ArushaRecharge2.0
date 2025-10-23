import ArchGDAL as AG
using JLD2
include("lookuptable_management.jl")

# Configuration: set target resolution (in meters)
# Options: 250 (original), 100, 50, 30
TARGET_RESOLUTION = 30  # Change this to desired resolution

# Determine which files to load based on resolution
if TARGET_RESOLUTION == 250
    # Use original files
    landuse_file = "arusha_recharge/LULC Input/2020_Landuse.map"
    soil_file = "arusha_recharge/Other input/soil.map"
    println("Using original 250m resolution datasets")
else
    # Use resampled files
    landuse_file = "arusha_recharge/LULC Input/2020_Landuse_$(TARGET_RESOLUTION)m.tif"
    soil_file = "arusha_recharge/Other input/soil_$(TARGET_RESOLUTION)m.tif"
    println("Using resampled $(TARGET_RESOLUTION)m resolution datasets")
end

# Load landuse
landuseds = AG.readraster(landuse_file)
AG.getdriver(landuseds)
AG.nraster(landuseds) # nº of bands
AG.width(landuseds)
AG.height(landuseds)
gt = AG.getgeotransform(landuseds)
@save "julia_datasets/geotransform_landuse.jld2" gt
p = AG.getproj(landuseds)
@save "julia_datasets/projection_landuse.jld2" p
AG.toPROJ4(AG.importWKT(p))
unique(landuseds[:,:,1])
landuse = landuseds[:,:,1]

# Load other datasets (these don't need resampling for now)
elevationds = AG.readraster("arusha_recharge/Other input/elevation.map")
elevation = elevationds[:,:,1]
slope = AG.readraster("arusha_recharge/Other input/slope.map")
slope = slope[:,:,1]

# Load soil with resolution-aware file
soiltypeds = AG.readraster(soil_file)
soiltype = soiltypeds[:,:,1]
# Saving the primitive datasets as JLD2 files
@save "julia_datasets/landuse.jld2" landuse
@save "julia_datasets/elevation.jld2" elevation
@save "julia_datasets/slope.jld2" slope
@save "julia_datasets/soiltype.jld2" soiltype

function normalize_lookup_dataset(categorical_dataset)
    unique_values = unique(categorical_dataset)
    sorted_unique_values = sort(unique_values)
    value_to_index = Dict(value => index for (index, value) in enumerate(sorted_unique_values))
    normalized_dataset = [value_to_index[value] for value in categorical_dataset]
    return normalized_dataset, value_to_index
end

normalized_landuse, landuse_mapping = normalize_lookup_dataset(landuse)
normalized_soil, soiltype_mapping = normalize_lookup_dataset(soiltype)
@save "julia_datasets/normalized_landuse.jld2" normalized_landuse landuse_mapping
@save "julia_datasets/normalized_soiltype.jld2" normalized_soil soiltype_mapping


