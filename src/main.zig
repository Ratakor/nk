const std = @import("std");
const builtin = @import("builtin");
const known_folders = @import("known-folders");
const Nekoweb = @import("Nekoweb.zig");

pub const std_options: std.Options = .{
    .log_level = if (builtin.mode == .Debug) .debug else .info,
    .logFn = coloredLog,
};

const version = "0.0.0";
const config_dirname = "nekoweb";
const config_filename = "config";
const config_path = switch (builtin.os.tag) {
    .windows => config_dirname ++ "\\" ++ config_filename,
    else => config_dirname ++ "/" ++ config_filename,
};

const usage =
    \\Usage: {s} [command] [options]
    \\
    \\Commands:
    // \\  push       | Upload a directory to your Nekoweb website
    // \\  pull       | Download all files from your Nekoweb website
    \\  info       | Display information about a Nekoweb website
    \\  create     | Create a new file or directory
    \\  upload     | Upload files to your Nekoweb website
    \\  delete     | Delete file or directory from your Nekoweb website
    \\  move       | Move/Rename a file or directory
    // \\  edit       | Edit a file
    \\  list       | List files from your Nekoweb website
    \\  logout     | Remove your API key from the save file
    \\  help       | Display information about a command
    \\  version    | Display program version
    \\
;

const usage_info =
    \\Usage: {s} info [username]
    \\
    \\Display informations about a Nekoweb website
    \\If no username is specified, informations about your own website is displayed
    \\
;

const usage_create =
    \\Usage: {s} create [-d] [pathname]
    \\
    \\Create a new file or directory on your Nekoweb website
    \\If the -d flag is specified, the pathname will be created as a directory
    \\
;

const usage_upload =
    \\Usage: {s} upload [files]... [destination]
    \\
    \\Upload files to your Nekoweb website
    \\Big files and zip are automatically handled
    \\If no destination is specified, the default is the root directory
    \\
;

const usage_delete =
    \\Usage: {s} delete [files]...
    \\
    \\Delete files or directories on your Nekoweb website
    \\Be careful, this action cannot be undone
    \\
;

const usage_move =
    \\Usage: {s} move [source] [destination]
    \\
    \\Move/Rename a file or directory on your Nekoweb website
    \\
;

const usage_list =
    \\Usage: {s} list [--no-color] [--only-dir] [directory]
    \\
    \\Display the content of a directory on your Nekoweb website
    \\If no directory is specified, all files will be listed recursively
    \\
    \\Flags:
    \\  --no-color    Disable color output
    \\  --only-dir    Display only directories
    \\
;

const usage_logout =
    \\Usage: {s} logout
    \\
    \\Remove your API key from the save file
    \\You will need to re-enter your API key the next time you use the program
    \\
;

const usage_help =
    \\Usage: {s} help [command]
    \\
    \\Display information about a command
    \\If no command is specified, display the general usage
    \\
;

const usage_version =
    \\Usage: {s} version
    \\
    \\Display program version
    \\
;

const Color = enum(u8) {
    black = 30,
    red,
    green,
    yellow,
    blue,
    magenta,
    cyan,
    white,
    default,
    bright_black = 90,
    bright_red,
    bright_green,
    bright_yellow,
    bright_blue,
    bright_magenta,
    bright_cyan,
    bright_white,

    const csi = "\x1b[";
    const reset = csi ++ "0m";
    const bold = csi ++ "1m";

    fn toSeq(comptime fg: Color) []const u8 {
        return comptime csi ++ std.fmt.digits2(@intFromEnum(fg)) ++ "m";
    }
};

var progname: []const u8 = undefined;

fn coloredLog(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime switch (message_level) {
        .err => Color.bold ++ Color.red.toSeq() ++ "error" ++ Color.reset,
        .warn => Color.bold ++ Color.yellow.toSeq() ++ "warning" ++ Color.reset,
        .info => Color.bold ++ Color.blue.toSeq() ++ "info" ++ Color.reset,
        .debug => Color.bold ++ Color.cyan.toSeq() ++ "debug" ++ Color.reset,
    };
    const scope_prefix = (if (scope != .default) "@" ++ @tagName(scope) else "") ++ ": ";
    const stderr = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stderr);
    const writer = bw.writer();

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    nosuspend {
        writer.print(level_txt ++ scope_prefix ++ format ++ "\n", args) catch return;
        bw.flush() catch return;
    }
}

fn getApiKey(allocator: std.mem.Allocator) ![]const u8 {
    var config_dir = try known_folders.open(allocator, .local_configuration, .{}) orelse {
        std.log.err("Failed to open the configuration directory", .{});
        std.process.exit(1);
    };
    defer config_dir.close();
    if (config_dir.openFile(config_path, .{})) |config_file| {
        defer config_file.close();
        const api_key = try config_file.readToEndAlloc(allocator, 4096);
        if (api_key.len != Nekoweb.api_key_len) {
            std.log.warn("Saved API key is invalid: expected {d} bytes, got {d}", .{
                Nekoweb.api_key_len,
                api_key.len,
            });
            allocator.free(api_key);
        } else {
            return api_key;
        }
    } else |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    }
    try config_dir.makeDir(config_dirname);
    const config_file = try config_dir.createFile(config_path, .{});
    defer config_file.close();

    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    try stdout.writeAll("Please enter your API key\n");
    try stdout.writeAll("You can find it at https://nekoweb.org/api\n");
    const max_retries = 5;
    const api_key = for (0..max_retries) |_| {
        try stdout.writeAll("API Key: ");
        const data = stdin.readUntilDelimiterAlloc(allocator, '\n', 4096) catch |err| switch (err) {
            error.EndOfStream => {
                try stdout.writeAll("\n");
                continue;
            },
            else => return err,
        };
        if (data.len != Nekoweb.api_key_len) {
            std.log.warn("API key is invalid: expected {d} bytes, got {d}", .{
                Nekoweb.api_key_len,
                data.len,
            });
            allocator.free(data);
            continue;
        }
        break data;
    } else {
        std.log.err("Too many retries, exiting", .{});
        std.process.exit(1);
    };

    try config_file.writeAll(api_key);
    std.log.info("Your API key has been saved", .{});

    return api_key;
}

fn formatUnsigned(dest: []u8, number: anytype) []u8 {
    var buf: [@sizeOf(@TypeOf(number)) * 4]u8 = undefined;
    std.debug.assert(buf.len <= dest.len);

    var i = buf.len;
    var n = number;
    var size_n: usize = 1;
    while (true) {
        i -= 1;
        buf[i] = @as(u8, @intCast(n % 10)) + '0';
        n /= 10;
        if (n == 0) {
            break;
        }
        if (size_n % 3 == 0) {
            i -= 1;
            buf[i] = ',';
        }
        size_n += 1;
    }

    return std.fmt.bufPrint(dest, "{s}", .{buf[i..]}) catch unreachable;
}

fn formatTime(dest: []u8, epoch: u64) []u8 {
    const epoch_secs: std.time.epoch.EpochSeconds = .{ .secs = epoch };
    const day_secs = epoch_secs.getDaySeconds();
    const epoch_day = epoch_secs.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    return std.fmt.bufPrint(dest, "{d:0>2} {s} {d:0>4} {d:0>2}:{d:0>2}:{d:0>2}", .{
        month_day.day_index,
        @tagName(month_day.month),
        year_day.year,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch unreachable;
}

fn info(nekoweb: *Nekoweb, allocator: std.mem.Allocator, username: ?[]const u8) !void {
    const response = try nekoweb.info(username);
    defer response.deinit();

    if (response.status != .ok) {
        const parsed = try std.json.parseFromSlice(
            struct { @"error": []const u8 },
            allocator,
            response.body.message.items,
            .{},
        );
        defer parsed.deinit();
        std.log.err("Failed to get info for {s}: {s} ({s})", .{
            username orelse "your website",
            parsed.value.@"error",
            @tagName(response.status),
        });
        std.process.exit(1);
    }

    const value = response.body.json.value;
    var buf: [128]u8 = undefined;
    const stdout = std.io.getStdOut().writer();

    try stdout.print(Color.bold ++ "Username" ++ Color.reset ++ ":     {s}\n" ++
        Color.bold ++ "Title" ++ Color.reset ++ ":        {s}\n" ++
        Color.bold ++ "Views" ++ Color.reset ++ ":        {s}\n" ++
        Color.bold ++ "Followers" ++ Color.reset ++ ":    {s}\n" ++
        Color.bold ++ "Created at" ++ Color.reset ++ ":   {s}\n" ++
        Color.bold ++ "Last updated" ++ Color.reset ++ ": {s}\n", .{
        value.username,
        value.title,
        formatUnsigned(buf[0..], value.views),
        formatUnsigned(buf[32..], value.followers),
        formatTime(buf[64..], value.created_at / std.time.ms_per_s),
        formatTime(buf[96..], value.updated_at / std.time.ms_per_s),
    });
}

fn create(nekoweb: *Nekoweb, args: *std.process.ArgIterator) !void {
    var is_dir = false;
    var pathname: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-d")) {
            is_dir = true;
        } else {
            if (pathname) |name| {
                std.log.warn("Replacing previous pathname '{s}' with '{s}'", .{ name, arg });
            }
            pathname = arg;
        }
    }

    if (pathname) |name| {
        const response = try nekoweb.create(name, is_dir);
        defer response.deinit();

        if (response.status != .ok) {
            std.log.err("Failed to create '{s}': {s} ({s})", .{
                name,
                response.body,
                @tagName(response.status),
            });
            std.process.exit(1);
        }

        std.log.info("'{s}' has been created: {s}", .{ name, response.body });
    } else {
        std.log.err("No pathname specified", .{});
        std.process.exit(1);
    }
}

fn upload(nekoweb: *Nekoweb, allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    var filenames = std.ArrayList([]const u8).init(allocator);
    defer filenames.deinit();
    while (args.next()) |arg| {
        try filenames.append(arg);
    }

    var destname: []const u8 = undefined;
    if (filenames.items.len == 0) {
        std.log.err("No file specified to upload", .{});
        std.process.exit(1);
    } else if (filenames.items.len == 1) {
        std.log.warn("No destination specified, defaulting to '/'", .{});
        destname = "/";
    } else {
        destname = filenames.pop();
    }

    const cwd = std.fs.cwd();
    for (filenames.items) |filename| {
        const stat = cwd.statFile(filename) catch |err| switch (err) {
            error.FileNotFound => {
                std.log.err("'{s}' does not exist", .{filename});
                std.process.exit(1);
            },
            else => return err,
        };

        std.log.info("Uploading '{s}' to '{s}' ...", .{ filename, destname });

        const response = if (stat.size > Nekoweb.max_file_size) blk: {
            std.log.warn("'{s}' is a big file ({d}B)", .{ filename, stat.size });

            const create_response = try nekoweb.bigCreate();
            defer create_response.deinit();
            if (create_response.status != .ok) {
                std.log.err("Failed to create a new big file: {s} ({s})", .{
                    create_response.body.message.items,
                    @tagName(create_response.status),
                });
                continue;
            }
            const id = create_response.body.json.value.id;

            const upload_response = try nekoweb.bigUpload(id, filename);
            defer upload_response.deinit();
            if (upload_response.status != .ok) {
                std.log.err("Failed to upload big file '{s}': {s} ({s})", .{
                    filename,
                    upload_response.body,
                    @tagName(upload_response.status),
                });
                continue;
            }

            if (std.mem.endsWith(u8, filename, ".zip")) {
                std.log.info("'{s}' is a zip file, importing content ...", .{filename});
                std.time.sleep(2 * std.time.ns_per_s);
                break :blk try nekoweb.import(id);
            } else {
                break :blk try nekoweb.bigMove(id, destname);
            }
        } else blk: {
            break :blk try nekoweb.upload(&[_][]const u8{filename}, destname);
        };
        defer response.deinit();

        if (response.status != .ok) {
            std.log.err("Failed to upload '{s}': {s} ({s})", .{
                filename,
                response.body,
                @tagName(response.status),
            });
        } else {
            std.log.info(
                "{s}",
                .{response.body},
            );
        }
    }
}

fn delete(nekoweb: *Nekoweb, args: *std.process.ArgIterator) !void {
    while (args.next()) |pathname| {
        const response = try nekoweb.delete(pathname);
        defer response.deinit();

        if (response.status != .ok) {
            std.log.err("Failed to delete '{s}': {s} ({s})", .{
                pathname,
                response.body,
                @tagName(response.status),
            });
            continue;
        }

        std.log.info("'{s}' has been delete: {s}", .{ pathname, response.body });
    }
}

fn move(nekoweb: *Nekoweb, args: *std.process.ArgIterator) !void {
    const src = args.next() orelse {
        std.log.err("No source specified", .{});
        std.process.exit(1);
    };
    const dest = args.next() orelse {
        std.log.err("No destination specified", .{});
        std.process.exit(1);
    };

    const response = try nekoweb.rename(src, dest);
    defer response.deinit();

    if (response.status != .ok) {
        std.log.err("Failed to move '{s}' to '{s}': {s} ({s})", .{
            src,
            dest,
            response.body,
            @tagName(response.status),
        });
        std.process.exit(1);
    }

    std.log.info("'{s}' has been moved to '{s}': {s}", .{ src, dest, response.body });
}

fn recursiveList(
    nekoweb: *Nekoweb,
    pathname: []const u8,
    color: bool,
    only_dir: bool,
) !void {
    const response = try nekoweb.readFolder(pathname);
    defer response.deinit();

    if (response.status != .ok) {
        std.log.err("Failed to list '{s}': {s} ({s})", .{
            pathname,
            response.body.message.items,
            @tagName(response.status),
        });
        std.process.exit(1);
    }

    const stdout = std.io.getStdOut().writer();
    for (response.body.json.value) |file| {
        if (file.dir) {
            if (color) {
                try stdout.print(
                    Color.bold ++ Color.blue.toSeq() ++ "{s}{s}\n" ++ Color.reset,
                    .{ pathname[1..], file.name },
                );
            } else {
                try stdout.print("{s}{s}\n", .{ pathname[1..], file.name });
            }
            var buffer: [4096]u8 = undefined;
            try recursiveList(
                nekoweb,
                try std.fmt.bufPrint(&buffer, "{s}{s}/", .{ pathname, file.name }),
                color,
                only_dir,
            );
        } else if (!only_dir) {
            try stdout.print("{s}{s}\n", .{ pathname[1..], file.name });
        }
    }
}

fn list(nekoweb: *Nekoweb, args: *std.process.ArgIterator) !void {
    var pathname: []const u8 = "/";
    var recursive_root = true;
    var color = true;
    var only_dir = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--no-color")) {
            color = false;
        } else if (std.mem.eql(u8, arg, "--only-dir")) {
            only_dir = true;
        } else {
            pathname = arg;
            recursive_root = false;
        }
    }

    if (recursive_root) {
        return recursiveList(nekoweb, pathname, color, only_dir);
    }

    const response = try nekoweb.readFolder(pathname);
    defer response.deinit();

    if (response.status != .ok) {
        std.log.err("Failed to list '{s}': {s} ({s})", .{
            pathname,
            response.body.message.items,
            @tagName(response.status),
        });
        std.process.exit(1);
    }

    const stdout = std.io.getStdOut().writer();
    for (response.body.json.value) |file| {
        if (file.dir) {
            if (color) {
                try stdout.print(
                    Color.bold ++ Color.blue.toSeq() ++ "{s}\n" ++ Color.reset,
                    .{file.name},
                );
            } else {
                try stdout.print("{s}\n", .{file.name});
            }
        } else if (!only_dir) {
            try stdout.print("{s}\n", .{file.name});
        }
    }
}

fn logout(allocator: std.mem.Allocator) !void {
    var config_dir = try known_folders.open(allocator, .local_configuration, .{}) orelse {
        std.log.err("Failed to open the configuration directory", .{});
        std.process.exit(1);
    };
    defer config_dir.close();
    config_dir.deleteFile(config_path) catch |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    };
    std.log.info("Your API key has been removed", .{});
}

fn help(command: ?[]const u8) !void {
    const stderr = std.io.getStdErr().writer();
    if (command) |cmd| {
        if (std.mem.eql(u8, cmd, "info")) {
            try stderr.print(usage_info, .{progname});
        } else if (std.mem.eql(u8, cmd, "create")) {
            try stderr.print(usage_create, .{progname});
        } else if (std.mem.eql(u8, cmd, "upload")) {
            try stderr.print(usage_upload, .{progname});
        } else if (std.mem.eql(u8, cmd, "delete")) {
            try stderr.print(usage_delete, .{progname});
        } else if (std.mem.eql(u8, cmd, "move")) {
            try stderr.print(usage_move, .{progname});
        } else if (std.mem.eql(u8, cmd, "list")) {
            try stderr.print(usage_list, .{progname});
        } else if (std.mem.eql(u8, cmd, "logout")) {
            try stderr.print(usage_logout, .{progname});
        } else if (std.mem.eql(u8, cmd, "help")) {
            try stderr.print(usage_help, .{progname});
        } else if (std.mem.eql(u8, cmd, "version")) {
            try stderr.print(usage_version, .{progname});
        } else {
            std.log.warn("Unknown command '{s}'", .{cmd});
            try stderr.print(usage, .{progname});
        }
    } else {
        try stderr.print(usage, .{progname});
    }
}

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    progname = args.next().?;

    const api_key = try getApiKey(allocator);
    defer allocator.free(api_key);
    var nekoweb = Nekoweb.init(allocator, api_key);
    defer nekoweb.deinit();

    const command = args.next() orelse {
        try help(null);
        std.process.exit(1);
    };

    if (std.mem.eql(u8, command, "info")) {
        try info(&nekoweb, allocator, args.next());
    } else if (std.mem.eql(u8, command, "create")) {
        try create(&nekoweb, &args);
    } else if (std.mem.eql(u8, command, "upload")) {
        try upload(&nekoweb, allocator, &args);
    } else if (std.mem.eql(u8, command, "delete")) {
        try delete(&nekoweb, &args);
    } else if (std.mem.eql(u8, command, "move")) {
        try move(&nekoweb, &args);
    } else if (std.mem.eql(u8, command, "list")) {
        try list(&nekoweb, &args);
    } else if (std.mem.eql(u8, command, "logout")) {
        try logout(allocator);
    } else if (std.mem.eql(u8, command, "help")) {
        try help(args.next());
    } else if (std.mem.eql(u8, command, "version")) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s} " ++ version ++ "\n", .{progname});
    } else {
        try help(command);
        std.process.exit(1);
    }
}
