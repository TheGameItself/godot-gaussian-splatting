#[compute]

// VkRadixSort written by Mirco Werner: https://github.com/MircoWerner/VkRadixSort
// Based on implementation of Intel's Embree: https://github.com/embree/embree/blob/v4.0.0-ploc/kernels/rthwif/builder/gpu/sort.h

#version 460
#extension GL_GOOGLE_include_directive: enable
#extension GL_KHR_shader_subgroup_basic: enable
#extension GL_KHR_shader_subgroup_arithmetic: enable
#extension GL_KHR_shader_subgroup_ballot: enable

#define WORKGROUP_SIZE 512// assert WORKGROUP_SIZE >= RADIX_SORT_BINS
#define RADIX_SORT_BINS 256
#define SUBGROUP_SIZE 32// 32 NVIDIA; 64 AMD

layout(local_size_x = WORKGROUP_SIZE, local_size_y = 1, local_size_z = 1) in;

layout (push_constant, std430) uniform PushConstants {
    uint g_num_elements;
    uint g_shift;
    uint g_num_workgroups;
    uint g_num_blocks_per_workgroup;
};

layout (std430, set = 1, binding = 0) buffer elements_in {
    uvec2 g_elements_in[];
};

layout (std430, set = 1, binding = 1) buffer elements_out {
    uvec2 g_elements_out[];
};

layout (std430, set = 1, binding = 2) buffer histograms {
// [histogram_of_workgroup_0 | histogram_of_workgroup_1 | ... ]
    uint g_histograms[];// |g_histograms| = RADIX_SORT_BINS * #WORKGROUPS = RADIX_SORT_BINS * g_num_workgroups
};

shared uint[RADIX_SORT_BINS / SUBGROUP_SIZE] sums;// subgroup reductions
shared uint[RADIX_SORT_BINS] global_offsets;// global exclusive scan (prefix sum)

struct BinFlags {
    uint flags[WORKGROUP_SIZE / 32];
};
shared BinFlags[RADIX_SORT_BINS] bin_flags;

void main() {
    uint gID = gl_GlobalInvocationID.x;
    uint lID = gl_LocalInvocationID.x;
    uint wID = gl_WorkGroupID.x;
    uint sID = gl_SubgroupID;
    uint lsID = gl_SubgroupInvocationID;

    uint local_histogram = 0;
    uint prefix_sum = 0;
    uint histogram_count = 0;

    if (lID < RADIX_SORT_BINS) {
        uint count = 0;
        for (uint j = 0; j < g_num_workgroups; j++) {
            const uint t = g_histograms[RADIX_SORT_BINS * j + lID];
            local_histogram = (j == wID) ? count : local_histogram;
            count += t;
        }
        histogram_count = count;
        const uint sum = subgroupAdd(histogram_count);
        prefix_sum = subgroupExclusiveAdd(histogram_count);
        if (subgroupElect()) {
            // one thread inside the warp/subgroup enters this section
            sums[sID] = sum;
        }
    }
    barrier();

    if (lID < RADIX_SORT_BINS) {
        const uint sums_prefix_sum = subgroupBroadcast(subgroupExclusiveAdd(sums[lsID]), sID);
        const uint global_histogram = sums_prefix_sum + prefix_sum;
        global_offsets[lID] = global_histogram + local_histogram;
    }

    //     ==== scatter keys according to global offsets =====
    const uint flags_bin = lID / 32;
    const uint flags_bit = 1 << (lID % 32);

    for (uint index = 0; index < g_num_blocks_per_workgroup; index++) {
        uint elementId = wID * g_num_blocks_per_workgroup * WORKGROUP_SIZE + index * WORKGROUP_SIZE + lID;

        // initialize bin flags
        if (lID < RADIX_SORT_BINS) {
            for (int i = 0; i < WORKGROUP_SIZE / 32; i++) {
                bin_flags[lID].flags[i] = 0U;// init all bin flags to 0
            }
        }
        barrier();

        uvec2 element_in = uvec2(0, 0);
        uint binID = 0;
        uint binOffset = 0;
        if (elementId < g_num_elements) {
            element_in = g_elements_in[elementId];
            binID = uint(element_in[0] >> g_shift) & uint(RADIX_SORT_BINS - 1);
            // offset for group
            binOffset = global_offsets[binID];
            // add bit to flag
            atomicAdd(bin_flags[binID].flags[flags_bin], flags_bit);
        }
        barrier();

        if (elementId < g_num_elements) {
            // calculate output index of element
            uint prefix = 0;
            uint count = 0;
            for (uint i = 0; i < WORKGROUP_SIZE / 32; i++) {
                const uint bits = bin_flags[binID].flags[i];
                const uint full_count = bitCount(bits);
                const uint partial_count = bitCount(bits & (flags_bit - 1));
                prefix += (i < flags_bin) ? full_count : 0U;
                prefix += (i == flags_bin) ? partial_count : 0U;
                count += full_count;
            }
            g_elements_out[binOffset + prefix] = element_in;
            if (prefix == count - 1) {
                atomicAdd(global_offsets[binID], count);
            }
        }

        barrier();
    }
}