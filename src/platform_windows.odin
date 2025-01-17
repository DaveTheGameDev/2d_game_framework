package main

device:     ^D3D11.IDevice
device_ctx: ^D3D11.IDeviceContext
swapchain:  ^DXGI.ISwapChain1

rasterizer_state: ^D3D11.IRasterizerState
sampler_state:    ^D3D11.ISamplerState
blend_state:      ^D3D11.IBlendState

vertex_buffer:   ^D3D11.IBuffer
index_buffer:    ^D3D11.IBuffer
constant_buffer: ^D3D11.IBuffer

vertex_shader: ^D3D11.IVertexShader
pixel_shader:  ^D3D11.IPixelShader
input_layout:  ^D3D11.IInputLayout

atlas_texture:         DX11Texture
main_render_texture:   DX11Texture
screen_render_texture: DX11Texture

GlobalConstants :: struct #align(16) {
    scissor_rect: vec4,
    screen_res:   vec2,
}

DX11Texture :: struct {
    texture:             ^D3D11.ITexture2D,
    texture_view:        ^D3D11.IShaderResourceView,
    render_texture_view: ^D3D11.IRenderTargetView,
    width, height: int,
}

_graphics_init :: proc() -> () {
    result: D3D11.HRESULT

    feature_levels := [?]D3D11.FEATURE_LEVEL{._11_0, ._11_1}
    device_flags: D3D11.CREATE_DEVICE_FLAGS
    device_flags = {.BGRA_SUPPORT}
    when ODIN_DEBUG {
        device_flags = device_flags + { .DEBUG }
    }

    dxgi_device:  ^DXGI.IDevice
    dxgi_adapter: ^DXGI.IAdapter
    dxgi_factory: ^DXGI.IFactory2

    defer safe_free(dxgi_device)
    defer safe_free(dxgi_adapter)
    defer safe_free(dxgi_factory)

    // BOILERPLATE DEVICE CREATION
    {
        base_device:         ^D3D11.IDevice
        base_device_context: ^D3D11.IDeviceContext

        defer safe_free(base_device)
        defer safe_free(base_device_context)

        result = D3D11.CreateDevice(nil, .HARDWARE, nil, device_flags, &feature_levels[0], len(feature_levels), D3D11.SDK_VERSION, &base_device, nil, &base_device_context)
        CHECK_RES_REQUIRED(result)

        result = base_device->QueryInterface(D3D11.IDevice_UUID, (^rawptr)(&device))
        CHECK_RES_REQUIRED(result)

        result = base_device_context->QueryInterface(D3D11.IDeviceContext_UUID, (^rawptr)(&device_ctx))
        CHECK_RES_REQUIRED(result)

        result = device->QueryInterface(DXGI.IDevice_UUID, (^rawptr)(&dxgi_device))
        CHECK_RES_REQUIRED(result)

        result = dxgi_device->GetAdapter(&dxgi_adapter)
        CHECK_RES_REQUIRED(result)

        result = dxgi_adapter->GetParent(DXGI.IFactory2_UUID, (^rawptr)(&dxgi_factory))
        CHECK_RES_REQUIRED(result)
    }

    {
        swapchain_desc := DXGI.SWAP_CHAIN_DESC1 {
            Width       = u32(app_state.gfx.window_width),
            Height      = u32(app_state.gfx.window_height),
            Format      = .B8G8R8A8_UNORM_SRGB,
            Stereo      = false,
            SampleDesc  = {Count = 1, Quality = 0},
            BufferUsage = {.RENDER_TARGET_OUTPUT},
            BufferCount = 2,
            Scaling     = .STRETCH,
            SwapEffect  = .DISCARD,
            AlphaMode   = .UNSPECIFIED,
            Flags       = {},
        }

        result = dxgi_factory->CreateSwapChainForHwnd(device, window, &swapchain_desc, nil, nil, &swapchain)
        CHECK_RES_REQUIRED(result)
    }

    {
        blend_desc: D3D11.BLEND_DESC
        blend_desc.RenderTarget[0].BlendEnable           = true
        blend_desc.RenderTarget[0].SrcBlend              = .SRC_ALPHA
        blend_desc.RenderTarget[0].DestBlend             = .INV_SRC_ALPHA
        blend_desc.RenderTarget[0].BlendOp               = .ADD
        blend_desc.RenderTarget[0].SrcBlendAlpha         = .ONE
        blend_desc.RenderTarget[0].DestBlendAlpha        = .INV_SRC_ALPHA
        blend_desc.RenderTarget[0].BlendOpAlpha          = .ADD
        blend_desc.RenderTarget[0].RenderTargetWriteMask = u8(D3D11.COLOR_WRITE_ENABLE_ALL)

        result = device->CreateBlendState(&blend_desc, &blend_state)
        CHECK_RES_REQUIRED(result)
        _set_debug_name(blend_state, "main_blend_state")
    }

    {
        rasterizer_desc := D3D11.RASTERIZER_DESC {
            FillMode = .SOLID,
            CullMode = .BACK,
            FrontCounterClockwise = false,
            ScissorEnable = false,
        }
        result = device->CreateRasterizerState(&rasterizer_desc, &rasterizer_state)
        CHECK_RES_REQUIRED(result)
        _set_debug_name(rasterizer_state, "main_rasterizer_state")

        sampler_desc := D3D11.SAMPLER_DESC {
            Filter         = .MIN_MAG_MIP_POINT,
            AddressU       = .WRAP,
            AddressV       = .WRAP,
            AddressW       = .WRAP,
            ComparisonFunc = .NEVER,
        }
        result = device->CreateSamplerState(&sampler_desc, &sampler_state)
        CHECK_RES_REQUIRED(result)
        _set_debug_name(sampler_state, "main_sampler_state")
    }

    // Generate vertex buffer for da quads
    {
        vertex_buffer_desc := D3D11.BUFFER_DESC {
            ByteWidth      = size_of(Vertex) * MAX_QUADS * 4,
            Usage          = .DYNAMIC,
            BindFlags      = {.VERTEX_BUFFER},
            CPUAccessFlags = {.WRITE},
        }

        index_buffer_count :: MAX_QUADS * 6
        indices: [MAX_QUADS * 6]u16

        for i := 0; i < index_buffer_count; i += 6 {
            quad_index := u16(i / 6 * 4)
            indices[i + 0] = quad_index + 0
            indices[i + 1] = quad_index + 1
            indices[i + 2] = quad_index + 2
            indices[i + 3] = quad_index + 0
            indices[i + 4] = quad_index + 2
            indices[i + 5] = quad_index + 3
        }

        index_buffer_desc := D3D11.BUFFER_DESC {
            ByteWidth = size_of(indices),
            Usage     = .IMMUTABLE,
            BindFlags = {.INDEX_BUFFER},
        }

        index_data := D3D11.SUBRESOURCE_DATA {
            pSysMem = &indices[0],
            SysMemPitch = size_of(indices),
        }

        result = device->CreateBuffer(&vertex_buffer_desc, nil, &vertex_buffer)
        CHECK_RES_REQUIRED(result)
        _set_debug_name(vertex_buffer, "main_vertex_buffer")

        result = device->CreateBuffer(&index_buffer_desc, &index_data, &index_buffer)
        CHECK_RES_REQUIRED(result)
        _set_debug_name(index_buffer, "main_index_buffer")
    }

    // Global Constant Buffer
   {
        constant_buffer_desc := D3D11.BUFFER_DESC{
            ByteWidth      = size_of(GlobalConstants),
            Usage          = .DYNAMIC,
            BindFlags      = {.CONSTANT_BUFFER},
            CPUAccessFlags = {.WRITE},
        }

        result = device->CreateBuffer(&constant_buffer_desc, nil, &constant_buffer)
        CHECK_RES_REQUIRED(result)
        _set_debug_name(constant_buffer, "main_constant_buffer")
   }

    // Create main 2D shader
    {
        shader_data :: #load("shader.hlsl", []u8)

        // Compile vertex shader
        vertex, vertex_res := _compile_shader(shader_data, "main", ShaderType.Vertex)
        CHECK_RES_REQUIRED(vertex_res)
        vertex_shader, input_layout = _create_vertex_shader_from_blob(vertex, "main")

        pixel, pixel_res := _compile_shader(shader_data, "main", ShaderType.Pixel)
        CHECK_RES_REQUIRED(pixel_res)
        pixel_shader = _create_pixel_shader_from_blob(pixel, "main")
    }

    // Pixel art render tex
    main_render_texture = _create_render_texture(640, 380)

    _set_debug_name(main_render_texture.texture, "pixel_render.texture")
    _set_debug_name(main_render_texture.texture_view, "pixel_render.texture_view")
    _set_debug_name(main_render_texture.render_texture_view, "pixel_render.render_texture_view")

    _setup_buffers()

    _set_debug_name(atlas_texture.texture, "atlas.texture")
    _set_debug_name(atlas_texture.texture_view, "atlas.texture_view")
    _set_debug_name(atlas_texture.render_texture_view, "atlas.render_texture_view")

    win.ShowWindow(window, 1)
    win.UpdateWindow(window)
}

_graphics_shutdown :: proc() {

}

_setup_buffers :: proc() {
    result := swapchain->GetBuffer(0, D3D11.ITexture2D_UUID, (^rawptr)(&screen_render_texture.texture))
    CHECK_RES_REQUIRED(result)

    result = device->CreateRenderTargetView(screen_render_texture.texture, nil, &screen_render_texture.render_texture_view)
    CHECK_RES_REQUIRED(result)

    _set_debug_name(screen_render_texture.texture, "screen.texture")
    _set_debug_name(screen_render_texture.texture_view, "screen.texture_view")
    _set_debug_name(screen_render_texture.render_texture_view, "screen.render_texture_view")

    screen_render_texture.width  = app_state.gfx.window_width
    screen_render_texture.height = app_state.gfx.window_height
}

_graphics_resize_buffers :: proc() {
    safe_free(screen_render_texture.render_texture_view)
    safe_free(screen_render_texture.texture)
    result := swapchain->ResizeBuffers(0, 0, 0, .UNKNOWN, {})
    CHECK_RES_REQUIRED(result)
    _setup_buffers()
}

_graphics_set_render_target :: proc(render_target: ^DX11Texture, clear_color: Color) {
    viewport: D3D11.VIEWPORT = { 0, 0, f32(render_target.width), f32(render_target.height), 0, 1}
    device_ctx->RSSetViewports(1, &viewport)

    col := clear_color
    device_ctx->ClearRenderTargetView(render_target.render_texture_view, &col)
    device_ctx->OMSetRenderTargets(1, &render_target.render_texture_view, nil)
}

_graphics_start_frame :: proc() {
    if app_state.gfx.window_resized {
        _graphics_resize_buffers()
        app_state.gfx.window_resized = false
    }

    _graphics_set_render_target(&main_render_texture, app_state.gfx.frame.clear_color)

    device_ctx->RSSetState(rasterizer_state)

    blend_factor :[4]f32 = 1
    device_ctx->OMSetBlendState(blend_state, &blend_factor, 0xffffffff)

    mapped_subresource: D3D11.MAPPED_SUBRESOURCE
    device_ctx->Map(vertex_buffer, 0, .WRITE_DISCARD, {}, &mapped_subresource)
    mem.copy(mapped_subresource.pData, &app_state.gfx.frame.quads[0], size_of(Quad) * app_state.gfx.frame.quad_count)
    device_ctx->Unmap(vertex_buffer, 0)

    device_ctx->IASetPrimitiveTopology(.TRIANGLELIST)
    device_ctx->IASetInputLayout(input_layout)

    stride := u32(size_of(Vertex))
    offset := u32(0)
    device_ctx->IASetVertexBuffers(0, 1, &vertex_buffer, &stride, &offset)
    device_ctx->IASetIndexBuffer( index_buffer, .R16_UINT, 0)

    device_ctx->VSSetShader(vertex_shader, nil, 0)

    device_ctx->Map(constant_buffer, 0, .WRITE_DISCARD, {}, &mapped_subresource)
    data := (^GlobalConstants)(mapped_subresource.pData)
    data.scissor_rect = 0
    data.screen_res = {window_width(), window_height()}
    device_ctx->Unmap(constant_buffer, 0)

    device_ctx->VSSetConstantBuffers(0, 1, &constant_buffer)

    device_ctx->PSSetShader(pixel_shader, nil, 0)

    device_ctx->PSSetShaderResources(0, 1, &atlas_texture.texture_view)
    device_ctx->PSSetShaderResources(2, 1, &main_render_texture.texture_view)
    device_ctx->PSSetSamplers(0, 1, &sampler_state)

     if app_state.gfx.frame.quad_count > 0 {
        device_ctx->DrawIndexed(u32(6 * app_state.gfx.frame.quad_count), 0, 0)
    }
}

_graphics_present_frame :: proc() {
    _graphics_set_render_target(&screen_render_texture, {0, 0, 0, 1})

    app_state.gfx.frame.quad_count = 0

    // Set the camera with the correct aspect ratio
    set_camera({0, 0}, 1, {f32(screen_render_texture.width), f32(screen_render_texture.height)}, .Center)

    // Draw the full rect (now matching the camera dimensions)
    draw_rect({0, 0, f32(screen_render_texture.width), f32(screen_render_texture.height)}, .center, 1, img_id = .render_tex)

    // Rest of the rendering pipeline
    device_ctx->IASetPrimitiveTopology(.TRIANGLELIST)
    device_ctx->IASetInputLayout(input_layout)

    mapped_subresource: D3D11.MAPPED_SUBRESOURCE
    device_ctx->Map(vertex_buffer, 0, .WRITE_DISCARD, {}, &mapped_subresource)
    mem.copy(mapped_subresource.pData, &app_state.gfx.frame.quads[0], size_of(Quad))
    device_ctx->Unmap(vertex_buffer, 0)

    stride := u32(size_of(Vertex))
    offset := u32(0)
    device_ctx->IASetVertexBuffers(0, 1, &vertex_buffer, &stride, &offset)
    device_ctx->IASetIndexBuffer(index_buffer, .R16_UINT, 0)

    device_ctx->VSSetShader(vertex_shader, nil, 0)
    device_ctx->VSSetConstantBuffers(0, 1, &constant_buffer)

    device_ctx->PSSetShader(pixel_shader, nil, 0)

    device_ctx->PSSetShaderResources(0, 1, &atlas_texture.texture_view)
    device_ctx->PSSetShaderResources(2, 1, &main_render_texture.texture_view)
    device_ctx->PSSetShaderResources(3, 1, &screen_render_texture.texture_view)
    device_ctx->PSSetSamplers(0, 1, &sampler_state)

    device_ctx->DrawIndexed(6, 0, 0)

    swapchain->Present(1, {})
}


_create_render_texture :: proc(width, height: int) -> (texture: DX11Texture) {
    texture_desc := D3D11.TEXTURE2D_DESC{
        Width      = u32(width),
        Height     = u32(height),
        MipLevels  = 1,
        ArraySize  = 1,
        Format     = .R8G8B8A8_UNORM_SRGB,
        SampleDesc = {Count = 1, Quality = 0},
        Usage      = .DEFAULT,
        BindFlags  = {.RENDER_TARGET, .SHADER_RESOURCE},
    }

    result := device->CreateTexture2D(&texture_desc, nil, &texture.texture)
    CHECK_RES_REQUIRED(result)

    result = device->CreateRenderTargetView(texture.texture, nil, &texture.render_texture_view)
    CHECK_RES_REQUIRED(result)

    result = device->CreateShaderResourceView(texture.texture, nil, &texture.texture_view)
    CHECK_RES_REQUIRED(result)

    texture.width  = width
    texture.height = height
    return
}

_upload_texture :: proc(texture_data: rawptr, width, height: int, mips: u32 = 1) -> (DX11Texture, bool) {
    texture_desc := D3D11.TEXTURE2D_DESC{
        Width      = u32(width),
        Height     = u32(height),
        MipLevels  = mips,
        ArraySize  = 1,
        Format     = .R8G8B8A8_UNORM_SRGB,
        SampleDesc = {Count = 1},
        Usage      = .IMMUTABLE,
        BindFlags  = {.SHADER_RESOURCE},
    }

    texture_data := D3D11.SUBRESOURCE_DATA{
        pSysMem     = texture_data,
        SysMemPitch = u32(width * 4),
    }

    texture: ^D3D11.ITexture2D
    tex_res := device->CreateTexture2D(&texture_desc, &texture_data, &texture)
    CHECK_RES_REQUIRED(tex_res)

    texture_view: ^D3D11.IShaderResourceView
    tex_view_res := device->CreateShaderResourceView(texture, nil, &texture_view)
    CHECK_RES_REQUIRED(tex_view_res)

    log_info(fmt.tprintf("Successfully uploaded texture to GPU. Size: %dx%d", width, height))
    return {texture, texture_view, nil, int(width), int(height)}, true
}

//////////// SHADER STUFF ////////////
_compile_shader :: proc(data: []u8, name: string, shader_type: ShaderType) -> (shader_blob: ^D3D.ID3DBlob, ok: D3D11.HRESULT) {
    entry:  cstring
    target: cstring

    #partial switch shader_type {
        case .Vertex: entry, target = "vs_main",  "vs_5_0"
        case .Pixel:  entry, target = "ps_main",  "ps_5_0"
    }

    log_info("Compiling %v shader: %v", shader_type, name)

    error_blob: ^D3D.ID3DBlob
    ok = D3D.Compile(raw_data(data), len(data), nil, nil, nil, entry, target, 0, 0, &shader_blob, &error_blob)

    if error_blob != nil {
        error_message := strings.string_from_ptr((^byte)(error_blob->GetBufferPointer()), int(error_blob->GetBufferSize()))
        error_blob->Release()
        log_error("Failed to compile shader: %v", error_message)
    } else {
        log_info("Successfully compiled %v shader: %v", shader_type, name)
    }
    return
}

_create_pixel_shader_from_blob :: proc(shader_blob: ^D3D.ID3DBlob, name: string) -> (shader: ^D3D11.IPixelShader) {
    pixel_result := device->CreatePixelShader(shader_blob->GetBufferPointer(), shader_blob->GetBufferSize(), nil, &shader)
    CHECK_RES_REQUIRED(pixel_result)
    _set_debug_name(shader, fmt.tprintf("{}_pixel_shader}", name))
    return shader
}

_create_vertex_shader_from_blob :: proc(shader_blob: ^D3D.ID3DBlob, name: string) -> (shader: ^D3D11.IVertexShader, layout: ^D3D11.IInputLayout) {
    result: D3D11.HRESULT
    result = device->CreateVertexShader(shader_blob->GetBufferPointer(), shader_blob->GetBufferSize(), nil, &shader)
    CHECK_RES_REQUIRED(result)

    layout, result = _generate_input_layout(shader_blob)
    CHECK_RES_REQUIRED(result)

    _set_debug_name(shader, fmt.tprintf("{}_vertex_shader}", name))
    _set_debug_name(layout, fmt.tprintf("{}_input_layout}", name))

    return shader, layout
}

// Generates a input layout directly from the shader data rather than manually authoring one on the odin side for every shader
_generate_input_layout :: proc (vertex_shader_blob: ^D3D11.IBlob) -> (^D3D11.IInputLayout, D3D11.HRESULT) {
    IShaderReflectionType_UUID_STRING :: "8d536ca1-0cca-4956-a837-786963755584"
    IShaderReflectionType_UUID := &D3D.IID{0x8d536ca1, 0x0cca, 0x4956, {0xa8, 0x37, 0x78, 0x69, 0x63, 0x75, 0x55, 0x84}}

    vertex_shader_reflection: ^D3D11.IShaderReflection
    reflect_result := D3D.Reflect(vertex_shader_blob->GetBufferPointer(), vertex_shader_blob->GetBufferSize(), IShaderReflectionType_UUID, (^rawptr)(&vertex_shader_reflection))
    CHECK_RES_REQUIRED(reflect_result)

    defer vertex_shader_reflection->Release()

    // get the description of the input layout
    input_layout_desc: D3D11.SHADER_DESC
    desc_result := vertex_shader_reflection->GetDesc(&input_layout_desc)
    CHECK_RES_REQUIRED(desc_result)

    desc := make([]D3D11.INPUT_ELEMENT_DESC, (int)(input_layout_desc.InputParameters))
    defer delete(desc)

    // get the description of each input element
    for i in 0..<len(desc) {
        signature_parameter_desc: D3D11.SIGNATURE_PARAMETER_DESC
        param_desc_result := vertex_shader_reflection->GetInputParameterDesc(u32(i), &signature_parameter_desc)
        CHECK_RES_REQUIRED(param_desc_result)

        input_element_desc: D3D11.INPUT_ELEMENT_DESC

        input_element_desc.SemanticName         = signature_parameter_desc.SemanticName
        input_element_desc.SemanticIndex        = signature_parameter_desc.SemanticIndex
        input_element_desc.InputSlot            = 0
        input_element_desc.AlignedByteOffset    = D3D11.APPEND_ALIGNED_ELEMENT
        input_element_desc.InputSlotClass       = .VERTEX_DATA
        input_element_desc.InstanceDataStepRate = 0

        if signature_parameter_desc.Mask == 1 {
            #partial switch signature_parameter_desc.ComponentType {
                case .FLOAT32: input_element_desc.Format = .R32_FLOAT
                case .SINT32:  input_element_desc.Format = .R32_SINT
                case .UINT32:  input_element_desc.Format = .R32_UINT
            }
        } else if signature_parameter_desc.Mask <= 3 {
            #partial switch signature_parameter_desc.ComponentType {
                case .FLOAT32: input_element_desc.Format = .R32G32_FLOAT
                case .SINT32:  input_element_desc.Format = .R32G32_SINT
                case .UINT32:  input_element_desc.Format = .R32G32_UINT
            }
        } else if signature_parameter_desc.Mask <= 7 {
            #partial switch signature_parameter_desc.ComponentType {
                case .FLOAT32: input_element_desc.Format = .R32G32B32_FLOAT
                case .SINT32:  input_element_desc.Format = .R32G32B32_SINT
                case .UINT32:  input_element_desc.Format = .R32G32B32_UINT
            }
        } else if signature_parameter_desc.Mask <= 15 {
            #partial switch signature_parameter_desc.ComponentType {
                case .FLOAT32: input_element_desc.Format = .R32G32B32A32_FLOAT
                case .SINT32:  input_element_desc.Format = .R32G32B32A32_SINT
                case .UINT32:  input_element_desc.Format = .R32G32B32A32_UINT
            }
        }

        desc[i] = input_element_desc
    }

    input_layout_result := device->CreateInputLayout(&desc[0], u32(len(desc)), vertex_shader_blob->GetBufferPointer(), vertex_shader_blob->GetBufferSize(), &input_layout)
    CHECK_RES_REQUIRED(input_layout_result)

    return input_layout, input_layout_result
}
//////////// END SHADER STUFF ////////////


//////////// D3D UTILS ////////////
@(private="file")
safe_free :: proc(obj: ^D3D11.IUnknown) {
    if obj != nil {
        obj->Release()
    }
}

@(disabled=!ODIN_DEBUG)
_set_debug_name :: proc(resource: ^D3D11.IDeviceChild, name: string) {
    if resource != nil && len(name) > 0 {
        win_str := win.utf8_to_wstring(name)
        resource->SetPrivateData(D3D11.WKPDID_D3DDebugObjectNameW_UUID, u32(size_of(u16) * len(name)), &win_str[0])
    }
}
//////////// END D3D UTILS ////////////

//////////// WINDOWING ////////////
window: win.HWND

_window_open :: proc(title: string) {
    instance := win.HINSTANCE(win.GetModuleHandleW(nil))
    assert(instance != nil, "Failed to fetch current instance handle")

    class_name := win.utf8_to_wstring(title)

    class := win.WNDCLASSW {
        lpfnWndProc   = win_proc,
        lpszClassName = class_name,
        hInstance     = instance,
        hCursor       = win.LoadCursorA(nil, win.IDC_ARROW), // Set this otherwise spinny cursor shows
    }

    class_handle := win.RegisterClassW(&class)
    assert(class_handle != 0, "Class creation failed")

    win.SetProcessDPIAware()
    win.timeBeginPeriod(1)

    screen_width  := win.GetSystemMetrics(win.SM_CXSCREEN)
    screen_height := win.GetSystemMetrics(win.SM_CYSCREEN)

    window_width, window_height: i32

    // Helper to default the window size to common res value in window mode
    switch {
        case  screen_height >= 2160: window_width, window_height = 2560, 1440
        case  screen_height >= 1440: window_width, window_height = 1920, 1080
        case  screen_height >= 1080: window_width, window_height = 1280, 720
        case: window_width, window_height = 640, 360
    }

    window_x := (screen_width - c.int(window_width)) / 2
    window_y := (screen_height - c.int(window_height)) / 2

    window = win.CreateWindowW(class_name, class_name,
        win.WS_OVERLAPPEDWINDOW,
        window_x, window_y, c.int(window_width), c.int(window_height),
        nil, nil, instance, nil)

    assert(window != nil, "Window creation Failed")
    register_raw_input_devices(window)

    app_state.gfx.screen_width  = int(screen_width)
    app_state.gfx.screen_height = int(screen_height)
    app_state.gfx.window_width  = int(window_width)
    app_state.gfx.window_height = int(window_height)
}

_window_poll :: proc() {
    msg: win.MSG

    for win.PeekMessageW(&msg, nil, 0, 0, 1) {
        win.TranslateMessage(&msg)
        win.DispatchMessageW(&msg)
    }
}

_window_closed :: proc(hwnd: win.HWND) {
    app_state.running = false
    win.DestroyWindow(hwnd)
}

_window_on_resized :: proc(wparam: win.WPARAM, lparam: win.LPARAM) {
    app_state.gfx.window_width  = int(win.LOWORD(win.DWORD(lparam)))
    app_state.gfx.window_height = int(win.HIWORD(win.DWORD(lparam)))
    app_state.gfx.window_resized = true
}

@(private="file")
win_proc :: proc "stdcall" (hwnd: win.HWND, msg: win.UINT, wparam: win.WPARAM, lparam: win.LPARAM) -> win.LRESULT {
    context = app_state.odin_ctx

    switch(msg) {
        case win.WM_DESTROY:   win.PostQuitMessage(0)
        case win.WM_INPUT:     process_raw_input(lparam)
        case win.WM_SETFOCUS:  app_state.gfx.window_focused = true
        case win.WM_KILLFOCUS: app_state.gfx.window_focused = false
        case win.WM_CLOSE:     _window_closed(hwnd)
        case win.WM_SIZE:      _window_on_resized(wparam, lparam)
        case: return win.DefWindowProcW(hwnd, msg, wparam, lparam)
    }
    return 0
}

_window_show_message_box :: proc(
    title, msg: string,
    msg_type: MessageBoxType,
) {
    message_type: win.UINT = 0x00000000

    switch msg_type {
        case .Info:    message_type |= 0x00000040
        case .Warning: message_type |= 0x00000030
        case .Error:   message_type |= 0x00000010
    }

    win.MessageBoxW(
        window,
        win.utf8_to_wstring(msg),
        win.utf8_to_wstring(title),
        message_type,
    )
}

_window_set_title :: proc(title: string) {
    win.SetWindowTextW(window, win.utf8_to_wstring(title))
}

_window_set_size :: proc(width, height: u32) {
    win.SetWindowPos(window, nil, 0, 0, c.int(width), c.int(height), 0x0001 | 0x0002)
}

_window_get_size :: proc() -> (width, height: int) {
    return app_state.gfx.window_width, app_state.gfx.window_height
}

_window_set_position :: proc(x, y: u32) {
    win.SetWindowPos(window, nil, c.int(x), c.int(y), 0, 0, 0x0001 | 0x0002)
}

_window_set_fullscreen :: proc(fullscreen: bool) {
    if fullscreen != app_state.gfx.fullscreen {
        swapchain->SetFullscreenState(win.BOOL(fullscreen), nil);
        app_state.gfx.fullscreen = fullscreen
        _graphics_resize_buffers()
    }
}

_cursor_show :: proc(show: bool) {
    win.ShowCursor(show ? win.TRUE : win.FALSE)
}

//////////// END WINDOWING ////////////


//////////// INPUT ////////////
@(private = "file")
register_raw_input_devices :: proc(hwnd: win.HWND) {
    rid: [2]win.RAWINPUTDEVICE
    rid[0].usUsagePage = 0x01             // HID_USAGE_PAGE_GENERIC
    rid[0].usUsage = 0x02                 // HID_USAGE_GENERIC_MOUSE
    rid[0].dwFlags = win.RIDEV_INPUTSINK  // adds mouse and also ignores legacy mouse messages
    rid[0].hwndTarget = hwnd

    rid[1].usUsagePage = 0x01              // HID_USAGE_PAGE_GENERIC
    rid[1].usUsage = 0x06                  // HID_USAGE_GENERIC_KEYBOARD
    rid[1].dwFlags = win.RIDEV_INPUTSINK   // adds keyboard and also ignores legacy keyboard messages
    rid[1].hwndTarget = hwnd

    if !win.RegisterRawInputDevices(&rid[0], 2, size_of(rid[0]))
    {
        panic("Failed to register raw input devices")
    }
}

@(private = "file")
lpb_buffer: [1024]u8

@(private = "file")
process_raw_input :: proc(lParam: win.LPARAM) {
    PROFILE(#procedure)
    if !app_state.gfx.window_focused {
        return
    }

    point: win.POINT
    if win.GetCursorPos(&point) {
        // Convert screen coordinates to client coordinates
        window_handle := win.GetActiveWindow() // or store your window handle somewhere
        if win.ScreenToClient(window_handle, &point) {
            app_state.input.mouse_position = {int(point.x), int(point.y)}
        } else {
            app_state.input.mouse_position = {-1, -1}
        }
    } else {
        app_state.input.mouse_position = {-1, -1}
    }
    dwSize: u32
    win.GetRawInputData(win.HRAWINPUT(lParam), win.RID_INPUT, nil, &dwSize, size_of(win.RAWINPUTHEADER))
    data := lpb_buffer[:dwSize]

    if win.GetRawInputData(win.HRAWINPUT(lParam), win.RID_INPUT, raw_data(data), &dwSize, size_of(win.RAWINPUTHEADER)) != dwSize {
        return
    }

    raw := cast(^win.RAWINPUT)raw_data(data)
    if (raw.header.dwType == win.RIM_TYPEMOUSE) {
        mouse := raw.data.mouse
        deltaX := mouse.lLastX
        deltaY := mouse.lLastY
        app_state.input.mouse_move_delta = {f32(deltaX), f32(deltaY)}

        // Process mouse buttons
        if mouse.usButtonFlags & win.RI_MOUSE_LEFT_BUTTON_DOWN != 0 {
            update_mouse_state(.Left, true)
        }
        if mouse.usButtonFlags & win.RI_MOUSE_LEFT_BUTTON_UP != 0 {
            update_mouse_state(.Left, false)
        }
        if mouse.usButtonFlags & win.RI_MOUSE_RIGHT_BUTTON_DOWN != 0 {
            update_mouse_state(.Right, true)
        }
        if mouse.usButtonFlags & win.RI_MOUSE_RIGHT_BUTTON_UP != 0 {
            update_mouse_state(.Right, false)
        }
        if mouse.usButtonFlags & win.RI_MOUSE_MIDDLE_BUTTON_DOWN != 0 {
            update_mouse_state(.Middle, true)
        }
        if mouse.usButtonFlags & win.RI_MOUSE_MIDDLE_BUTTON_UP != 0 {
            update_mouse_state(.Middle, false)
        }

        if mouse.usButtonFlags & win.RI_MOUSE_WHEEL != 0 {
            wheel_delta := cast(i16)mouse.usButtonData
            app_state.input.mouse_scroll_y = f32(wheel_delta) / f32(win.WHEEL_DELTA)
        }
    } else if raw.header.dwType == win.RIM_TYPEKEYBOARD {
        key := _remap_key(WinKeyCode(raw.data.keyboard.VKey))
        if (raw.data.keyboard.Flags & win.RI_KEY_BREAK == 0) {
            current_state := app_state.input.key_states[key]
            new_pressed_state :Key_State= current_state.pressed == .None ? .Pressed : .Blocked
            app_state.input.key_states[key] = {current = .Pressed, pressed = new_pressed_state}
        } else {
            app_state.input.key_states[key] = {current = .Released, pressed = .None}
        }
    }
}

update_mouse_state :: proc(button: Mouse_Button, is_down: bool) {
    if is_down {
        current_state := app_state.input.mouse_states[button]
        new_pressed_state := current_state.pressed == .None ? Key_State.Pressed : Key_State.Blocked
        app_state.input.mouse_states[button] = {current = .Pressed, pressed = new_pressed_state}
    } else {
        app_state.input.mouse_states[button] = {current = .Released, pressed = .None}
    }
}

_remap_key :: proc(key: WinKeyCode) -> Key_Code {
    #partial switch key {
        // Numeric keys
        case .Num_0: return .Alpha_0
        case .Num_1: return .Alpha_1
        case .Num_2: return .Alpha_2
        case .Num_3: return .Alpha_3
        case .Num_4: return .Alpha_4
        case .Num_5: return .Alpha_5
        case .Num_6: return .Alpha_6
        case .Num_7: return .Alpha_7
        case .Num_8: return .Alpha_8
        case .Num_9: return .Alpha_9

        // Function keys
        case .F1:  return .F1
        case .F2:  return .F2
        case .F3:  return .F3
        case .F4:  return .F4
        case .F5:  return .F5
        case .F6:  return .F6
        case .F7:  return .F7
        case .F8:  return .F8
        case .F9:  return .F9
        case .F10: return .F10
        case .F11: return .F11
        case .F12: return .F12

        // Alphabetic keys
        case .A: return .A
        case .B: return .B
        case .C: return .C
        case .D: return .D
        case .E: return .E
        case .F: return .F
        case .G: return .G
        case .H: return .H
        case .I: return .I
        case .J: return .J
        case .K: return .K
        case .L: return .L
        case .M: return .M
        case .N: return .N
        case .O: return .O
        case .P: return .P
        case .Q: return .Q
        case .R: return .R
        case .S: return .S
        case .T: return .T
        case .U: return .U
        case .V: return .V
        case .W: return .W
        case .X: return .X
        case .Y: return .Y
        case .Z: return .Z

        // Arrow keys
        case .UpArrow:    return .Up
        case .DownArrow:  return .Down
        case .LeftArrow:  return .Left
        case .RightArrow: return .Right

        // Navigation keys
        case .Insert:   return .Insert
        case .Delete:   return .Delete
        case .Home:     return .Home
        case .End:      return .End
        case .PageUp:   return .Page_Up
        case .PageDown: return .Page_Down

        // Symbol keys
        case .OEM3:     return .Back_Quote
        case .OEMComma: return .Comma
        case .OEMPeriod: return .Period
        case .OEM2:     return .Forward_Slash
        case .OEM5:     return .Back_Slash
        case .OEM1:     return .Semicolon
        case .OEM7:     return .Apostrophe
        case .OEM4:     return .Left_Bracket
        case .OEM6:     return .Right_Bracket
        case .OEMMinus: return .Minus
        case .OEMPlus:  return .Equals

        // Modifier keys
        case .LeftCtrl:  return .Control_Left
        case .RightCtrl: return .Control_Right
        case .LeftAlt:   return .Alt_Left
        case .RightAlt:  return .Alt_Right
        case .LeftWin:   return .Super_Left
        case .RightWin:  return .Super_Right

        // Special keys
        case .Tab:       return .Tab
        case .CapsLock:  return .Capslock
        case .LeftShift: return .Shift_Left
        case .RightShift: return .Shift_Right
        case .Enter:     return .Enter
        case .Space:     return .Space
        case .Backspace: return .Backspace
        case .Esc:       return .Escape

        // Numpad keys
        case .NumPad0:    return .Num_0
        case .NumPad1:    return .Num_1
        case .NumPad2:    return .Num_2
        case .NumPad3:    return .Num_3
        case .NumPad4:    return .Num_4
        case .NumPad5:    return .Num_5
        case .NumPad6:    return .Num_6
        case .NumPad7:    return .Num_7
        case .NumPad8:    return .Num_8
        case .NumPad9:    return .Num_9
        case .Add:        return .Num_Add
        case .Subtract:   return .Num_Subtract
        case .Multiply:   return .Num_Multiply
        case .Divide:     return .Num_Divide
        case .Decimal:    return .Num_Decimal

        case: return .INVALID  // Default case for unmapped keys
    }
}


WinKeyCode :: enum u32 {
    None = 0x00,
    Backspace = 0x08,
    Tab = 0x09,
    Enter = 0x0D,
    Shift = 0x10,
    Control = 0x11,
    Alt = 0x12,
    PauseBreak = 0x13,
    CapsLock = 0x14,
    Esc = 0x1B,
    Space = 0x20,
    PageUp = 0x21,
    PageDown = 0x22,
    End = 0x23,
    Home = 0x24,
    LeftArrow = 0x25,
    UpArrow = 0x26,
    RightArrow = 0x27,
    DownArrow = 0x28,
    PrintScreen = 0x2C,
    Insert = 0x2D,
    Delete = 0x2E,
    Num_0 = 0x30,
    Num_1 = 0x31,
    Num_2 = 0x32,
    Num_3 = 0x33,
    Num_4 = 0x34,
    Num_5 = 0x35,
    Num_6 = 0x36,
    Num_7 = 0x37,
    Num_8 = 0x38,
    Num_9 = 0x39,
    A = 0x41,
    B = 0x42,
    C = 0x43,
    D = 0x44,
    E = 0x45,
    F = 0x46,
    G = 0x47,
    H = 0x48,
    I = 0x49,
    J = 0x4A,
    K = 0x4B,
    L = 0x4C,
    M = 0x4D,
    N = 0x4E,
    O = 0x4F,
    P = 0x50,
    Q = 0x51,
    R = 0x52,
    S = 0x53,
    T = 0x54,
    U = 0x55,
    V = 0x56,
    W = 0x57,
    X = 0x58,
    Y = 0x59,
    Z = 0x5A,
    LeftWin = 0x5B,
    RightWin = 0x5C,
    Apps = 0x5D,
    Sleep = 0x5F,
    NumPad0 = 0x60,
    NumPad1 = 0x61,
    NumPad2 = 0x62,
    NumPad3 = 0x63,
    NumPad4 = 0x64,
    NumPad5 = 0x65,
    NumPad6 = 0x66,
    NumPad7 = 0x67,
    NumPad8 = 0x68,
    NumPad9 = 0x69,
    Multiply = 0x6A,
    Add = 0x6B,
    Separator = 0x6C,
    Subtract = 0x6D,
    Decimal = 0x6E,
    Divide = 0x6F,
    F1 = 0x70,
    F2 = 0x71,
    F3 = 0x72,
    F4 = 0x73,
    F5 = 0x74,
    F6 = 0x75,
    F7 = 0x76,
    F8 = 0x77,
    F9 = 0x78,
    F10 = 0x79,
    F11 = 0x7A,
    F12 = 0x7B,
    F13 = 0x7C,
    F14 = 0x7D,
    F15 = 0x7E,
    F16 = 0x7F,
    F17 = 0x80,
    F18 = 0x81,
    F19 = 0x82,
    F20 = 0x83,
    F21 = 0x84,
    F22 = 0x85,
    F23 = 0x86,
    F24 = 0x87,
    NumLock = 0x90,
    ScrollLock = 0x91,
    LeftShift = 0xA0,
    RightShift = 0xA1,
    LeftCtrl = 0xA2,
    RightCtrl = 0xA3,
    LeftAlt = 0xA4,
    RightAlt = 0xA5,
    BrowserBack = 0xA6,
    BrowserForward = 0xA7,
    BrowserRefresh = 0xA8,
    BrowserStop = 0xA9,
    BrowserSearch = 0xAA,
    BrowserFavorites = 0xAB,
    BrowserHome = 0xAC,
    VolumeMute = 0xAD,
    VolumeDown = 0xAE,
    VolumeUp = 0xAF,
    MediaNextTrack = 0xB0,
    MediaPrevTrack = 0xB1,
    MediaStop = 0xB2,
    MediaPlayPause = 0xB3,
    LaunchMail = 0xB4,
    LaunchMediaSelect = 0xB5,
    LaunchApp1 = 0xB6,
    LaunchApp2 = 0xB7,
    OEM1 = 0xBA,
    OEMPlus = 0xBB,
    OEMComma = 0xBC,
    OEMMinus = 0xBD,
    OEMPeriod = 0xBE,
    OEM2 = 0xBF,
    OEM3 = 0xC0,
    OEM4 = 0xDB,
    OEM5 = 0xDC,
    OEM6 = 0xDD,
    OEM7 = 0xDE,
    OEM8 = 0xDF,
    OEM102 = 0xE2,
    ProcessKey = 0xE5,
    Packet = 0xE7,
    Attn = 0xF6,
    CrSel = 0xF7,
    ExSel = 0xF8,
    EraseEOF = 0xF9,
    Play = 0xFA,
    Zoom = 0xFB,
    PA1 = 0xFD,
    OEMClear = 0xFE,
}
//////////// END INPUT ////////////

@(private="file")
print_result :: proc(hr: D3D11.HRESULT) -> (msg: string) {
    message_buffer: [^]u16
    size := win.FormatMessageW(
        win.FORMAT_MESSAGE_ALLOCATE_BUFFER | win.FORMAT_MESSAGE_FROM_SYSTEM | win.FORMAT_MESSAGE_IGNORE_INSERTS,
        nil,
        u32(hr),
        0,
        cast(^u16)(&message_buffer),
        0,
        nil,
    )
    if size > 0 {
        error_message, err := win.utf16_to_utf8(message_buffer[:size])
        ensure(err == nil)
        msg = fmt.tprintf("Error 0x%08X: %s\n", hr, error_message)
        win.LocalFree(message_buffer)
    } else {
        msg = fmt.tprintf("Unknown error 0x%08X\n", hr)
    }
    return
}

CHECK_RES_REQUIRED :: proc(hr: D3D11.HRESULT) -> bool {
    ensure(hr >= 0, print_result(hr))
    return hr < 0
}

CHECK_RES :: proc(hr: D3D11.HRESULT) -> bool {
    return hr < 0
}

import win "core:sys/windows"

import D3D11 "vendor:directx/D3D11"
import DXGI "vendor:directx/dxgi"
import D3D "vendor:directx/d3d_compiler"

import "core:c"
import "core:strings"
import "core:fmt"
import "core:mem"

_ :: mem