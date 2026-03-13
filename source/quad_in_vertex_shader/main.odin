package example

import "core:fmt"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Quad In Vertex Shader"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

VERTEX_SOURCE :: `#version 460 core
    out vec2 v_tex_coord;
    out vec4 v_color;
    uniform mat4 u_projection;

    const vec2 positions[] = vec2[](
        vec2(-128.0, -128.0),
        vec2(128.0, -128.0),
        vec2(-128.0, 128.0),
        vec2(128.0, 128.0)
    );

    // Bottom left origin
    const vec2 tex_coords[] = vec2[](
        vec2(0.0, 0.0),
        vec2(1.0, 0.0),
        vec2(0.0, 1.0),
        vec2(1.0, 1.0)
    );

    const vec4 colors[] = vec4[](
        vec4(0.0, 0.0, 0.0, 1.0),
        vec4(1.0, 0.0, 0.0, 1.0),
        vec4(0.0, 1.0, 0.0, 1.0),
        vec4(0.0, 0.0, 1.0, 1.0)
    );

    void main() {
        gl_Position = u_projection * vec4(positions[gl_VertexID], 0.0, 1.0);
        v_tex_coord = tex_coords[gl_VertexID];
        v_color = colors[gl_VertexID];
    }
`

FRAGMENT_SOURCE :: `#version 460 core
    in vec2 v_tex_coord;
    in vec4 v_color;
    out vec4 o_frag_color;

    void main() {
        vec2 checker = floor(v_tex_coord * 8.0);
        float pattern = mod(checker.x + checker.y, 2.0);

        o_frag_color = v_color + vec4(vec3(pattern * 0.2), 0.0);
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

    program, program_status := gl.load_shaders_source(VERTEX_SOURCE, FRAGMENT_SOURCE)
    uniforms := gl.get_uniforms_from_program(program)

    if !program_status {
        fmt.printf("SHADER LOAD ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(program)

    // Bind default vao, won't draw otherwise
    vao: u32; gl.GenVertexArrays(1, &vao); defer gl.DeleteVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

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

        gl.UseProgram(program)
        gl.UniformMatrix4fv(uniforms["u_projection"].location, 1, false, &projection[0][0])
        gl.DrawArrays(gl.TRIANGLE_STRIP, 0, 4)

        sdl.GL_SwapWindow(window)
    }
}
