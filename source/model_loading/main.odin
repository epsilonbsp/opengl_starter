package example

import "core:fmt"
import _ "core:image/jpeg"
import _ "core:image/png"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Model Loading"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

VERTEX_SOURCE :: `#version 460 core
    layout(location = 0) in vec3 i_position;
    layout(location = 1) in vec3 i_normal;
    layout(location = 2) in vec2 i_tex_coord;

    out vec3 v_normal;
    out vec2 v_tex_coord;
    out vec3 v_world_pos;

    uniform mat4 u_projection;
    uniform mat4 u_view;
    uniform mat4 u_model;

    void main() {
        vec4 world_pos = u_model * vec4(i_position, 1.0);

        gl_Position = u_projection * u_view * world_pos;
        v_normal = mat3(transpose(inverse(u_model))) * i_normal;
        v_tex_coord = i_tex_coord;
        v_world_pos = world_pos.xyz;
    }
`

FRAGMENT_SOURCE :: `#version 460 core
    in vec3 v_normal;
    in vec2 v_tex_coord;
    in vec3 v_world_pos;

    out vec4 o_frag_color;

    uniform sampler2D u_base_color;
    uniform vec3 u_view_pos;
    uniform vec3 u_light_dir;
    uniform float u_ambient;
    uniform float u_shininess;

    void main() {
        vec3 normal = normalize(v_normal);
        vec3 view_dir = normalize(u_view_pos - v_world_pos);
        vec3 half_dir = normalize(u_light_dir + view_dir);

        vec3 base_color = texture(u_base_color, v_tex_coord).rgb;
        float diffuse = max(dot(normal, u_light_dir), 0.0);
        float specular = pow(max(dot(normal, half_dir), 0.0), u_shininess) * 0.5;

        o_frag_color = vec4(base_color * (u_ambient + diffuse) + specular, 1.0);
    }
`

// Source: https://polyhaven.com/a/Camera_01
GLB_DATA :: #load("model.glb")

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
    time_delta : f32 = 0
    time_last := time
    time_elapsed : f32 = 0

    camera: Camera
    init_camera(&camera)
    camera.position = {0, 0, 1}

    movement_speed: f32 = 1
    yaw_speed: f32 = 0.002
    pitch_speed: f32 = 0.002

    program, program_status := gl.load_shaders_source(VERTEX_SOURCE, FRAGMENT_SOURCE)
    uniforms := gl.get_uniforms_from_program(program)

    if !program_status {
        fmt.printf("SHADER LOAD ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(program)

    models, meshes, textures, ok := load_model()

    if !ok {
        fmt.printf("Failed to load model\n")

        return
    }

    defer {
        for &mesh in meshes {
            for &p in mesh.primitives {
                gl.DeleteVertexArrays(1, &p.vao)
                gl.DeleteBuffers(1, &p.vbo)
                gl.DeleteBuffers(1, &p.ibo)
            }

            delete(mesh.primitives)
        }

        delete(meshes)
        delete(models)

        for &tex in textures {
            gl.DeleteTextures(1, &tex)
        }

        delete(textures)
    }

    light_dir := glm.normalize(glm.vec3{1, 2, 3})
    shininess: f32 = 64.0
    ambient: f32 = 0.2

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

        if sdl.GetWindowRelativeMouseMode(window) {
            fly_camera(
                &camera,
                {key_state[sdl.Scancode.A], key_state[sdl.Scancode.D], key_state[sdl.Scancode.S], key_state[sdl.Scancode.W]},
                time_delta * movement_speed
            )
        }

        compute_camera_projection(&camera, f32(viewport_x) / f32(viewport_y))
        compute_camera_view(&camera)

        root_transform := glm.mat4Scale({5, 5, 5}) * glm.mat4Rotate({0, 1, 0}, time_elapsed * 0.5)

        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0.1, 0.1, 0.1, 1.0)
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)

        gl.UseProgram(program)
        gl.UniformMatrix4fv(uniforms["u_projection"].location, 1, false, &camera.projection[0][0])
        gl.UniformMatrix4fv(uniforms["u_view"].location, 1, false, &camera.view[0][0])
        gl.Uniform3f(uniforms["u_light_dir"].location, light_dir.x, light_dir.y, light_dir.z)
        gl.Uniform3f(uniforms["u_view_pos"].location, camera.position.x, camera.position.y, camera.position.z)
        gl.Uniform1f(uniforms["u_shininess"].location, shininess)
        gl.Uniform1f(uniforms["u_ambient"].location, ambient)
        gl.Uniform1i(uniforms["u_base_color"].location, 0)

        for &model in models {
            mesh := &meshes[model.mesh]
            transform := root_transform * model.transform

            gl.UniformMatrix4fv(uniforms["u_model"].location, 1, false, &transform[0][0])

            for &prim in mesh.primitives {
                gl.ActiveTexture(gl.TEXTURE0)
                gl.BindTexture(gl.TEXTURE_2D, prim.texture_id)
                gl.BindVertexArray(prim.vao)
                gl.DrawElements(gl.TRIANGLES, prim.index_count, gl.UNSIGNED_INT, nil)
            }
        }

        sdl.GL_SwapWindow(window)
    }
}
