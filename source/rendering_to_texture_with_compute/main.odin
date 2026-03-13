package example

import "core:fmt"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Rendering To Texture With Compute"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

TEXTURE_WIDTH  :: 512
TEXTURE_HEIGHT :: 512

// Compute pass: writes heart SDF directly to texture via imageStore
TEXTURE_COMPUTE_SOURCE :: `#version 460 core
    layout(local_size_x = 16, local_size_y = 16) in;
    layout(rgba8, binding = 0) uniform writeonly image2D u_output;
    uniform float u_time;

    const vec3  COLOR_OUTSIDE   = vec3(0.53, 0.81, 0.92);
    const vec3  COLOR_INSIDE    = vec3(0.85, 0.10, 0.15);
    const float PULSE_AMPLITUDE = 0.1;
    const float PULSE_SPEED     = 4.0;
    const float FALLOFF_SHARP   = 6.0;
    const float RIPPLE_FREQ     = 320.0;
    const float EDGE_SOFTNESS   = 0.01;

    float dot2(vec2 v) {
        return dot(v, v);
    }

    // Source: https://iquilezles.org/articles/distfunctions2d/
    float sd_heart(in vec2 p) {
        p.y += 0.5;
        p.x = abs(p.x);

        if (p.y + p.x > 1.0) {
            return sqrt(dot2(p - vec2(0.25, 0.75))) - sqrt(2.0) / 4.0;
        }

        return sqrt(min(
            dot2(p - vec2(0.0, 1.0)),
            dot2(p - 0.5 * max(p.x + p.y, 0.0))
        )) * sign(p.x - p.y);
    }

    void main() {
        ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
        ivec2 size  = imageSize(u_output);

        vec2 uv = (vec2(coord) + 0.5) / vec2(size);
        vec2 p  = 2.0 * uv - 1.0;

        float scale = 1.0 + PULSE_AMPLITUDE * sin(u_time * PULSE_SPEED);
        float d = sd_heart(p / scale);

        vec3 col = (d > 0.0) ? COLOR_OUTSIDE : COLOR_INSIDE;
        col *= 1.0 - exp(-FALLOFF_SHARP * abs(d));
        col *= 0.8 + 0.2 * cos(RIPPLE_FREQ * d);
        col  = mix(col, vec3(1.0), 1.0 - smoothstep(0.0, EDGE_SOFTNESS, abs(d)));

        imageStore(u_output, coord, vec4(col, 1.0));
    }
`

// Output pass: samples the compute texture and draws it on a centered quad
OUTPUT_VERTEX_SOURCE :: `#version 460 core
    out vec2 v_tex_coord;
    uniform mat4 u_projection;

    const vec2 quad_size = vec2(512.0);
    const vec2 half_size = quad_size / 2.0;

    const vec2 positions[] = vec2[](
        vec2(-half_size.x, -half_size.y),
        vec2( half_size.x, -half_size.y),
        vec2(-half_size.x,  half_size.y),
        vec2( half_size.x,  half_size.y)
    );

    const vec2 tex_coords[] = vec2[](
        vec2(0.0, 0.0),
        vec2(1.0, 0.0),
        vec2(0.0, 1.0),
        vec2(1.0, 1.0)
    );

    void main() {
        gl_Position = u_projection * vec4(positions[gl_VertexID], 0.0, 1.0);
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

    texture_program, texture_program_ok := gl.load_compute_source(TEXTURE_COMPUTE_SOURCE)
    texture_uniforms := gl.get_uniforms_from_program(texture_program)

    if !texture_program_ok {
        fmt.printf("TEXTURE SHADER ERROR: %s\n", gl.get_last_error_message())
        return
    }

    defer gl.DeleteProgram(texture_program)

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

    // Texture the compute shader writes into — must use sized internal format (RGBA8) for image units
    texture: u32; gl.GenTextures(1, &texture); defer gl.DeleteTextures(1, &texture)
    gl.BindTexture(gl.TEXTURE_2D, texture)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, TEXTURE_WIDTH, TEXTURE_HEIGHT, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)

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

        time := f32(sdl.GetTicks()) / 1000.0
        projection := glm.mat4Ortho3d(-f32(viewport_x) / 2, f32(viewport_x) / 2, -f32(viewport_y) / 2, f32(viewport_y) / 2, -1, 1)

        // Compute pass: dispatch heart SDF to texture
        gl.UseProgram(texture_program)
        gl.Uniform1f(texture_uniforms["u_time"].location, time)
        gl.BindImageTexture(0, texture, 0, false, 0, gl.WRITE_ONLY, gl.RGBA8)
        gl.DispatchCompute(TEXTURE_WIDTH / 16, TEXTURE_HEIGHT / 16, 1)
        gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)

        // Output to main window framebuffer
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(output_program)
        gl.UniformMatrix4fv(output_uniforms["u_projection"].location, 1, false, &projection[0][0])
        gl.BindTexture(gl.TEXTURE_2D, texture)
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        sdl.GL_SwapWindow(window)
    }
}
