package example

import "core:fmt"
import rand "core:math/rand"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Instanced Points"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

VERTEX_SOURCE :: `#version 460 core
    layout(location = 0) in vec2 i_position;
    layout(location = 1) in float i_radius;
    layout(location = 2) in int i_color;
    flat out float v_radius;
    out vec4 v_color;
    out vec2 v_tex_coord;
    uniform mat4 u_projection;

    const vec2 positions[] = vec2[](
        vec2(-1.0, -1.0),
        vec2(1.0, -1.0),
        vec2(-1.0, 1.0),
        vec2(1.0, 1.0)
    );

    const vec2 tex_coords[] = vec2[](
        vec2(0.0, 0.0),
        vec2(1.0, 0.0),
        vec2(0.0, 1.0),
        vec2(1.0, 1.0)
    );

    vec3 get_color(int color) {
        return vec3(
            (color >> 16) & 0xFF,
            (color >> 8) & 0xFF,
            color & 0xFF
        ) / 255.0;
    }

    void main() {
        vec2 position = positions[gl_VertexID] * i_radius + i_position;

        gl_Position = u_projection * vec4(position, 0.0, 1.0);
        v_radius = i_radius;
        v_color = vec4(get_color(i_color), 1.0);
        v_tex_coord = tex_coords[gl_VertexID];
    }
`

FRAGMENT_SOURCE :: `#version 460 core
    flat in float v_radius;
    in vec4 v_color;
    in vec2 v_tex_coord;
    out vec4 o_frag_color;

    void main() {
        vec2 uv = v_tex_coord;
        vec2 cp = uv * 2.0 - 1.0;

        float d = length(cp);
        float alpha = 1.0 - smoothstep(0.9, 1.0, d);

        o_frag_color = vec4(v_color.rgb, alpha);
    }
`

POINT_CAP :: 1024
POINT_POS_MIN : f32 : -512
POINT_POS_MAX : f32 : 512
POINT_RADIUS_MIN : f32 : 4
POINT_RADIUS_MAX : f32 : 16

Point :: struct {
    position: glm.vec2,
    radius: f32,
    color: i32
}

pack_color :: proc(color: glm.ivec3) -> i32 {
    return (color.x << 16) | (color.y << 8) | color.z;
}

random_color :: proc() -> i32 {
    return pack_color({rand.int31() % 256, rand.int31() % 256, rand.int31() % 256})
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

    program, program_status := gl.load_shaders_source(VERTEX_SOURCE, FRAGMENT_SOURCE)
    uniforms := gl.get_uniforms_from_program(program)

    if !program_status {
        fmt.printf("SHADER LOAD ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(program)

    points : [POINT_CAP]Point

    for &point in points {
        point.position = {rand.float32_range(POINT_POS_MIN, POINT_POS_MAX), rand.float32_range(POINT_POS_MIN, POINT_POS_MAX)}
        point.radius = rand.float32_range(POINT_RADIUS_MIN, POINT_RADIUS_MAX)
        point.color = random_color()
    }

    // Create vertex array
    vao: u32; gl.GenVertexArrays(1, &vao); defer gl.DeleteVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    // Create vertex buffer for vertices
    vbo: u32; gl.GenBuffers(1, &vbo); defer gl.DeleteBuffers(1, &vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, POINT_CAP * size_of(Point), &points, gl.STATIC_DRAW)

    // Specify buffer layout
    offset: i32 = 0
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Point), auto_cast offset)
    gl.VertexAttribDivisor(0, 1)

    offset += size_of(glm.vec2)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 1, gl.FLOAT, gl.FALSE, size_of(Point), auto_cast offset)
    gl.VertexAttribDivisor(1, 1)

    offset += size_of(i32)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribIPointer(2, 1, gl.INT, size_of(Point), auto_cast offset)
    gl.VertexAttribDivisor(2, 1)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

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
        gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, POINT_CAP)

        sdl.GL_SwapWindow(window)
    }
}
