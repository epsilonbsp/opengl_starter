package example

import "core:fmt"
import rand "core:math/rand"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Image Generation"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

IMAGE_WIDTH  :: 512
IMAGE_HEIGHT :: 512
VORONOI_SEEDS :: 64

VERTEX_SOURCE :: `#version 460 core
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

    // Bottom left origin
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

FRAGMENT_SOURCE :: `#version 460 core
    in vec2 v_tex_coord;
    out vec4 o_frag_color;
    uniform sampler2D u_texture;

    void main() {
        o_frag_color = texture(u_texture, v_tex_coord);
    }
`

Seed :: struct {
    pos: glm.vec2,
    color: [3]u8
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

    // Create vertex array
    vao: u32; gl.GenVertexArrays(1, &vao); defer gl.DeleteVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    seeds: [VORONOI_SEEDS]Seed

    for &s in seeds {
        s.pos = {rand.float32_range(0, IMAGE_WIDTH), rand.float32_range(0, IMAGE_HEIGHT)}
        s.color = {u8(rand.int31() % 256), u8(rand.int31() % 256), u8(rand.int31() % 256)}
    }

    pixels := make([]u8, IMAGE_WIDTH * IMAGE_HEIGHT * 4); defer delete(pixels)

    // Generate image
    for y in 0 ..< IMAGE_HEIGHT {
        for x in 0 ..< IMAGE_WIDTH {
            p := glm.vec2{f32(x), f32(y)}
            nearest := 0
            best_dist := glm.length(p - seeds[0].pos)

            for i in 1 ..< VORONOI_SEEDS {
                d := glm.length(p - seeds[i].pos)

                if d < best_dist {
                    best_dist = d
                    nearest = i
                }
            }

            idx := (y * IMAGE_WIDTH + x) * 4
            pixels[idx + 0] = seeds[nearest].color[0]
            pixels[idx + 1] = seeds[nearest].color[1]
            pixels[idx + 2] = seeds[nearest].color[2]
            pixels[idx + 3] = 255
        }
    }

    // Create texture
    tbo: u32; gl.GenTextures(1, &tbo); defer gl.DeleteTextures(1, &tbo)
    gl.BindTexture(gl.TEXTURE_2D, tbo)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, i32(IMAGE_WIDTH), i32(IMAGE_HEIGHT), 0, gl.RGBA, gl.UNSIGNED_BYTE, &pixels[0])
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
