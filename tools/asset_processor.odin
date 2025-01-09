package main

import stbi  "vendor:stb/image"
import stbrp "vendor:stb/rect_pack"

import "core:path/filepath"
import "core:fmt"
import "core:strings"
import "core:os"
import "core:mem"

main :: proc() {
    if !os.exists("bin") {
        os.make_directory("bin")
    }

    if !os.exists("bin/res") {
        os.make_directory("bin/res")
    }

    if !os.exists("bin/res/img") {
        os.make_directory("bin/res/img")
    }

    output_file :: "src/generated.odin"
    images := process_images()
    pack_images_into_atlas(images)
    generate_image_info(images, output_file)
}

Image :: struct {
    width:  i32,
    height: i32,
    name:   string,
    data:   [^]byte,
    uv:     [4]f32,
}

generate_image_info :: proc(images: [dynamic]Image, output_file: string) {
    sb := strings.builder_make()
    defer strings.builder_destroy(&sb)

    strings.write_string(&sb, "// THIS FILE IS GENERATED, DO NOT MODIFY.\n\n")

    strings.write_string(&sb, "package main\n\n")


    // Write Image_Info struct definition
    strings.write_string(&sb, "Image_Info :: struct {\n")
    strings.write_string(&sb, "    width:  i32,\n")
    strings.write_string(&sb, "    height: i32,\n")
    strings.write_string(&sb, "    uv:     Vec4,\n")
    strings.write_string(&sb, "}\n\n")

    // Generate image enum
    strings.write_string(&sb, "Image_Name :: enum {\n")
    strings.write_string(&sb, "    nil,\n")
    strings.write_string(&sb, "    font,\n")
    for img in images {
        strings.write_string(&sb, fmt.tprintf("    %s,\n", img.name))
    }
    strings.write_string(&sb, "}\n\n")

    // Generate image info array
    strings.write_string(&sb, "IMAGE_INFO := [Image_Name]Image_Info{\n")
    strings.write_string(&sb, "    .nil = {},\n")
    strings.write_string(&sb, "    .font = {},\n")
    for img in images {
        strings.write_string(&sb, fmt.tprintf("    .%s = {{width = %d, height = %d, uv = {{%f, %f, %f, %f}}}},\n",
            img.name, img.width, img.height, img.uv.x, img.uv.y, img.uv.z, img.uv.w))
    }
    strings.write_string(&sb, "}\n")

    os.write_entire_file(output_file, sb.buf[:])
}

process_images :: proc() -> [dynamic]Image {
    out_dir  := "bin/res/"
    in_dir  := "res/img"

    images := make([dynamic]Image)

     Walk_Data :: struct {
        images: [dynamic]Image
     }

     walk_data := Walk_Data {images}

    stbi.set_flip_vertically_on_load(1)

    filepath.walk(
        in_dir,
       proc(info: os.File_Info, in_err: os.Error, user_data: rawptr) -> (err: os.Error, skip_dir: bool) {
            if in_err != 0 {
                fmt.eprintln("Error accessing file:", in_err)
                return in_err, false
            }

            png_data, succ := os.read_entire_file(info.fullpath)

            if in_err != 0 {
                fmt.eprintln("Error accessing file:", in_err)
                return in_err, false
            }

            w_data := (cast(^Walk_Data)user_data)

            if !info.is_dir && filepath.ext(info.name) == ".png" {
                enum_name := strings.to_snake_case(strings.trim_suffix(info.name, filepath.ext(info.name)))

                width, height, channels: i32
		        img_data := stbi.load_from_memory(raw_data(png_data), auto_cast len(png_data), &width, &height, &channels, 4)

		        img := Image{width, height, enum_name, img_data, 0}

                n, err := append(&w_data.images, img)

                if err != nil {
                    fmt.println(err)
                }
            }

            return 0, false
        },
        rawptr(&walk_data),
    )

    return walk_data.images
}

Coord :: stbrp.Coord
   pack_images_into_atlas :: proc(images: [dynamic]Image) {
    pack_images :: proc(images: [dynamic]Image, width, height: int) -> (bool, [dynamic]stbrp.Rect) {
        ctx: stbrp.Context
        nodes := make([dynamic]stbrp.Node, width)
        defer delete(nodes)

        stbrp.init_target(&ctx, auto_cast width, auto_cast height, raw_data(nodes), auto_cast len(nodes))

        rects: [dynamic]stbrp.Rect
        for img, i in images {
            if img.width == 0 {
                continue
            }
            append(&rects, stbrp.Rect{
                id = auto_cast i,
                w  = Coord(img.width + 2),
                h  = Coord(img.height + 2),
            })
        }

        success := stbrp.pack_rects(&ctx, raw_data(rects), auto_cast len(rects))
        return success == 1, rects
    }

    // Find the best minimum size
    initial_size := 64
    atlas_width, atlas_height: int
    rects: [dynamic]stbrp.Rect
    for size := initial_size; size <= 8192; size *= 2 {
        success, temp_rects := pack_images(images, size, size)
        if success {
            atlas_width = size
            atlas_height = size
            rects = temp_rects
            break
        }
        delete(temp_rects)
    }

    if atlas_width == 0 || atlas_height == 0 {
        fmt.eprintln("Failed to pack all the rects, maximum size exceeded!")
        return
    }

    fmt.printf("Atlas size: %dx%d\n", atlas_width, atlas_height)

    atlas_data := make([]byte, atlas_width * atlas_height * 4)
    defer delete(atlas_data)

    mem.set(raw_data(atlas_data), 0, atlas_width * atlas_height * 4)

    for rect in rects {
        img := &images[rect.id]

        rect_w := int(rect.w) - 2
        rect_h := int(rect.h) - 2

        for row in 0..<rect_h {
            src_row := mem.ptr_offset(img.data, row * int(img.width) * 4)
            dest_row := &atlas_data[((int(rect.y) + 1 + row) * atlas_width + int(rect.x) + 1) * 4]
            mem.copy(dest_row, src_row, rect_w * 4)
        }

        img.uv[0] = f32(rect.x + 1) / f32(atlas_width)
        img.uv[1] = f32(rect.y + 1) / f32(atlas_height)
        img.uv[2] = f32(int(rect.x) + 1 + rect_w) / f32(atlas_width)
        img.uv[3] = f32(int(rect.y) + 1 + rect_h) / f32(atlas_height)

        fmt.printf("Image %d (%s): Packed at (%d, %d), size: %dx%d, UVs: (%.4f, %.4f) - (%.4f, %.4f)\n",
            rect.id, img.name, rect.x, rect.y, rect.w, rect.h,
            img.uv[0], img.uv[1], img.uv[2], img.uv[3])

        stbi.image_free(img.data)
        img.data = nil
    }

    stbi.write_png("bin/res/img/atlas.png", auto_cast atlas_width, auto_cast atlas_height, 4, raw_data(atlas_data), 4 * auto_cast atlas_width)

    // // Save individual images for debugging
    // for rect in rects {
    //     img := &images[rect.id]
    //     rect_w := int(rect.w) - 2
    //     rect_h := int(rect.h) - 2
    //     img_data := make([]byte, rect_w * rect_h * 4)
    //     defer delete(img_data)

    //     for row in 0..<rect_h {
    //         src_row := &atlas_data[((int(rect.y) + 1 + row) * atlas_width + int(rect.x) + 1) * 4]
    //         dest_row := &img_data[row * rect_w * 4]
    //         mem.copy(dest_row, src_row, rect_w * 4)
    //     }

    //     stbi.write_png(fmt.ctprintf("bin/res/img/debug_image_%s.png", img.name), auto_cast rect_w, auto_cast rect_h, 4, raw_data(img_data), 4 * auto_cast rect_w)
    // }

    delete(rects)
}