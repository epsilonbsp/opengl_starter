package example

import "core:fmt"
import "core:math"
import rand "core:math/rand"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Instanced Geometry"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

VERTEX_SOURCE :: `#version 460 core
    layout(location = 0) in vec2 i_position;
    layout(location = 1) in vec2 i_tex_coord;
    layout(location = 2) in mat3x2 i_transform;
    layout(location = 5) in int i_color;
    out vec2 v_tex_coord;
    out vec4 v_color;
    uniform mat4 u_projection;

    vec3 get_color(int color) {
        return vec3(
            (color >> 16) & 0xFF,
            (color >> 8) & 0xFF,
            color & 0xFF
        ) / 255.0;
    }

    void main() {
        vec2 position = i_transform * vec3(i_position, 1.0);
        gl_Position = u_projection * vec4(position, 0.0, 1.0);
        v_tex_coord = i_tex_coord;
        v_color = vec4(get_color(i_color), 1.0);
    }
`

FRAGMENT_SOURCE :: `#version 460 core
    in vec2 v_tex_coord;
    in vec4 v_color;
    out vec4 o_frag_color;

    void main() {
        o_frag_color = v_color;
    }
`

INSTANCE_CAP :: 1024
INSTANCE_POS_MIN : f32 : -512
INSTANCE_POS_MAX : f32 : 512
INSTANCE_SCALE_MIN : f32 : 4
INSTANCE_SCALE_MAX : f32 : 64

Vertex :: struct {
    position:  glm.vec2,
    tex_coord: glm.vec2
}

Instance :: struct {
    transform: glm.mat3x2,
    color: i32
}

make_transform :: proc(pos: glm.vec2, angle, scale: f32) -> glm.mat3x2 {
    c := math.cos(angle)
    s := math.sin(angle)

    return glm.mat3x2{
        c * scale, -s * scale, pos.x,
        s * scale,  c * scale, pos.y
    }
}

pack_color :: proc(color: glm.ivec3) -> i32 {
    return (color.x << 16) | (color.y << 8) | color.z
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

    // For anti-aliasing
    sdl.GL_SetAttribute(.MULTISAMPLEBUFFERS, 1)
    sdl.GL_SetAttribute(.MULTISAMPLESAMPLES, 4)

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

    // Low-poly heart geometry: triangle fan, center first then outline CCW, closed
    vertices := [13]Vertex{
        {{ 0.0,  0.1},  {0.5, 0.55}}, // center
        {{ 0.0, -1.0},  {0.5, 0.0 }}, // bottom tip
        {{-0.6, -0.4},  {0.2, 0.3 }}, // lower left
        {{-1.0,  0.2},  {0.0, 0.6 }}, // left side
        {{-0.9,  0.6},  {0.05, 0.8}}, // upper left
        {{-0.5,  0.9},  {0.25, 1.0}}, // left bump peak
        {{ 0.0,  0.65}, {0.5, 0.85}}, // center dip
        {{ 0.5,  0.9},  {0.75, 1.0}}, // right bump peak
        {{ 0.9,  0.6},  {0.95, 0.8}}, // upper right
        {{ 1.0,  0.2},  {1.0, 0.6 }}, // right side
        {{ 0.6, -0.4},  {0.8, 0.3 }}, // lower right
        {{ 0.0, -1.0},  {0.5, 0.0 }}, // close (bottom tip)
        {{ 0.0, -1.0},  {0.5, 0.0 }}, // degenerate to end fan cleanly
    }

    // Per-instance transforms and colors
    instances: [INSTANCE_CAP]Instance

    for &inst in instances {
        pos := glm.vec2{rand.float32_range(INSTANCE_POS_MIN, INSTANCE_POS_MAX), rand.float32_range(INSTANCE_POS_MIN, INSTANCE_POS_MAX)}
        angle := rand.float32_range(0, math.TAU)
        size := rand.float32_range(INSTANCE_SCALE_MIN, INSTANCE_SCALE_MAX)

        inst.transform = make_transform(pos, angle, size)
        inst.color = random_color()
    }

    // Create vertex array
    vao: u32; gl.GenVertexArrays(1, &vao); defer gl.DeleteVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    // Geometry VBO - per-vertex, divisor 0 (default)
    geo_vbo: u32; gl.GenBuffers(1, &geo_vbo); defer gl.DeleteBuffers(1, &geo_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, geo_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices, gl.STATIC_DRAW)

    geo_offset: i32 = 0
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), auto_cast geo_offset)

    geo_offset += size_of(glm.vec2)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), auto_cast geo_offset)

    // Instance VBO - per-instance, divisor 1
    inst_vbo: u32; gl.GenBuffers(1, &inst_vbo); defer gl.DeleteBuffers(1, &inst_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, inst_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(instances), &instances, gl.STATIC_DRAW)

    // mat3x2 occupies 3 consecutive attribute locations (one vec2 per column)
    inst_base_loc :: u32(2) // locations 0 and 1 are used by the geometry VBO
    mat3x2_cols   :: 3

    inst_offset: i32 = 0

    for i in 0 ..< mat3x2_cols {
        loc := inst_base_loc + u32(i)

        gl.EnableVertexAttribArray(loc)
        gl.VertexAttribPointer(loc, 2, gl.FLOAT, gl.FALSE, size_of(Instance), auto_cast inst_offset)
        gl.VertexAttribDivisor(loc, 1)

        inst_offset += size_of(glm.vec2)
    }

    // Color at location 5, after the 3 vec2 columns (3 * 8 = 24 bytes)
    color_loc :: inst_base_loc + mat3x2_cols

    gl.EnableVertexAttribArray(color_loc)
    gl.VertexAttribIPointer(color_loc, 1, gl.INT, size_of(Instance), auto_cast inst_offset)
    gl.VertexAttribDivisor(color_loc, 1)

    gl.Enable(gl.MULTISAMPLE)

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
        gl.DrawArraysInstanced(gl.TRIANGLE_FAN, 0, 13, INSTANCE_CAP)

        sdl.GL_SwapWindow(window)
    }
}
