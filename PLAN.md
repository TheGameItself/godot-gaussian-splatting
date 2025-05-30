# Project Plan: Godot 3D Gaussian Splatting

## Changelog (Living Scientific Record)
- 2024-06-09: Updated draw_list_begin calls to use RenderingDevice.INITIAL_ACTION_CLEAR and RenderingDevice.FINAL_ACTION_STORE if available, otherwise fallback to integer values 1 (Clear) and 3 (Store) due to missing enums in Godot 4.3 stable. Fixed file path for .ply data. Added fallback mechanism for running original code. Documented best debugging practices and started a living scientific record.
- 2024-06-09: Loaded large .ply file (695,779 splats, 59 properties). All pipelines valid. Encountered VK_SUCCESS errors in compute shaders. Plan to implement fallback scene and changelog for each development loop.

## INDEX / LEGEND
- **PRIORITY LIST (Update Frequently):** Sections requiring regular review and updates.
- **PROJECT IMPLEMENTATION PLAN (Update Frequently):** This document.
- **Project File Structure (Key Files & Directories):** Important files and directories.
- **CURRENT PRIORITIES (Focus Area):** Tasks currently being focused on, ordered by importance.
- **PHASED IMPLEMENTATION ROADMAP:** Longer-term plan broken down into phases.
- **Memory Variables Table:** Key variables, types, purposes, and memory requirements.
- **Recent Analysis & Immediate Focus:** Recent issues, findings, resolutions, and next steps.
- **Ongoing Activities:** Continuous tasks like testing, documentation, and research.
- **DEVELOPMENT LOOP:** Iterative process for working on tasks.
- **DEVELOPMENT DECISION TABLE:** Key decision points and actions.

---

## Overall Goal
Implement and enable the training of a live 6D Gaussian placement model within the Godot Engine, capable of representing and rendering dynamic scenes and adapting Gaussian parameters in real-time or near real-time.

---

## CURRENT PRIORITIES (Update Frequently)
- **Fix Core Rendering Resource Initialization (Critical):** Resolve RID(0) errors for buffers and uniform sets in _initialize_rendering_resources (main.gd) by correcting buffer_create calls and usage flags.
- **Fix Render Pipeline Creation:** Ensure the main rendering pipeline in main.gd is created successfully.
- **Verify Basic Rendering:** Achieve a basic visual output in the Godot viewport.
- **Verify Compute Shader Execution:** Confirm culling and sorting compute shaders (visible_splats.glsl, multi_radixsort*.glsl) run and produce expected data (e.g., visible_count).
- **Refine PLY Loading & SH:** Ensure robust .ply parsing (_load_ply_file in main.gd) and correct loading/usage of SH coefficients in splat.glsl.
- **Implement Culling & Sorting Logic:** Verify the correctness of the culling and radix sort algorithms implemented in the compute shaders.
- **Integrate Data into Render Shader:** Ensure splat.glsl correctly accesses and uses all required Gaussian properties (position, opacity, scale, rotation, SH) from the buffers.
- **Implement Optimization Techniques (Tile-based Rendering, LOD, etc.):** Integrate performance optimizations based on the plan.
- **Integrate External Training Output:** Ensure compatibility with .ply files from the PyTorch training pipeline.
- **Implement Fourier Transform & Evolutionary Algorithm Integration:** Begin integrating the core concepts of the broader project vision.
- **Testing, Validation, and Refinement:** Conduct comprehensive testing, optimize performance, and address visual/stability issues.

---

## Recent Analysis & Immediate Focus
- **Immediate Focus:** Test the project after the latest fixes. If rendering is still blank, check for print output, buffer/pipeline validity, and .ply data loading. Begin the development loop: select next priority from CURRENT PRIORITIES, implement/debug, test, and analyze results. Progress is now tracked in the changelog above.

---

## DEVELOPMENT LOOP
1. **Select Current Priority:** Choose the highest-priority task from the CURRENT PRIORITIES list.
2. **Implement/Debug:** Write or modify code to address the selected task. Use debugging techniques (print statements, Godot debugger, etc.).
3. **Test:** Run the project to verify the implemented changes and check for expected behavior (e.g., console output, visual rendering).
4. **Analyze Results & Update Plan:** Analyze what worked, what didn't, and why. Update the Recent Analysis & Immediate Focus section with findings, resolutions, and next steps. Move completed priorities to a "Completed Priorities" section (add as needed).
5. **Repeat:** Return to step 1.

---

## AI-Assisted Debugging & Chat Tools Integration

### Why Use Chat Tools for Debugging?
Chat-based AI tools (like ChatGPT) can accelerate debugging by:
- Explaining error messages and code behavior
- Suggesting fixes and code improvements
- Helping generate and review test cases
- Providing step-by-step guidance for isolating and reproducing bugs
- Assisting with code understanding and documentation

**References:**
- [How to Debug Code Using ChatGPT (Rollbar)](https://rollbar.com/blog/how-to-debug-code-using-chatgpt/)
- [How to use ChatGPT to write code and debug (ZDNet)](https://www.zdnet.com/article/how-to-use-chatgpt-to-write-code-and-my-favorite-trick-to-debug-what-it-generates/)

### AI-Assisted Debugging Loop
1. **Identify the Problem**
   - Use debug output, error messages, or unexpected behavior as clues.
   - Ask the chat tool to explain errors or suggest likely causes.
2. **Isolate the Problem**
   - Narrow down the code section responsible (use print statements, breakpoints, or ask the chat tool for strategies).
3. **Reproduce the Problem**
   - Ensure the bug can be triggered consistently. Ask the chat tool for help in creating minimal test cases.
4. **Understand the Code**
   - Use the chat tool to explain code structure, logic, and dependencies.
5. **Apply Fixes and Suggestions**
   - Implement fixes suggested by the chat tool or your own analysis.
   - Use the chat tool to review the fix or suggest improvements.
6. **Test the Fix**
   - Run the code and verify the issue is resolved. Ask the chat tool for additional test cases if needed.
7. **Document the Process**
   - Log the bug, solution, and any insights in the plan or changelog for future reference.

### Best Practices
- Be specific when describing errors or code to the chat tool.
- Share relevant code snippets and error messages.
- Use the chat tool iteratively: ask, apply, test, and repeat.
- Document all findings and solutions in the project plan.

---

## PHASED IMPLEMENTATION ROADMAP
### Phase 1: Core Infrastructure Completion & Verification
- Finalize Resource Initialization
- Deep Dive into Compute Shader Correctness
- Refine PLY Data Handling

### Phase 2: Data Integration & Initial Rendering Refinement
- Verify Data Usage in Render Shader
- Implement Basic SH Calculation

### Phase 3: Optimization and Performance Foundation
- Implement Core Culling & Sorting Logic
- Explore Initial Optimizations
- Optimize Frame Time

### Phase 4: External Integration & Testing
- Integrate External Data
- Establish Testing and Validation Procedures

### Phase 5: Advanced Features Leading to Live 6D Training
- Fourier Transform Integration
- Evolutionary Algorithm Implementation
- Dynamic Scene Support
- Dynamic Point Management
- Integrate Ray Sampling
- Integrate CNNs for Dynamic Tasks
- Implement View Angle Prediction Training

---

## Project File Structure (Key Files & Directories)
- .godot/ : Godot editor-specific files and cache
- assets/ : Models, textures, etc.
- Originals/ : Original project files for reference
- shaders/ : Godot-specific shaders for Gaussian Splatting
- Testing Data/ : Sample data for testing
- UI/ : User interface scenes and scripts
- Camera.gd : Camera control script
- main.gd : Main script for initialization, loading, and rendering
- main.tscn : Main scene file
- README.md : Project README

---

## Memory Variables Table
| Variable Name      | Type                  | Purpose                                      | Memory Requirement         |
|--------------------|-----------------------|----------------------------------------------|---------------------------|
| points             | PackedVector3Array     | 3D coordinates of each point                 | 12 bytes per point        |
| colors             | PackedColorArray       | Color information for each point             | 4 bytes per point         |
| sizes              | PackedFloat32Array     | Size (variance) of each Gaussian             | 4 bytes per point         |
| weights            | PackedFloat32Array     | Weight of each Gaussian                      | 4 bytes per point         |
| parameters         | PackedFloat32Array     | Additional Gaussian parameters (e.g. rotation)| 4 bytes per parameter     |
| num_gaussians      | int                   | Total number of Gaussians                    | 4 bytes                   |
| max_gaussians      | int                   | Maximum number of Gaussians                  | 4 bytes                   |
| error_threshold    | float                 | Threshold for error in rendering             | 4 bytes                   |
| camera_position    | Vector3               | Camera position in the scene                 | 12 bytes                  |
| view_matrix        | Matrix4                | Camera view transformation                   | 64 bytes                  |
| projection_matrix  | Matrix4                | Projection matrix for rendering              | 64 bytes                  |
| frame_time         | float                 | Time taken for last frame rendering          | 4 bytes                   |
| render_target      | Texture               | Texture used for rendering                   | Varies                    |

---

## DEVELOPMENT DECISION TABLE
| Condition                                 | Decision/Action                                                                 | Notes                                                                 |
|--------------------------------------------|----------------------------------------------------------------------------------|-----------------------------------------------------------------------|
| Current Priority Completed Successfully    | Move to the next priority in the CURRENT PRIORITIES list. Update the plan.       | Verify success criteria (e.g., console output, visual results).       |
| Current Priority Blocked or Error Occurs   | Analyze the error/blocker. Consult debug output and relevant code sections.      | Use available tools for investigation. Update plan and focus.         |
| Debugging RenderingDevice (RD) issues      | Consult Originals/main.gd for comparison of RD usage, buffer flags, and freeing. | The original version visually rendered, so it's a good reference.     |
| Visual Rendering Achieved                  | Note this as a checkpoint in "Recent Analysis & Immediate Focus".               | Proceed to verify compute shader execution (Priority 4).              |
| Need to decide on the next development step| Consult the CURRENT PRIORITIES list and this Decision Table.                     | Prioritize based on the list and current findings.                    |
| Need to add/modify a decision rule         | Update this DEVELOPMENT DECISION TABLE with the new or modified rule.            | Keep this table a living document.                                    |
| Script is not executing (no early prints)  | Check project.godot to ensure the main scene is set correctly.                   | Fundamental check if script does not run at all.                      |
| No script output at all                    | Investigate project settings, Godot executable, or environment.                  | Indicates a core issue before script parsing/execution.               |

---

## Ongoing Activities
- Testing, Validation, and Refinement
- Documentation
- Research
- Plan Maintenance

---

## Completed Priorities
- (Add as priorities are completed)

## 1. Fix GDScript Parse Errors
- Identify and resolve syntax and compatibility issues in `main.gd` and other scripts.
- Update code to match the current Godot version's GDScript requirements.

## 2. Rendering Resource Initialization
- Ensure all rendering resources (shaders, buffers, textures) are properly initialized.
- Debug and fix any issues related to resource loading or compatibility.

## 3. Implement 3D Gaussian Splatting
- Integrate or update the core logic for 3D Gaussian Splatting.
- Ensure the splatting algorithm works with the current Godot rendering pipeline.

## 4. Scene and Camera Setup
- Configure the main scene (`main.tscn`) and camera (`Camera.gd`) for correct visualization.
- Test with sample data (e.g., from `Testing Data/3DGS_PLY_sample_data/`).

## 5. UI and Controls
- Implement or refine UI elements for loading data, controlling the view, and adjusting parameters.
- Ensure user interactions are smooth and intuitive.

## 6. Testing and Debugging
- Test the application with various datasets.
- Debug rendering, performance, and interaction issues.
- Address any errors or warnings in the Godot editor and output.

## 7. Documentation and Cleanup
- Update the `README.md` with setup, usage, and troubleshooting instructions.
- Clean up unused files and code. 