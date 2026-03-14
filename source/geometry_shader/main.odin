package example

import "core:fmt"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Geometry Shader"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

// Vertex shader: emits a single point at the origin
VERTEX_SOURCE :: `#version 460 core

    void main() {
        gl_Position = vec4(0.0, 0.0, 0.0, 1.0);
    }
`

// Geometry shader: takes one point and emits a rotating star as triangle_strip triangles
GEOMETRY_SOURCE :: `#version 460 core
    layout(points) in;
    layout(triangle_strip, max_vertices = 30) out;
    out vec4 v_color;

    uniform mat4 u_projection;
    uniform float u_time;

    const int POINT_COUNT = 5;
    const float OUTER_RADIUS = 200.0;
    const float INNER_RADIUS = 80.0;
    const float TAU = 6.28318530;

    void emit(vec2 center, vec2 offset) {
        gl_Position = u_projection * vec4(center + offset, 0.0, 1.0);
        EmitVertex();
    }

    void main() {
        vec2 center = gl_in[0].gl_Position.xy;

        for (int i = 0; i < POINT_COUNT; i++) {
            float t_outer = TAU * float(i) / float(POINT_COUNT) - TAU / 4.0 + u_time;
            float t_inner = t_outer + TAU / float(2 * POINT_COUNT);
            float t_outer_next = TAU * float(i + 1) / float(POINT_COUNT) - TAU / 4.0 + u_time;

            vec2 outer = vec2(cos(t_outer),      sin(t_outer))      * OUTER_RADIUS;
            vec2 inner = vec2(cos(t_inner),      sin(t_inner))      * INNER_RADIUS;
            vec2 outer_next = vec2(cos(t_outer_next), sin(t_outer_next)) * OUTER_RADIUS;

            v_color = vec4(1.0, 0.85, 0.1, 1.0);

            // Triangle: center > outer tip > inner valley
            emit(center, vec2(0.0));
            emit(center, outer);
            emit(center, inner);
            EndPrimitive();

            // Triangle: center > inner valley > next outer tip
            emit(center, vec2(0.0));
            emit(center, inner);
            emit(center, outer_next);
            EndPrimitive();
        }
    }
`

FRAGMENT_SOURCE :: `#version 460 core
    in vec4 v_color;
    out vec4 o_frag_color;

    void main() {
        o_frag_color = v_color;
    }
`

load_shaders_source :: proc(vs_source, gs_source, fs_source: string, binary_retrievable := false) -> (program_id: u32, ok: bool) {
    vertex_shader_id := gl.compile_shader_from_source(vs_source, gl.Shader_Type.VERTEX_SHADER) or_return
    defer gl.DeleteShader(vertex_shader_id)

    geometry_shader_id := gl.compile_shader_from_source(gs_source, gl.Shader_Type.GEOMETRY_SHADER) or_return
    defer gl.DeleteShader(geometry_shader_id)

    fragment_shader_id := gl.compile_shader_from_source(fs_source, gl.Shader_Type.FRAGMENT_SHADER) or_return
    defer gl.DeleteShader(geometry_shader_id)

    return gl.create_and_link_program([]u32{vertex_shader_id, geometry_shader_id, fragment_shader_id}, binary_retrievable)
}

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

    program, program_ok := load_shaders_source(VERTEX_SOURCE, GEOMETRY_SOURCE, FRAGMENT_SOURCE)
    uniforms := gl.get_uniforms_from_program(program)

    if !program_ok {
        fmt.printf("SHADER ERROR: %s\n", gl.get_last_error_message())

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

        time := f32(sdl.GetTicks()) / 1000.0
        projection := glm.mat4Ortho3d(-f32(viewport_x) / 2, f32(viewport_x) / 2, -f32(viewport_y) / 2, f32(viewport_y) / 2, -1, 1)

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.05, 0.05, 0.1, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(program)
        gl.UniformMatrix4fv(uniforms["u_projection"].location, 1, false, &projection[0][0])
        gl.Uniform1f(uniforms["u_time"].location, time)
        gl.DrawArrays(gl.POINTS, 0, 1)

        sdl.GL_SwapWindow(window)
    }
}
