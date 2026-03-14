package example

import "core:fmt"
import "core:image"
import _ "core:image/jpeg"
import _ "core:image/png"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"
import gltf "vendor:cgltf"

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

Vertex :: struct {
    position: glm.vec3,
    normal: glm.vec3,
    uv: glm.vec2,
}

Primitive_GPU :: struct {
    vao, vbo, ibo: u32,
    texture_id: u32,
    index_count: i32,
}

Mesh_GPU :: struct {
    primitives: [dynamic]Primitive_GPU,
}

Model :: struct {
    mesh: int,
    transform: glm.mat4,
}

load_texture :: proc(img: ^gltf.image) -> u32 {
    if img == nil || img.buffer_view == nil {
        return 0
    }

    bv := img.buffer_view
    src := ([^]u8)(bv.buffer.data)[bv.offset : bv.offset + bv.size]

    loaded, err := image.load_from_bytes(src, {.alpha_add_if_missing})

    if err != nil {
        return 0
    }

    defer image.destroy(loaded)

    tex: u32
    gl.GenTextures(1, &tex)
    gl.BindTexture(gl.TEXTURE_2D, tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, i32(loaded.width), i32(loaded.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, &loaded.pixels.buf[0])
    gl.GenerateMipmap(gl.TEXTURE_2D)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)

    return tex
}

upload_mesh :: proc(mesh: ^gltf.mesh, texture_cache: ^map[rawptr]u32, white_tex: u32) -> Mesh_GPU {
    gpu_mesh: Mesh_GPU

    for &prim in mesh.primitives {
        if prim.type != .triangles || prim.indices == nil {
            continue
        }

        pos_acc, norm_acc, uv_acc: ^gltf.accessor

        for &attr in prim.attributes {
            #partial switch attr.type {
            case .position:
                pos_acc = attr.data
            case .normal:
                norm_acc = attr.data
            case .texcoord:
                if attr.index == 0 {
                    uv_acc = attr.data
                }
            }
        }

        if pos_acc == nil || norm_acc == nil {
            continue
        }

        vertex_count := pos_acc.count

        pos_floats := make([]f32, vertex_count * 3)
        defer delete(pos_floats)
        _ = gltf.accessor_unpack_floats(pos_acc, raw_data(pos_floats), vertex_count * 3)

        norm_floats := make([]f32, vertex_count * 3)
        defer delete(norm_floats)
        _ = gltf.accessor_unpack_floats(norm_acc, raw_data(norm_floats), vertex_count * 3)

        uv_floats := make([]f32, vertex_count * 2)
        defer delete(uv_floats)

        if uv_acc != nil {
            _ = gltf.accessor_unpack_floats(uv_acc, raw_data(uv_floats), vertex_count * 2)
        }

        vertices := make([]Vertex, vertex_count)
        defer delete(vertices)

        for i in 0 ..< int(vertex_count) {
            vertices[i].position = {pos_floats[i * 3], pos_floats[i * 3 + 1], pos_floats[i * 3 + 2]}
            vertices[i].normal = {norm_floats[i * 3], norm_floats[i * 3 + 1], norm_floats[i * 3 + 2]}
            vertices[i].uv = {uv_floats[i * 2], uv_floats[i * 2 + 1]}
        }

        index_count := prim.indices.count
        indices := make([]u32, index_count)
        defer delete(indices)
        _ = gltf.accessor_unpack_indices(prim.indices, raw_data(indices), size_of(u32), index_count)

        texture_id := white_tex

        if prim.material != nil {
            tex_view := prim.material.pbr_metallic_roughness.base_color_texture

            if tex_view.texture != nil && tex_view.texture.image_ != nil {
                key := rawptr(tex_view.texture.image_)

                if cached, found := texture_cache[key]; found {
                    texture_id = cached
                } else {
                    texture_id = load_texture(tex_view.texture.image_)

                    if texture_id == 0 {
                        texture_id = white_tex
                    }

                    texture_cache[key] = texture_id
                }
            }
        }

        gpu: Primitive_GPU
        gpu.index_count = i32(index_count)
        gpu.texture_id = texture_id

        gl.GenVertexArrays(1, &gpu.vao)
        gl.BindVertexArray(gpu.vao)

        gl.GenBuffers(1, &gpu.vbo)
        gl.BindBuffer(gl.ARRAY_BUFFER, gpu.vbo)
        gl.BufferData(gl.ARRAY_BUFFER, int(vertex_count) * size_of(Vertex), raw_data(vertices), gl.STATIC_DRAW)

        stride := i32(size_of(Vertex))
        gl.EnableVertexAttribArray(0)
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, offset_of(Vertex, position))
        gl.EnableVertexAttribArray(1)
        gl.VertexAttribPointer(1, 3, gl.FLOAT, gl.FALSE, stride, offset_of(Vertex, normal))
        gl.EnableVertexAttribArray(2)
        gl.VertexAttribPointer(2, 2, gl.FLOAT, gl.FALSE, stride, offset_of(Vertex, uv))

        gl.GenBuffers(1, &gpu.ibo)
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, gpu.ibo)
        gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, int(index_count) * size_of(u32), raw_data(indices), gl.STATIC_DRAW)

        append(&gpu_mesh.primitives, gpu)
    }

    return gpu_mesh
}

upload_node :: proc(node: ^gltf.node, models: ^[dynamic]Model, meshes: ^[dynamic]Mesh_GPU, mesh_cache: ^map[rawptr]int, texture_cache: ^map[rawptr]u32, white_tex: u32) {
    if node.mesh != nil {
        world: [16]f32
        gltf.node_transform_world(node, &world[0])

        mesh_index, found := mesh_cache[rawptr(node.mesh)]

        if !found {
            mesh_index = len(meshes)
            append(meshes, upload_mesh(node.mesh, texture_cache, white_tex))
            mesh_cache[rawptr(node.mesh)] = mesh_index
        }

        append(models, Model{
            mesh = mesh_index,
            transform = transmute(glm.mat4)world,
        })
    }

    for child in node.children {
        upload_node(child, models, meshes, mesh_cache, texture_cache, white_tex)
    }
}

load_model :: proc() -> (models: [dynamic]Model, meshes: [dynamic]Mesh_GPU, textures: [dynamic]u32, ok: bool) {
    options: gltf.options
    gltf_data, res := gltf.parse(options, raw_data(GLB_DATA), uint(len(GLB_DATA)))

    if res != .success {
        fmt.printf("GLTF parse error: %v\n", res)

        return
    }

    defer gltf.free(gltf_data)

    if gltf.load_buffers(options, gltf_data, nil) != .success {
        fmt.printf("GLTF load_buffers error\n")

        return
    }

    // White fallback texture (1x1 white pixel)
    white_pixel: [4]u8 = {255, 255, 255, 255}
    white_tex: u32
    gl.GenTextures(1, &white_tex)
    gl.BindTexture(gl.TEXTURE_2D, white_tex)
    gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, &white_pixel)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
    gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
    append(&textures, white_tex)

    mesh_cache: map[rawptr]int
    defer delete(mesh_cache)

    texture_cache: map[rawptr]u32
    defer delete(texture_cache)

    scene := gltf_data.scene

    if scene == nil && len(gltf_data.scenes) > 0 {
        scene = &gltf_data.scenes[0]
    }

    if scene != nil {
        for node in scene.nodes {
            upload_node(node, &models, &meshes, &mesh_cache, &texture_cache, white_tex)
        }
    }

    for _, tex_id in texture_cache {
        if tex_id != white_tex {
            append(&textures, tex_id)
        }
    }

    ok = len(models) > 0

    return
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
