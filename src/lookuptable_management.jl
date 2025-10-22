
function normalize_lookup_dataset(categorical_dataset)
    unique_values = unique(categorical_dataset)
    sorted_unique_values = sort(unique_values)
    value_to_index = Dict(value => index for (index, value) in enumerate(sorted_unique_values))
    normalized_dataset = [value_to_index[value] for value in categorical_dataset]
    return normalized_dataset, value_to_index
end



"""
    lookup_table_to_array(lookup_table, mapping) -> Vector

Convert a lookup table and mapping dictionary into an array of values for normalized indices.

# Arguments
- `lookup_table`: A dictionary mapping land use codes to numeric values (e.g., 1=>0.6, 21=>1.5)
- `mapping`: A dictionary from `normalize_lookup_dataset` mapping land use codes to indices (e.g., 1=>1, 21=>2)

# Returns
- `Vector`: An array of values ordered by the normalized indices. For each unique land use code
  (in sorted order), returns its corresponding value from the lookup table.

# Description
This function creates a lookup array for use with normalized datasets. Given:
- A mapping from land use codes to sequential indices (from `normalize_lookup_dataset`)
- A lookup table with values for each land use code

It returns an array where `array[i]` contains the value for the land use code at index `i`.

If a land use code in the mapping is not found in the lookup table, the default value of 0.0 is used.

# Examples
lookup values
| Land Use Type      | land use code | Crop Coef. |
|:-------------------|--------------:|-----------:|
| Urban              |             1 |        0.6 |
| Agriculture        |            21 |        1.5 |
| Deciduous forest   |            31 |        1.3 |
| Coniferous tree    |            32 |        1.2 |
| Mixed forest       |            33 |        1.2 |
| Shrub/Grassland    |            36 |        1.0 |
| Sparsely vegetated |           307 |        0.9 |
```julia
# After normalizing land use data
landuse_raster = [1, 21, 31, 1, 21, 307]
normalized_landuse, landuse_mapping = normalize_lookup_dataset(landuse_raster)
# normalized_landuse = [1, 2, 3, 1, 2, 4]
# landuse_mapping = Dict(1=>1, 21=>2, 31=>3, 307=>4)

# Define parameter values for each land use code
lookup_table = Dict(
    1 => 0.6,    # Urban
    21 => 1.5,   # Agriculture
    31 => 1.3,   # Forest
    307 => 0.9   # Sparse vegetation
)

# Create lookup array
lookup_array = lookup_table_to_array(lookup_table, landuse_mapping)
# Result: [0.6, 1.5, 1.3, 0.9]
# Now: parameter_value = lookup_array[normalized_landuse[i]]
```

# Usage Pattern
```julia
# Step 1: Normalize land use codes
normalized_landuse, mapping = normalize_lookup_dataset(landuse_raster)

# Step 2: Create lookup arrays for each parameter
kc_lookup = lookup_table_to_array(kc_table, mapping)
threshold_lookup = lookup_table_to_array(threshold_table, mapping)

# Step 3: In kernel, use: kc_val = kc_lookup[normalized_landuse[i]]
```
"""
function lookup_table_to_array(lookup_table::AbstractDict, mapping::AbstractDict)
    # mapping is: land_use_code => index
    # We need to create array where array[index] = lookup_table[land_use_code]
    
    # Invert the mapping to get: index => land_use_code
    index_to_code = Dict(idx => code for (code, idx) in mapping)
    
    # Create array in order of indices
    max_index = maximum(values(mapping))
    result = zeros(max_index)
    
    for i in 1:max_index
        code = index_to_code[i]
        result[i] = get(lookup_table, code, 0.0)
    end
    
    return result
end
