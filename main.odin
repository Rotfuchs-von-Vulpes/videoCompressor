package videoCompressor

import "core:slice"
import "core:strconv"
import "core:time"
import "core:strings"
import "base:runtime"
import "core:os/os2"
import "core:os"
import "core:fmt"

megabyte :: 1024 * 1024

extract_video_name :: proc (file : string) -> string {
    arr := strings.split(file, ".")
    if len(arr) > 1 {
        arr2 := arr[:len(arr)-1]
        return strings.join(arr2, ".")
    }
    return file
}

get_out_name :: proc (video_name : string, out_count : int) -> string {
    b := strings.Builder{}
    strings.write_string(&b, video_name)
    strings.write_rune(&b, '_')
    strings.write_int(&b, out_count)
    strings.write_string(&b, ".mp4")
    return strings.to_string(b)
}

run_compress :: proc "c" (quality : i32, file_name, out_name, preset : string) -> bool {
    context = runtime.default_context()
    p := os2.Process_Desc{}
    p.command = {"ffmpeg",  "-i", file_name, "-c:v", "libx264", "-crf", fmt.tprintf("%d", 51-quality), "-preset", preset, "-c:a", "copy", out_name}
    p.working_dir = os.get_current_directory()
    if state, stdout, stderr, err := os2.process_exec(p, context.allocator); err == nil {
        return true
    } else {
        fmt.println("Erro ao executar ffmpeg")
        fmt.println(string(stderr))
        return false
    }
}

read_size :: proc (out : string) -> (bool, int) {
    if h, err := os.open(out); err == nil {
        defer os.close(h)
        if size, err := os.file_size(h); err == nil {
            return true, int(size)
        }
        fmt.println("Erro ao ler tamanho do arquivo")
        return false, 0
    }
    fmt.println("Erro ao abrir arquivo")
    return false, 0
}

delete_video :: proc (file_name : string) {
    os.remove(file_name)
}

binary_search :: proc (file_name : string, target_size : int, preset : string) -> bool {
    ma: i32 = 51
    mi: i32 = 0
    medium : i32
    history : [dynamic]i32 = {}

    out_count := 1
    best_idx := 0

    video_name := extract_video_name(file_name)
    loop: for {
        medium = (ma - mi) / 2 + mi
        out_name := get_out_name(video_name, out_count)
        for q in history {
            if q == medium {
                break loop
            }
        }
        append(&history, medium)

        if !run_compress(medium, file_name, out_name, preset) {
            return false
        }
        if ok, size := read_size(out_name); ok {
            fmt.printfln("tentativa numero %d, tamanho: %fMiB", out_count, f32(size) / megabyte)
            if size > target_size {
                delete_video(out_name)
                ma = medium
            } else if size <= target_size {
                if best_idx > 0 do delete_video(get_out_name(video_name, best_idx))
                best_idx = out_count
                mi = medium
            }
            out_count += 1
        } else {
            return false
        }
    }
    if best_idx == 0 {
        fmt.printfln("Nao consegui...")
        return false
    }
    return true
}

parse_args :: proc (args : []string) -> (bool, string, int, string) {
    presets := []string{"ultrafast", "superfast", "veryfast", "fast", "medium", "slow", "slower", "veryslow"}
    allPresets, _ := strings.join(presets, ", ")
    first := true
    preset := "veryslow"
    targetSize := 10 * megabyte
    file : string
    command :: enum {
        none,
        preset,
        size
    }
    next : command = .none
    for arg in args {
        if first {
            file = arg
            first = false
        } else if next == .none {
            if arg == "-p" {
                next = .preset
            } else if arg == "-s" {
                next = .size
            }
        } else {
            switch next {
                case .none:
                case .preset:
                    preset = arg
                    failed := !slice.contains(presets, preset)
                    if failed {
                        fmt.printfln("%s nao é um preset valido, eh necessario que seja um desses: %s.", preset, allPresets)
                        return false, "", 0, ""
                    }
                case .size:
                    if v, ok := strconv.parse_int(arg, 10); ok {
                        targetSize = megabyte * v 
                    } else {
                        fmt.println("Tamanho do arquivo deve ser um numero inteiro puro (denotando mebibytes).")
                        return false, "", 0, ""
                    }
            }
            next = .none
        }
    }
    if file == "" {
        fmt.println("Arquivo de video nao foi especificado.")
        return false, "", 0, ""
    }
    fmt.printfln("Video para comprimir: %s", file)
    fmt.printfln("Tamanho maximo: %fMiB", f32(targetSize) / megabyte)
    fmt.printfln("Preset de velocidade: %s", preset)
    return true, file, targetSize, preset
}

main :: proc () {
    args := os.args[1:]
    t := time.now()
    if len(args) == 0 {
        fmt.println("Insira o nome do arquivo de video, exemplo: \"video.mp4\" -p veryslow -s 10")
    } else if ok, file, target_size, preset := parse_args(args); ok {
        if ok := binary_search(file, target_size, preset); ok {
            fmt.println("Pronto!")
        }
        m := time.duration_seconds(time.since(t))
        fmt.printfln("tempo total: %fs", m)
    }
}