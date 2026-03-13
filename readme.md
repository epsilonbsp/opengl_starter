# OpenGL Starter

Simple OpenGL examples in Odin to get started with, using SDL3 for windowing.

Based on [Odin SDL3 Template](https://github.com/epsilonbsp/odin_sdl3_template) — check that repo if you need help setting up Odin or SDL3.

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
