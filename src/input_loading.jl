import ArchGDAL as AG
using JLD2
include("lookuptable_management.jl")
landuseds = AG.readraster("arusha_recharge/LULC Input/2020_Landuse.map")
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
elevationds = AG.readraster("arusha_recharge/Other input/elevation.map")
elevation = elevationds[:,:,1]
slope = AG.readraster("arusha_recharge/Other input/slope.map")
slope = slope[:,:,1]
soiltypeds = AG.readraster("arusha_recharge/Other input/soil.map")
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

#
# | Land Use Type      | land use code | Crop Coef. |
# |:-------------------|--------------:|-----------:|
# | Urban              |             1 |        0.6 |
# | Agriculture        |            21 |        1.5 |
# | Deciduous forest   |            31 |        1.3 |
# | Coniferous tree    |            32 |        1.2 |
# | Mixed forest       |            33 |        1.2 |
# | Shrub/Grassland    |            36 |        1.0 |
# | Sparsely vegetated |           307 |        0.9 |
threshold_precipitation_lookup = Dict(
    1 => 0.6,
    21 => 1.5,
    31 => 1.3,
    32 => 1.2,
    33 => 1.2,
    36 => 1.0,
    307 => 0.9
)



arr = lookup_table_to_array(lookup_table, landuse_mapping)
