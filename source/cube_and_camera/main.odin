package example

import "core:fmt"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Camera And Camera"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

VERTEX_SOURCE :: `#version 460 core
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in vec3 i_normal;

    out vec3 v_normal;
    out vec3 v_world_pos;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        gl_Position = u_projection * u_view * world_pos;
        v_world_pos = world_pos.xyz;
        v_normal = mat3(transpose(inverse(u_model))) * i_normal;
    }
`

FRAGMENT_SOURCE :: `#version 460 core
    in vec3 v_normal;
    in vec3 v_world_pos;
    out vec4 o_frag_color;

    uniform vec3 u_light_dir;
    uniform vec3 u_view_pos;

    const float SHININESS = 64.0;

    void main() {
        vec3 color = vec3(1.0, 0.5, 0.1);
        vec3 normal = normalize(v_normal);

        float ambient = 0.2;
        float diffuse = max(dot(normal, u_light_dir), 0.0);

        vec3 view_dir = normalize(u_view_pos - v_world_pos);
        vec3 half_dir = normalize(u_light_dir + view_dir);
        float specular = pow(max(dot(normal, half_dir), 0.0), SHININESS) * 0.5;

        o_frag_color = vec4(color * (ambient + diffuse) + specular, 1.0);
    }
`

// 24 vertices (4 per face, 6 faces) with per-face normals
cube_vertices := [][2]glm.vec3 {
    // left
    {{-0.5, -0.5, -0.5}, {-1, 0, 0}},
    {{-0.5, -0.5,  0.5}, {-1, 0, 0}},
    {{-0.5,  0.5,  0.5}, {-1, 0, 0}},
    {{-0.5,  0.5, -0.5}, {-1, 0, 0}},
    // right
    {{ 0.5, -0.5,  0.5}, {1, 0, 0}},
    {{ 0.5, -0.5, -0.5}, {1, 0, 0}},
    {{ 0.5,  0.5, -0.5}, {1, 0, 0}},
    {{ 0.5,  0.5,  0.5}, {1, 0, 0}},
    // bottom
    {{-0.5, -0.5, -0.5}, {0, -1, 0}},
    {{ 0.5, -0.5, -0.5}, {0, -1, 0}},
    {{ 0.5, -0.5,  0.5}, {0, -1, 0}},
    {{-0.5, -0.5,  0.5}, {0, -1, 0}},
    // top
    {{-0.5,  0.5,  0.5}, {0, 1, 0}},
    {{ 0.5,  0.5,  0.5}, {0, 1, 0}},
    {{ 0.5,  0.5, -0.5}, {0, 1, 0}},
    {{-0.5,  0.5, -0.5}, {0, 1, 0}},
    // back
    {{ 0.5, -0.5, -0.5}, {0, 0, -1}},
    {{-0.5, -0.5, -0.5}, {0, 0, -1}},
    {{-0.5,  0.5, -0.5}, {0, 0, -1}},
    {{ 0.5,  0.5, -0.5}, {0, 0, -1}},
    // front
    {{-0.5, -0.5,  0.5}, {0, 0,  1}},
    {{ 0.5, -0.5,  0.5}, {0, 0,  1}},
    {{ 0.5,  0.5,  0.5}, {0, 0,  1}},
    {{-0.5,  0.5,  0.5}, {0, 0,  1}},
}

cube_indices := []u16 {
     0,  1,  2,   0,  2,  3,
     4,  5,  6,   4,  6,  7,
     8,  9, 10,   8, 10, 11,
    12, 13, 14,  12, 14, 15,
    16, 17, 18,  16, 18, 19,
    20, 21, 22,  20, 22, 23,
}

index_count := len(cube_indices)

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
    _ = sdl.SetWindowRelativeMouseMode(window, true)

    viewport_x, viewport_y: i32; sdl.GetWindowSize(window, &viewport_x, &viewport_y)
    key_state := sdl.GetKeyboardState(nil)
    time: u64 = sdl.GetTicks()
    time_delta : f32 = 0
    time_last := time
    time_elapsed : f32 = 0

    camera: Camera; init_camera(&camera)
    movement_speed: f32 = 5
    yaw_speed: f32 = 0.002
    pitch_speed: f32 = 0.002

    program, program_status := gl.load_shaders_source(VERTEX_SOURCE, FRAGMENT_SOURCE)
    uniforms := gl.get_uniforms_from_program(program)

    if !program_status {
        fmt.printf("SHADER LOAD ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(program)

    vao: u32; gl.GenVertexArrays(1, &vao); defer gl.DeleteVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    vbo: u32; gl.GenBuffers(1, &vbo); defer gl.DeleteBuffers(1, &vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(cube_vertices) * size_of(cube_vertices[0]), &cube_vertices[0], gl.STATIC_DRAW)

    offset: f32 = 0
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of([2]glm.vec3), auto_cast offset)

    offset += size_of(glm.vec3)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of([2]glm.vec3), auto_cast offset)

    ibo: u32; gl.GenBuffers(1, &ibo); defer gl.DeleteBuffers(1, &ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(cube_indices) * size_of(cube_indices[0]), &cube_indices[0], gl.STATIC_DRAW)

    light_dir := glm.normalize(glm.vec3{1, 2, 3})

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

    loop: for {
        time = sdl.GetTicks()
        time_delta = f32(time - time_last) / 1000
        time_last = time
        time_elapsed += time_delta

        event: sdl.Event

        for sdl.PollEvent(&event) {
            #partial switch event.type {
            case .QUIT:
                break loop
            case .WINDOW_RESIZED:
                sdl.GetWindowSize(window, &viewport_x, &viewport_y)
            case .KEY_DOWN:
                if event.key.scancode == sdl.Scancode.ESCAPE {
                    _ = sdl.SetWindowRelativeMouseMode(window, !sdl.GetWindowRelativeMouseMode(window))
                }
            case .MOUSE_MOTION:
                if sdl.GetWindowRelativeMouseMode(window) {
                    rotate_camera(&camera, event.motion.xrel * yaw_speed, event.motion.yrel * pitch_speed, 0)
                }
            }
        }

        if (sdl.GetWindowRelativeMouseMode(window)) {
            fly_camera(
                &camera,
                {key_state[sdl.Scancode.A], key_state[sdl.Scancode.D], key_state[sdl.Scancode.S], key_state[sdl.Scancode.W]},
                time_delta * movement_speed
            )
        }

        compute_camera_projection(&camera, f32(viewport_x) / f32(viewport_y))
        compute_camera_view(&camera)

        model := glm.mat4Rotate({1, 1, 0}, time_elapsed / 10.0)

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.1, 0.1, 0.1, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.UseProgram(program)
        gl.UniformMatrix4fv(uniforms["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(uniforms["u_view"].location, 1, false, &camera.view[0][0])
        gl.UniformMatrix4fv(uniforms["u_model"].location, 1, false, &model[0][0])
        gl.Uniform3f(uniforms["u_light_dir"].location, light_dir.x, light_dir.y, light_dir.z)
        gl.Uniform3f(uniforms["u_view_pos"].location, camera.position.x, camera.position.y, camera.position.z)
        gl.BindVertexArray(vao)
        gl.DrawElements(gl.TRIANGLES, i32(index_count), gl.UNSIGNED_SHORT, nil)

        sdl.GL_SwapWindow(window)
    }
}
