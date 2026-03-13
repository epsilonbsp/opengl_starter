package example

import "core:fmt"
import rand "core:math/rand"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Shared Camera UBO"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

CAMERA_UBO_BINDING :: 0

SPHERE_CAP :: 2048
SPHERE_POS_MIN : f32 : -512
SPHERE_POS_MAX : f32 : 512
SPHERE_RADIUS_MIN : f32 : 2
SPHERE_RADIUS_MAX : f32 : 16

CUBE_VERTEX_SOURCE :: `#version 460 core
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in vec3 i_normal;
    out vec3 v_normal;
    out vec3 v_world_pos;

    layout(std140, binding = 0) uniform Camera {
        mat4 projection;
        mat4 view;
        vec3 view_pos;
        vec3 light_dir;
        float ambient;
    };

    uniform mat4 u_model;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        gl_Position = projection * view * world_pos;
        v_world_pos = world_pos.xyz;
        v_normal = mat3(transpose(inverse(u_model))) * i_normal;
    }
`

CUBE_FRAGMENT_SOURCE :: `#version 460 core
    in vec3 v_normal;
    in vec3 v_world_pos;
    out vec4 o_frag_color;

    layout(std140, binding = 0) uniform Camera {
        mat4 projection;
        mat4 view;
        vec3 view_pos;
        vec3 light_dir;
        float ambient;
    };

    const float SHININESS = 64.0;

    void main() {
        vec3 color = vec3(1.0, 0.5, 0.1);
        vec3 normal = normalize(v_normal);

        float diffuse = max(dot(normal, light_dir), 0.0);

        vec3 view_dir  = normalize(view_pos - v_world_pos);
        vec3 half_dir  = normalize(light_dir + view_dir);
        float specular = pow(max(dot(normal, half_dir), 0.0), SHININESS) * 0.5;

        o_frag_color = vec4(color * (ambient + diffuse) + specular, 1.0);
    }
`

SPHERES_VERTEX_SOURCE :: `#version 460 core
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in float i_radius;
    layout(location = 2) in int i_color;
    out vec4 v_color;
    out vec3 v_frag_vs;
    flat out vec3 v_center_vs;
    flat out float v_radius;

    layout(std140, binding = 0) uniform Camera {
        mat4 projection;
        mat4 view;
        vec3 view_pos;
        vec3 light_dir;
        float ambient;
    };

    // Unit cube — sphere of radius r fits inside cube of half-size r,
    // so the projected cube always covers the sphere silhouette from any angle
    const vec3 cube[14] = vec3[](
        vec3(-1, 1,-1), vec3( 1, 1,-1), vec3(-1,-1,-1), vec3( 1,-1,-1),
        vec3( 1,-1, 1), vec3( 1, 1,-1), vec3( 1, 1, 1),
        vec3(-1, 1,-1), vec3(-1, 1, 1),
        vec3(-1,-1,-1), vec3(-1,-1, 1),
        vec3( 1,-1, 1), vec3(-1, 1, 1), vec3( 1, 1, 1)
    );

    vec3 get_color(int color) {
        return vec3(
            (color >> 16) & 0xFF,
            (color >> 8) & 0xFF,
            color & 0xFF
        ) / 255.0;
    }

    void main() {
        v_center_vs = (view * vec4(i_position, 1.0)).xyz;
        v_radius = i_radius;

        vec3 position = i_position + cube[gl_VertexID] * i_radius;
        v_frag_vs = (view * vec4(position, 1.0)).xyz;

        gl_Position = projection * vec4(v_frag_vs, 1.0);
        v_color = vec4(get_color(i_color), 1.0);
    }
`

SPHERES_FRAGMENT_SOURCE :: `#version 460 core
    in vec4 v_color;
    in vec3 v_frag_vs;
    flat in vec3 v_center_vs;
    flat in float v_radius;
    out vec4 o_frag_color;

    layout(std140, binding = 0) uniform Camera {
        mat4 projection;
        mat4 view;
        vec3 view_pos;
        vec3 light_dir;
        float ambient;
    };

    const float SHININESS = 64.0;

    void main() {
        // Ray from camera (view-space origin) through the cube surface fragment
        vec3 ray_dir = normalize(v_frag_vs);

        // Ray-sphere intersection: t^2 - 2bt + (|c|^2 - r^2) = 0
        float b    = dot(ray_dir, v_center_vs);
        float disc = b * b - dot(v_center_vs, v_center_vs) + v_radius * v_radius;

        if (disc < 0.0) {
            discard;
        }

        float t      = b - sqrt(disc);
        vec3  hit_vs = t * ray_dir;

        // True sphere surface normal at hit point (view space → world space)
        mat3 cam_to_world = transpose(mat3(view));
        vec3 normal   = cam_to_world * normalize(hit_vs - v_center_vs);
        vec3 view_dir = cam_to_world * normalize(-hit_vs);

        // Correct depth from actual sphere surface
        vec4 clip_pos = projection * vec4(hit_vs, 1.0);
        gl_FragDepth  = (clip_pos.z / clip_pos.w) * 0.5 + 0.5;

        vec3 light    = normalize(light_dir);
        vec3 half_dir = normalize(light + view_dir);

        float diffuse  = max(dot(normal, light), 0.0);
        float specular = pow(max(dot(normal, half_dir), 0.0), SHININESS) * 0.5;

        o_frag_color = vec4(v_color.rgb * (ambient + diffuse) + specular, 1.0);
    }
`

Camera_UBO :: struct {
    projection: glm.mat4,
    view:       glm.mat4,
    view_pos:   glm.vec3,
    _pad0:      f32,
    light_dir:  glm.vec3,
    ambient:    f32,
}

Sphere :: struct {
    position: glm.vec3,
    radius:   f32,
    color:    i32,
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
    time_delta: f32 = 0
    time_last := time

    camera: Camera; init_camera(&camera)
    movement_speed: f32 = 30
    yaw_speed: f32 = 0.002
    pitch_speed: f32 = 0.002

    // Cube shader
    cube_program, cube_ok := gl.load_shaders_source(CUBE_VERTEX_SOURCE, CUBE_FRAGMENT_SOURCE)
    cube_uniforms := gl.get_uniforms_from_program(cube_program)

    if !cube_ok {
        fmt.printf("CUBE SHADER LOAD ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(cube_program)

    // Sphere shader
    spheres_program, spheres_ok := gl.load_shaders_source(SPHERES_VERTEX_SOURCE, SPHERES_FRAGMENT_SOURCE)

    if !spheres_ok {
        fmt.printf("SPHERE SHADER LOAD ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(spheres_program)

    // UBO shared between both programs
    ubo: u32; gl.GenBuffers(1, &ubo); defer gl.DeleteBuffers(1, &ubo)
    gl.BindBuffer(gl.UNIFORM_BUFFER, ubo)
    gl.BufferData(gl.UNIFORM_BUFFER, size_of(Camera_UBO), nil, gl.DYNAMIC_DRAW)
    gl.BindBufferBase(gl.UNIFORM_BUFFER, CAMERA_UBO_BINDING, ubo)

    // Cube data: 24 vertices (4 per face, 6 faces) with per-face normals
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
        {{-0.5,  0.5,  0.5}, {0, 0,  1}}
    }

    cube_indices := []u16 {
        0,  1,  2,   0,  2,  3,
        4,  5,  6,   4,  6,  7,
        8,  9, 10,   8, 10, 11,
        12, 13, 14,  12, 14, 15,
        16, 17, 18,  16, 18, 19,
        20, 21, 22,  20, 22, 23
    }

    cube_index_count := len(cube_indices)

    // Cube VAO
    cube_vao: u32; gl.GenVertexArrays(1, &cube_vao); defer gl.DeleteVertexArrays(1, &cube_vao)
    gl.BindVertexArray(cube_vao)

    cube_vbo: u32; gl.GenBuffers(1, &cube_vbo); defer gl.DeleteBuffers(1, &cube_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, cube_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(cube_vertices), &cube_vertices, gl.STATIC_DRAW)
    gl.BufferData(gl.ARRAY_BUFFER, len(cube_vertices) * size_of(cube_vertices[0]), &cube_vertices[0], gl.STATIC_DRAW)

    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of([2]glm.vec3), 0)

    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, size_of([2]glm.vec3), size_of(glm.vec3))

    cube_ibo: u32; gl.GenBuffers(1, &cube_ibo); defer gl.DeleteBuffers(1, &cube_ibo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, cube_ibo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, len(cube_indices) * size_of(cube_indices[0]), &cube_indices[0], gl.STATIC_DRAW)

    // Sphere data
    spheres: [SPHERE_CAP]Sphere

    for &p in spheres {
        p.position = {rand.float32_range(SPHERE_POS_MIN, SPHERE_POS_MAX), rand.float32_range(SPHERE_POS_MIN, SPHERE_POS_MAX), rand.float32_range(SPHERE_POS_MIN, SPHERE_POS_MAX)}
        p.radius = rand.float32_range(SPHERE_RADIUS_MIN, SPHERE_RADIUS_MAX)
        p.color = random_color()
    }

    // Sphere VAO
    spheres_vao: u32; gl.GenVertexArrays(1, &spheres_vao); defer gl.DeleteVertexArrays(1, &spheres_vao)
    gl.BindVertexArray(spheres_vao)

    spheres_vbo: u32; gl.GenBuffers(1, &spheres_vbo); defer gl.DeleteBuffers(1, &spheres_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, spheres_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(spheres), &spheres, gl.STATIC_DRAW)

    offset: i32 = 0
    gl.EnableVertexAttribArray(0)
    gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, size_of(Sphere), auto_cast offset)
    gl.VertexAttribDivisor(0, 1)

    offset += size_of(glm.vec3)
    gl.EnableVertexAttribArray(1)
    gl.VertexAttribPointer(1, 1, gl.FLOAT, gl.FALSE, size_of(Sphere), auto_cast offset)
    gl.VertexAttribDivisor(1, 1)

    offset += size_of(f32)
    gl.EnableVertexAttribArray(2)
    gl.VertexAttribIPointer(2, 1, gl.INT, size_of(Sphere), auto_cast offset)
    gl.VertexAttribDivisor(2, 1)

    light_dir := glm.normalize(glm.vec3{1, 2, 3})
    cube_model := glm.mat4Scale({32, 32, 32})

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

        if (sdl.GetWindowRelativeMouseMode(window)) {
            fly_camera(
                &camera,
                {key_state[sdl.Scancode.A], key_state[sdl.Scancode.D], key_state[sdl.Scancode.S], key_state[sdl.Scancode.W]},
                time_delta * movement_speed
            )
        }

        compute_camera_projection(&camera, f32(viewport_x) / f32(viewport_y))
        compute_camera_view(&camera)

        // Upload once — both programs read from the same UBO
        camera_data := Camera_UBO{
            projection = camera.projection,
            view       = camera.view,
            view_pos   = camera.position,
            light_dir  = light_dir,
            ambient    = 0.2,
        }
        gl.BindBuffer(gl.UNIFORM_BUFFER, ubo)
        gl.BufferSubData(gl.UNIFORM_BUFFER, 0, size_of(Camera_UBO), &camera_data)

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0, 0, 0, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        // Render cube
        gl.UseProgram(cube_program)
        gl.UniformMatrix4fv(cube_uniforms["u_model"].location, 1, false, &cube_model[0][0])
        gl.BindVertexArray(cube_vao)
        gl.DrawElements(gl.TRIANGLES, i32(cube_index_count), gl.UNSIGNED_SHORT, nil)

        // Render spheres
        gl.UseProgram(spheres_program)
        gl.BindVertexArray(spheres_vao)
        gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 14, SPHERE_CAP)

        sdl.GL_SwapWindow(window)
    }
}
