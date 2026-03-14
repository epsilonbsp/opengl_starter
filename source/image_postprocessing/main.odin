package example

import "core:fmt"
import "core:image/png"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Image Post Processing"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

// Compute pass: reads input texture, applies Gaussian blur kernel, writes to output texture
COMPUTE_SOURCE :: `#version 460 core
    layout(local_size_x = 16, local_size_y = 16) in;
    layout(rgba8, binding = 0) uniform readonly image2D u_input;
    layout(rgba8, binding = 1) uniform writeonly image2D u_output;

    // Sobel edge detection kernels
    const float kernel_x[9] = float[](
        -1.0,  0.0,  1.0,
        -2.0,  0.0,  2.0,
        -1.0,  0.0,  1.0
    );

    const float kernel_y[9] = float[](
        -1.0, -2.0, -1.0,
         0.0,  0.0,  0.0,
         1.0,  2.0,  1.0
    );

    void main() {
        ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
        ivec2 size = imageSize(u_input);

        vec4 gx = vec4(0.0);
        vec4 gy = vec4(0.0);

        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                ivec2 s = clamp(coord + ivec2(x, y), ivec2(0), size - 1);
                vec4 texel = imageLoad(u_input, s);

                gx += texel * kernel_x[(y + 1) * 3 + (x + 1)];
                gy += texel * kernel_y[(y + 1) * 3 + (x + 1)];
            }
        }

        imageStore(u_output, coord, sqrt(gx * gx + gy * gy));
    }
`

// Output pass: draws the processed texture on a centered quad
OUTPUT_VERTEX_SOURCE :: `#version 460 core
    out vec2 v_tex_coord;
    uniform mat4 u_projection;
    uniform vec2 u_offset;
    uniform vec2 u_size;

    const vec2 positions[] = vec2[](
        vec2(-1.0, -1.0),
        vec2( 1.0, -1.0),
        vec2(-1.0,  1.0),
        vec2( 1.0,  1.0)
    );

    const vec2 tex_coords[] = vec2[](
        vec2(0.0, 1.0),
        vec2(1.0, 1.0),
        vec2(0.0, 0.0),
        vec2(1.0, 0.0)
    );

    void main() {
        gl_Position = u_projection * vec4(positions[gl_VertexID] * u_size / 2.0 + u_offset, 0.0, 1.0);
        v_tex_coord = tex_coords[gl_VertexID];
    }
`

OUTPUT_FRAGMENT_SOURCE :: `#version 460 core
    in vec2 v_tex_coord;
    out vec4 o_frag_color;
    uniform sampler2D u_texture;

    void main() {
        o_frag_color = texture(u_texture, v_tex_coord);
    }
`

main :: proc() {
    if !sdl.Init({.VIDEO}) {
        fmt.printf("SDL ERROR: %s\n", sdl.GetError())
        return
    }

    defer sdl.Quit()

    sdl.GL_SetAttribute(.CONTEXT_PROFILE_MASK, i32(sdl.GLProfile.CORE))
    sdl.GL_SetAttribute(.CONTEXT_MAJOR_VERSION, GL_VERSION_MAJOR)
    sdl.GL_SetAttribute(.CONTEXT_MINOR_VERSION, GL_VERSION_MINOR)

    window := sdl.CreateWindow(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT, {.OPENGL, .RESIZABLE})
    defer sdl.DestroyWindow(window)

    gl_context := sdl.GL_CreateContext(window)
    defer sdl.GL_DestroyContext(gl_context)

    gl.load_up_to(GL_VERSION_MAJOR, GL_VERSION_MINOR, sdl.gl_set_proc_address)

    sdl.SetWindowPosition(window, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED)

    viewport_x, viewport_y: i32; sdl.GetWindowSize(window, &viewport_x, &viewport_y)

    compute_program, compute_program_ok := gl.load_compute_source(COMPUTE_SOURCE)

    if !compute_program_ok {
        fmt.printf("COMPUTE SHADER ERROR: %s\n", gl.get_last_error_message())
        return
    }

    defer gl.DeleteProgram(compute_program)

    output_program, output_program_ok := gl.load_shaders_source(OUTPUT_VERTEX_SOURCE, OUTPUT_FRAGMENT_SOURCE)
    output_uniforms := gl.get_uniforms_from_program(output_program)

    if !output_program_ok {
        fmt.printf("OUTPUT SHADER ERROR: %s\n", gl.get_last_error_message())
        return
    }

    defer gl.DeleteProgram(output_program)

    // Bind default vao, won't draw otherwise
    vao: u32; gl.GenVertexArrays(1, &vao); defer gl.DeleteVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    // Load source image, source: https://ambientcg.com/view?id=Bricks101
    data := #load("texture.png")
    image, _ := png.load_from_bytes(data, {.alpha_add_if_missing}); defer png.destroy(image)

    image_width := i32(image.width)
    image_height := i32(image.height)

    // Input texture - loaded from image, read-only in compute
    input_texture: u32; gl.GenTextures(1, &input_texture); defer gl.DeleteTextures(1, &input_texture)
    gl.BindTexture(gl.TEXTURE_2D, input_texture)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, image_width, image_height, 0, gl.RGBA, gl.UNSIGNED_BYTE, &image.pixels.buf[0])
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    // Output texture - same size, compute writes processed result here
    output_texture: u32; gl.GenTextures(1, &output_texture); defer gl.DeleteTextures(1, &output_texture)
    gl.BindTexture(gl.TEXTURE_2D, output_texture)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, image_width, image_height, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

    // Dispatch once - input is static, no need to re-run every frame
    gl.UseProgram(compute_program)
    gl.BindImageTexture(0, input_texture,  0, false, 0, gl.READ_ONLY,  gl.RGBA8)
    gl.BindImageTexture(1, output_texture, 0, false, 0, gl.WRITE_ONLY, gl.RGBA8)
    gl.DispatchCompute(u32((image_width + 15) / 16), u32((image_height + 15) / 16), 1)
    gl.MemoryBarrier(gl.TEXTURE_FETCH_BARRIER_BIT)

    loop: for {
        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
                case .QUIT:
                    break loop
                case .WINDOW_RESIZED:
                    sdl.GetWindowSize(window, &viewport_x, &viewport_y)
            }
        }

        projection := glm.mat4Ortho3d(-f32(viewport_x) / 2, f32(viewport_x) / 2, -f32(viewport_y) / 2, f32(viewport_y) / 2, -1, 1)

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        size := glm.vec2(512)
        gap := size.x / 2

        gl.UseProgram(output_program)
        gl.UniformMatrix4fv(output_uniforms["u_projection"].location, 1, false, &projection[0][0])
        gl.Uniform2f(output_uniforms["u_size"].location, size.x, size.y)

        // Left: original
        gl.Uniform2f(output_uniforms["u_offset"].location, -gap, 0)
        gl.BindTexture(gl.TEXTURE_2D, input_texture)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        // Right: processed
        gl.Uniform2f(output_uniforms["u_offset"].location, gap, 0)
        gl.BindTexture(gl.TEXTURE_2D, output_texture)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        sdl.GL_SwapWindow(window)
    }
}
