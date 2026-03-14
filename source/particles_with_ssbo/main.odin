package example

import "core:fmt"
import rand "core:math/rand"
import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"
import gl "vendor:OpenGL"

WINDOW_TITLE :: "Particles With SSBO"
WINDOW_WIDTH :: 960
WINDOW_HEIGHT :: 540
GL_VERSION_MAJOR :: 4
GL_VERSION_MINOR :: 6

PARTICLE_CAP :: 1024
PARTICLE_POS_MIN :: f32(-256)
PARTICLE_POS_MAX :: f32(256)
PARTICLE_SPEED_MIN  :: f32(200)
PARTICLE_SPEED_MAX  :: f32(400)
PARTICLE_RADIUS_MIN :: f32(4)
PARTICLE_RADIUS_MAX :: f32(12)

// Compute pass: reads particle positions and velocities from SSBO, integrates motion, bounces off window edges
COMPUTE_SOURCE :: `#version 460 core
    layout(local_size_x = 64) in;

    struct Particle {
        vec2 position;
        vec2 velocity;
        float radius;
        int color;
    };

    layout(std430, binding = 0) buffer ParticleBuffer {
        Particle particles[];
    };

    uniform float u_delta_time;
    uniform vec2 u_bounds;

    void main() {
        uint i = gl_GlobalInvocationID.x;

        if (i >= particles.length()) {
            return;
        }

        particles[i].position += particles[i].velocity * u_delta_time;

        if (abs(particles[i].position.x) + particles[i].radius > u_bounds.x) {
            particles[i].velocity.x *= -1.0;
            particles[i].position.x = sign(particles[i].position.x) * (u_bounds.x - particles[i].radius);
        }

        if (abs(particles[i].position.y) + particles[i].radius > u_bounds.y) {
            particles[i].velocity.y *= -1.0;
            particles[i].position.y = sign(particles[i].position.y) * (u_bounds.y - particles[i].radius);
        }
    }
`

// Vertex shader: reads per-instance data from SSBO using gl_InstanceID instead of vertex attribs
VERTEX_SOURCE :: `#version 460 core
    struct Particle {
        vec2 position;
        vec2 velocity;
        float radius;
        int color;
    };

    layout(std430, binding = 0) readonly buffer ParticleBuffer {
        Particle particles[];
    };

    out vec2 v_tex_coord;
    out vec4 v_color;
    uniform mat4 u_projection;

    const vec2 positions[] = vec2[](
        vec2(-1.0, -1.0),
        vec2( 1.0, -1.0),
        vec2(-1.0,  1.0),
        vec2( 1.0,  1.0)
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
        Particle p = particles[gl_InstanceID];
        vec2 position = positions[gl_VertexID] * p.radius + p.position;

        gl_Position = u_projection * vec4(position, 0.0, 1.0);
        v_tex_coord = tex_coords[gl_VertexID];
        v_color = vec4(get_color(p.color), 1.0);
    }
`

FRAGMENT_SOURCE :: `#version 460 core
    in vec4 v_color;
    in vec2 v_tex_coord;
    out vec4 o_frag_color;

    void main() {
        vec2 cp = v_tex_coord * 2.0 - 1.0;
        float alpha = 1.0 - smoothstep(0.9, 1.0, length(cp));
        o_frag_color = vec4(v_color.rgb, alpha);
    }
`

Particle :: struct {
    position: glm.vec2,
    velocity: glm.vec2,
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

    viewport_x, viewport_y: i32; sdl.GetWindowSize(window, &viewport_x, &viewport_y)

    compute_program, compute_ok := gl.load_compute_source(COMPUTE_SOURCE)
    compute_uniforms := gl.get_uniforms_from_program(compute_program)

    if !compute_ok {
        fmt.printf("COMPUTE SHADER ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(compute_program)

    render_program, render_ok := gl.load_shaders_source(VERTEX_SOURCE, FRAGMENT_SOURCE)
    render_uniforms := gl.get_uniforms_from_program(render_program)

    if !render_ok {
        fmt.printf("RENDER SHADER ERROR: %s\n", gl.get_last_error_message())

        return
    }

    defer gl.DeleteProgram(render_program)

    particles: [PARTICLE_CAP]Particle

    for &p in particles {
        angle := rand.float32_range(0, glm.TAU)
        speed := rand.float32_range(PARTICLE_SPEED_MIN, PARTICLE_SPEED_MAX)

        p.position = {rand.float32_range(PARTICLE_POS_MIN, PARTICLE_POS_MAX), rand.float32_range(PARTICLE_POS_MIN, PARTICLE_POS_MAX)}
        p.velocity = {glm.cos(angle) * speed, glm.sin(angle) * speed}
        p.radius = rand.float32_range(PARTICLE_RADIUS_MIN, PARTICLE_RADIUS_MAX)
        p.color = random_color()
    }

    // Create SSBO - holds all particle data, written by compute shader, read by vertex shader
    ssbo: u32; gl.GenBuffers(1, &ssbo); defer gl.DeleteBuffers(1, &ssbo)
    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, ssbo)
    gl.BufferData(gl.SHADER_STORAGE_BUFFER, PARTICLE_CAP * size_of(Particle), &particles, gl.DYNAMIC_DRAW)
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, 0, ssbo)

    // Bind default vao, won't draw otherwise
    vao: u32; gl.GenVertexArrays(1, &vao); defer gl.DeleteVertexArrays(1, &vao)
    gl.BindVertexArray(vao)

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    prev_ticks := sdl.GetTicks()

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

        ticks := sdl.GetTicks()
        delta_time := f32(ticks - prev_ticks) / 1000.0
        prev_ticks = ticks

        bounds := glm.vec2{f32(viewport_x) / 2, f32(viewport_y) / 2}
        projection := glm.mat4Ortho3d(-bounds.x, bounds.x, -bounds.y, bounds.y, -1, 1)

        // Compute pass - update all particle positions in SSBO
        gl.UseProgram(compute_program)
        gl.Uniform1f(compute_uniforms["u_delta_time"].location, delta_time)
        gl.Uniform2f(compute_uniforms["u_bounds"].location, bounds.x, bounds.y)
        gl.DispatchCompute(u32((PARTICLE_CAP + 63) / 64), 1, 1)
        gl.MemoryBarrier(gl.SHADER_STORAGE_BARRIER_BIT)

        // Render pass - vertex shader reads from SSBO via gl_InstanceID, no vertex attributes
        gl.Viewport(0, 0, viewport_x, viewport_y)
        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.UseProgram(render_program)
        gl.UniformMatrix4fv(render_uniforms["u_projection"].location, 1, false, &projection[0][0])
        gl.DrawArraysInstanced(gl.TRIANGLE_STRIP, 0, 4, PARTICLE_CAP)

        sdl.GL_SwapWindow(window)
    }
}
