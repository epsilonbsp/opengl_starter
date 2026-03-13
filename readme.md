# OpenGL Starter

Simple OpenGL examples in Odin to get started with, using SDL3 for windowing.

Based on [Odin SDL3 Template](https://github.com/epsilonbsp/odin_sdl3_template) - check that repo if you need help setting up Odin or SDL3.

## Setup

Build SDL:

```
./build.bat build-sdl
```

## Usage

Run the current example:

```
./build.bat run
```

To switch examples, edit [source/main.odin](source/main.odin) and change the import to point to a different example package:

```odin
// Change import to run different examples
import example "default_window"
```

## Examples

| Example | Description |
|---------|-------------|
| `default_window` | Basic SDL3 + OpenGL 4.6 window with a grey clear color |
| `quad_in_vertex_shader` | Colored quad drawn using hardcoded positions and colors in the vertex shader |
| `quad_in_buffer` | Colored quad drawn using vertex data uploaded to a VBO |
| `quad_in_buffer_indexed` | Colored quad drawn using a VBO and an index buffer (EBO) with `glDrawElements` |
| `quad_with_texture` | Textured quad using a PNG loaded at compile time, mixed with vertex color |
| `instanced_points` | 1024 circles drawn in a single draw call using instanced rendering with per-instance position, radius, and color |
| `instanced_geometry` | 1024 low-poly hearts drawn in a single draw call using instanced rendering with per-instance `mat3x2` transform and packed color |
| `image_generation` | CPU-generated Voronoi diagram uploaded as a texture and displayed on a quad |
| `rendering_to_texture_with_fragment` | Heart SDF rendered to an offscreen FBO texture using fragment shader, then displayed on a centered quad |
| `rendering_to_texture_with_compute` | Heart SDF written directly to a texture using a compute shader via `imageStore`, then displayed on a centered quad |
| `image_postprocessing` | Sobel edge detection applied to a brick texture using a compute shader kernel, displayed side-by-side with the original |
| `geometry_shader` | A single `GL_POINT` expanded into a rotating 5-pointed star by a geometry shader |
| `particles_with_ssbo` | 1024 particles simulated on the GPU using a compute shader writing to an SSBO, then rendered as instanced circles |
| `cube_and_camera` | A cube rendered in 3D with with basic lighting, and a free-look camera controlled by mouse and WASD |
| `shared_camera_ubo` | A lit cube and 1024 shaded sphere impostors rendered in a shared 3D scene using a UBO to supply camera matrices to both programs |
| `normal_mapping` | A textured cube with per-pixel lighting using a normal map, tangent-space TBN matrix computed per vertex, supporting 8-bit and 16-bit PNG textures |
