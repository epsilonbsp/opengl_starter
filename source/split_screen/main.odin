package example

import "core:fmt"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Split Screen"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

CAMERA_UBO_BINDING :: 0

GRID_DIM   :: 4
CUBE_COUNT :: GRID_DIM * GRID_DIM * GRID_DIM

VERTEX_SOURCE :: `#version 460 core
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in vec3 i_normal;
    layout(location = 2) in mat4 i_model;

    out vec3 v_normal;
    out vec3 v_world_pos;

    layout(std140, binding = 0) uniform Camera {
        mat4 projection;
        mat4 view;
        vec3 view_pos;
        float _pad0;
        vec3 light_dir;
        float ambient;
    };

    void main() {
        vec4 world_pos = i_model * vec4(i_position, 1.0);

        gl_Position = projection * view * world_pos;
        v_world_pos = world_pos.xyz;
        v_normal = mat3(transpose(inverse(i_model))) * i_normal;
    }
`

COLOR_FRAGMENT_SOURCE :: `#version 460 core
    in vec3 v_normal;
    in vec3 v_world_pos;

    out vec4 o_frag_color;

    layout(std140, binding = 0) uniform Camera {
        mat4 projection;
        mat4 view;
        vec3 view_pos;
        float _pad0;
        vec3 light_dir;
        float ambient;
    };

    const float SHININESS = 64.0;

    void main() {
        vec3 color = vec3(1.0, 0.5, 0.1);
        vec3 normal = normalize(v_normal);

        float diffuse = max(dot(normal, light_dir), 0.0);

        vec3 view_dir = normalize(view_pos - v_world_pos);
        vec3 half_dir = normalize(light_dir + view_dir);
        float specular = pow(max(dot(normal, half_dir), 0.0), SHININESS) * 0.5;

        o_frag_color = vec4(color * (ambient + diffuse) + specular, 1.0);
    }
`

// Linearizes the nonlinear depth buffer value to a 0-1 range (0=near, 1=far).
// Without linearization, almost all depth budget goes to near objects — the
// cube would appear nearly white even at distance, hiding the gradient.
DEPTH_FRAGMENT_SOURCE :: `#version 460 core
    out vec4 o_frag_color;

    uniform float u_near;
    uniform float u_far;

    void main() {
        float z_ndc = gl_FragCoord.z * 2.0 - 1.0;
        float z_eye = (2.0 * u_near * u_far) / (u_far + u_near - z_ndc * (u_far - u_near));
        float linear_depth = (z_eye - u_near) / (u_far - u_near);

        o_frag_color = vec4(vec3(linear_depth), 1.0);
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

Camera_UBO :: struct {
    projection: glm.mat4,
    view:       glm.mat4,
    view_pos:   glm.vec3,
    _pad0:      f32,
    light_dir:  glm.vec3,
    ambient:    f32,
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
    _ = sdl.SetWindowRelativeMouseMode(window, true)

    viewport_x, viewport_y: i32
    sdl.GetWindowSize(window, &viewport_x, &viewport_y)
    key_state := sdl.GetKeyboardState(nil)
    time: u64 = sdl.GetTicks()
    time_delta: f32 = 0
    time_last := time

    camera: Camera
    init_camera(&camera)
    camera.position = {0, 0, 3}
    camera.near = 0.1
    camera.far = 10

    movement_speed: f32 = 5
    yaw_speed: f32 = 0.002
    pitch_speed: f32 = 0.002

    color_program, color_ok := gl.load_shaders_source(VERTEX_SOURCE, COLOR_FRAGMENT_SOURCE)

    if !color_ok {
        fmt.printf("COLOR SHADER ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(color_program)

    depth_program, depth_ok := gl.load_shaders_source(VERTEX_SOURCE, DEPTH_FRAGMENT_SOURCE)

    if !depth_ok {
        fmt.printf("DEPTH SHADER ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(depth_program)

    depth_uniforms := gl.get_uniforms_from_program(depth_program)

    ubo: u32
    gl.GenBuffers(1, &ubo)
    defer gl.DeleteBuffers(1, &ubo)
    gl.BindBuffer(gl.UNIFORM_BUFFER, ubo)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(Camera_UBO), nil, gl.DYNAMIC_DRAW)
    gl.BindBufferBase(gl.UNIFORM_BUFFER, CAMERA_UBO_BINDING, ubo)

    vao: u32
    gl.GenVertexArrays(1, &vao)
    defer gl.DeleteVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    vbo: u32
    gl.GenBuffers(1, &vbo)
    defer gl.DeleteBuffers(1, &vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, len(cube_vertices) * size_of(cube_vertices[0]), &cube_vertices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of([2]glm.vec3), 0)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of([2]glm.vec3), size_of(glm.vec3))

    ibo: u32
    gl.GenBuffers(1, &ibo)
    defer gl.DeleteBuffers(1, &ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(cube_indices) * size_of(cube_indices[0]), &cube_indices[0], gl.STATIC_DRAW)

    // 4x4x4 grid of cubes centered in XY, receding in Z.
    // Camera is at (0, 0, 3) looking at -Z; Z layers at 0, -1.5, -3, -4.5 (distances 3–7.5, within far=10).
    instance_models: [CUBE_COUNT]glm.mat4

    spacing: f32 = 2
    half := f32(GRID_DIM - 1) / 2.0

    for i in 0 ..< CUBE_COUNT {
        xi := i % GRID_DIM
        yi := (i / GRID_DIM) % GRID_DIM
        zi := i / (GRID_DIM * GRID_DIM)

        pos := glm.vec3{
            (f32(xi) - half) * spacing,
            (f32(yi) - half) * spacing,
            -f32(zi) * spacing,
        }

        instance_models[i] = glm.mat4Translate(pos)
    }

    instance_vbo: u32
    gl.GenBuffers(1, &instance_vbo)
    defer gl.DeleteBuffers(1, &instance_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, instance_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(instance_models), &instance_models, gl.STATIC_DRAW)

    // mat4 occupies 4 consecutive attribute locations (one vec4 per column)
    for col in 0 ..< 4 {
        loc := u32(2 + col)
        gl.EnableVertexAttribArray(loc)
        gl.VertexAttribPointer(loc, 4, gl.FLOAT, gl.FALSE, size_of(glm.mat4), uintptr(col * size_of(glm.vec4)))
        gl.VertexAttribDivisor(loc, 1)
    }

    light_dir := glm.normalize(glm.vec3{1, 2, 3})
    index_count := len(cube_indices)

    gl.Enable(gl.DEPTH_TEST)
    gl.Enable(gl.CULL_FACE)

    loop: for {
        time = sdl.GetTicks()
        time_delta = f32(time - time_last) / 1000
        time_last = time

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

        if sdl.GetWindowRelativeMouseMode(window) {
            fly_camera(
                &camera,
                {key_state[sdl.Scancode.A], key_state[sdl.Scancode.D], key_state[sdl.Scancode.S], key_state[sdl.Scancode.W]},
                time_delta * movement_speed,
            )
        }

        half_w := viewport_x / 2
        aspect := f32(half_w) / f32(viewport_y)

        compute_camera_projection(&camera, aspect)
        compute_camera_view(&camera)

        camera_data := Camera_UBO{
            projection = camera.projection,
            view       = camera.view,
            view_pos   = camera.position,
            light_dir  = light_dir,
            ambient    = 0.2,
        }

        gl.BindBuffer(gl.UNIFORM_BUFFER, ubo)
        gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(Camera_UBO), &camera_data)

        // Full clear before scissor is enabled — glClear respects scissor rect,
        // so clearing without it resets the whole framebuffer in one pass.
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.1, 0.1, 0.1, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.Enable(gl.SCISSOR_TEST)
        gl.BindVertexArray(vao)

        // Left half: color
        gl.Scissor(0, 0, half_w, viewport_y)
        gl.Viewport(0, 0, half_w, viewport_y)
        gl.UseProgram(color_program)
        gl.DrawElementsInstanced(gl.TRIANGLES, i32(index_count), gl.UNSIGNED_SHORT, nil, CUBE_COUNT)

        // Right half: linearized depth
        gl.Scissor(half_w, 0, viewport_x - half_w, viewport_y)
        gl.Viewport(half_w, 0, viewport_x - half_w, viewport_y)
        gl.UseProgram(depth_program)
        gl.Uniform1f(depth_uniforms["u_near"].location, camera.near)
        gl.Uniform1f(depth_uniforms["u_far"].location, camera.far)
        gl.DrawElementsInstanced(gl.TRIANGLES, i32(index_count), gl.UNSIGNED_SHORT, nil, CUBE_COUNT)

        gl.Disable(gl.SCISSOR_TEST)

        sdl.GL_SwapWindow(window)
    }
}
