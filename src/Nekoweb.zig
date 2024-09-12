const std = @import("std");
const Nekoweb = @This();

const api_url = "https://nekoweb.org/api";
const boundary = "x------------xXx--------------x";
pub const api_key_len = 64;
pub const max_file_size = 100 * 1000 * 1000;

api_key: []const u8,
client: std.http.Client,
allocator: std.mem.Allocator,

// not available
const Limits = struct {
    general: Limit,
    big_uploads: Limit,
    zip: Limit,

    const Limit = struct {
        limit: u32,
        remaining: ?u32,
        reset: ?i64,
    };
};

pub const Info = struct {
    id: u32,
    username: []const u8,
    title: []const u8,
    updates: u32,
    followers: u32,
    views: u32,
    created_at: u64, // epoch in milliseconds
    updated_at: u64, // epoch in milliseconds
};

pub const ReadFolder = []const struct {
    name: []const u8,
    dir: bool,
};

pub const BigCreate = struct {
    id: []const u8,
};

pub fn Response(comptime Type: ?type) type {
    if (Type) |T| {
        return struct {
            status: std.http.Status,
            body: union(enum) {
                json: std.json.Parsed(T),
                message: std.ArrayList(u8),
            },

            pub fn deinit(self: @This()) void {
                switch (self.body) {
                    .json => |json| json.deinit(),
                    .message => |msg| msg.deinit(),
                }
            }
        };
    } else {
        return struct {
            status: std.http.Status,
            body: []const u8,
            allocator: std.mem.Allocator,

            pub fn deinit(self: @This()) void {
                self.allocator.free(self.body);
            }
        };
    }
}

pub fn init(allocator: std.mem.Allocator, api_key: []const u8) Nekoweb {
    return .{
        .api_key = api_key,
        .client = .{ .allocator = allocator },
        .allocator = allocator,
    };
}

pub fn deinit(self: *Nekoweb) void {
    self.client.deinit();
}

// TODO: no need for auth if username is provided
/// Get information about a user's site or the authenticated user's site.
pub fn info(self: *Nekoweb, username: ?[]const u8) !Response(Info) {
    const url = if (username) |name|
        try std.fmt.allocPrint(self.allocator, api_url ++ "/site/info/{s}", .{name})
    else
        try std.fmt.allocPrint(self.allocator, api_url ++ "/site/info", .{});
    defer self.allocator.free(url);
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .GET,
        .headers = .{ .authorization = .{ .override = self.api_key } },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    if (result.status == .ok) {
        const json = try std.json.parseFromSlice(
            Info,
            self.allocator,
            response.items,
            .{ .allocate = .alloc_always },
        );
        response.deinit();
        return .{
            .status = result.status,
            .body = .{ .json = json },
        };
    } else {
        return .{
            .status = result.status,
            .body = .{ .message = response },
        };
    }
}

/// Create a new file or folder.
pub fn create(self: *Nekoweb, pathname: []const u8, is_folder: bool) !Response(null) {
    const url = api_url ++ "/files/create";
    const payload = try std.fmt.allocPrint(
        self.allocator,
        "pathname={s}&isFolder={}",
        .{ pathname, is_folder },
    );
    defer self.allocator.free(payload);
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .POST,
        .payload = payload,
        .headers = .{
            .authorization = .{ .override = self.api_key },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    return .{
        .status = result.status,
        .body = try response.toOwnedSlice(),
        .allocator = self.allocator,
    };
}

/// Upload a file or files. THis will overwrite old files. Max 100MB.
pub fn upload(self: *Nekoweb, filenames: []const []const u8, destname: []const u8) !Response(null) {
    if (filenames.len == 0) {
        return error.EmptySlice;
    }

    const url = api_url ++ "/files/upload";
    var payload_builder = std.ArrayList(u8).init(self.allocator);
    defer payload_builder.deinit();
    try payload_builder.appendSlice("--" ++ boundary ++ "\r\n");
    try payload_builder.appendSlice("Content-Disposition: form-data; name=\"pathname\"\r\n\r\n");
    try payload_builder.appendSlice(destname);
    try payload_builder.appendSlice("\r\n--" ++ boundary);
    const cwd = std.fs.cwd();
    for (filenames) |filename| {
        try payload_builder.appendSlice("\r\nContent-Disposition: form-data; name=\"files\"; filename=\"");
        try payload_builder.appendSlice(filename);
        try payload_builder.appendSlice("\"\r\n\r\n");
        const file = try cwd.openFile(filename, .{});
        defer file.close();
        try file.reader().readAllArrayList(&payload_builder, max_file_size);
        try payload_builder.appendSlice("\r\n--" ++ boundary);
    }
    try payload_builder.appendSlice("--\r\n");
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .POST,
        .payload = payload_builder.items,
        .headers = .{
            .authorization = .{ .override = self.api_key },
            .content_type = .{ .override = "multipart/form-data; boundary=" ++ boundary },
        },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    return .{
        .status = result.status,
        .body = try response.toOwnedSlice(),
        .allocator = self.allocator,
    };
}

/// Delete a file or folder.
pub fn delete(self: *Nekoweb, pathname: []const u8) !Response(null) {
    const url = api_url ++ "/files/delete";
    const payload = try std.fmt.allocPrint(self.allocator, "pathname={s}", .{pathname});
    defer self.allocator.free(payload);
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .POST,
        .payload = payload,
        .headers = .{
            .authorization = .{ .override = self.api_key },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    return .{
        .status = result.status,
        .body = try response.toOwnedSlice(),
        .allocator = self.allocator,
    };
}

/// Rename/Move a file or folder.
pub fn rename(self: *Nekoweb, pathname: []const u8, new_pathname: []const u8) !Response(null) {
    const url = api_url ++ "/files/rename";
    const payload = try std.fmt.allocPrint(
        self.allocator,
        "pathname={s}&newpathname={s}",
        .{ pathname, new_pathname },
    );
    defer self.allocator.free(payload);
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .POST,
        .payload = payload,
        .headers = .{
            .authorization = .{ .override = self.api_key },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    return .{
        .status = result.status,
        .body = try response.toOwnedSlice(),
        .allocator = self.allocator,
    };
}

/// Edit a file.
pub fn edit(self: *Nekoweb, pathname: []const u8, content: []const u8) !Response(null) {
    const url = api_url ++ "/files/edit";
    var payload_builder = std.ArrayList(u8).init(self.allocator);
    defer payload_builder.deinit();
    try payload_builder.appendSlice("--" ++ boundary ++ "\r\n");
    try payload_builder.appendSlice("Content-Disposition: form-data; name=\"pathname\"\r\n\r\n");
    try payload_builder.appendSlice(pathname);
    try payload_builder.appendSlice("\r\n--" ++ boundary ++ "\r\n");
    try payload_builder.appendSlice("Content-Disposition: form-data; name=\"content\"\r\n\r\n");
    try payload_builder.appendSlice(content);
    try payload_builder.appendSlice("\r\n--" ++ boundary ++ "--\r\n");
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .POST,
        .payload = payload_builder.items,
        .headers = .{
            .authorization = .{ .override = self.api_key },
            .content_type = .{ .override = "multipart/form-data; boundary=" ++ boundary },
        },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    return .{
        .status = result.status,
        .body = try response.toOwnedSlice(),
        .allocator = self.allocator,
    };
}

/// Read a folder.
pub fn readFolder(self: *Nekoweb, pathname: []const u8) !Response(ReadFolder) {
    const url = try std.fmt.allocPrint(
        self.allocator,
        api_url ++ "/files/readfolder?pathname={query}",
        .{std.Uri.Component{ .raw = pathname }},
    );
    defer self.allocator.free(url);
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .GET,
        .headers = .{ .authorization = .{ .override = self.api_key } },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    if (result.status == .ok) {
        const json = try std.json.parseFromSlice(
            ReadFolder,
            self.allocator,
            response.items,
            .{ .allocate = .alloc_always },
        );
        response.deinit();
        return .{
            .status = result.status,
            .body = .{ .json = json },
        };
    } else {
        return .{
            .status = result.status,
            .body = .{ .message = response },
        };
    }
}

/// Create upload for a big file. Allows to upload files larger than 100MB.
pub fn bigCreate(self: *Nekoweb) !Response(BigCreate) {
    const url = api_url ++ "/files/big/create";
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .GET,
        .headers = .{ .authorization = .{ .override = self.api_key } },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    if (result.status == .ok) {
        const json = try std.json.parseFromSlice(
            BigCreate,
            self.allocator,
            response.items,
            .{ .allocate = .alloc_always },
        );
        response.deinit();
        return .{
            .status = result.status,
            .body = .{ .json = json },
        };
    } else {
        return .{
            .status = result.status,
            .body = .{ .message = response },
        };
    }
}

/// Upload a big file. Allows to upload files larger than 100MB.
/// Make sure to call bigMove() or import() after this
pub fn bigUpload(self: *Nekoweb, id: []const u8, filename: []const u8) !Response(null) {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var payload_builder = try std.ArrayList(u8).initCapacity(self.allocator, max_file_size + 4096);
    defer payload_builder.deinit();
    var done = false;
    while (!done) {
        const url = api_url ++ "/files/big/append";
        payload_builder.clearRetainingCapacity();
        payload_builder.appendSliceAssumeCapacity("--" ++ boundary ++ "\r\n");
        payload_builder.appendSliceAssumeCapacity("Content-Disposition: form-data; name=\"id\"\r\n\r\n");
        payload_builder.appendSliceAssumeCapacity(id);
        payload_builder.appendSliceAssumeCapacity("\r\n--" ++ boundary ++ "\r\n");
        payload_builder.appendSliceAssumeCapacity("Content-Disposition: form-data; name=\"file\"; filename=\"");
        payload_builder.appendSliceAssumeCapacity(filename);
        payload_builder.appendSliceAssumeCapacity("\"\r\n\r\n");

        const original_len = payload_builder.items.len;
        payload_builder.items.len = original_len + max_file_size - 1;
        const dest_slice = payload_builder.items[original_len..];
        const bytes_read = try file.readAll(dest_slice);
        if (bytes_read != dest_slice.len) {
            payload_builder.shrinkRetainingCapacity(original_len + bytes_read);
            done = true;
        }
        payload_builder.appendSliceAssumeCapacity("\r\n--" ++ boundary ++ "--\r\n");
        var response = std.ArrayList(u8).init(self.allocator);
        errdefer response.deinit();

        const result = try self.client.fetch(.{
            .method = .POST,
            .payload = payload_builder.items,
            .headers = .{
                .authorization = .{ .override = self.api_key },
                .content_type = .{ .override = "multipart/form-data; boundary=" ++ boundary },
            },
            .response_storage = .{ .dynamic = &response },
            .location = .{ .url = url },
        });

        if (result.status != .ok) {
            return .{
                .status = result.status,
                .body = try response.toOwnedSlice(),
                .allocator = self.allocator,
            };
        } else {
            response.deinit();
        }
    }

    return .{
        .status = .ok,
        .body = try self.allocator.dupe(u8, "Uploaded"),
        .allocator = self.allocator,
    };
}

pub fn bigMove(self: *Nekoweb, id: []const u8, pathname: []const u8) !Response(null) {
    const url = api_url ++ "/files/big/move";
    const payload = try std.fmt.allocPrint(
        self.allocator,
        "id={s}&pathname={s}",
        .{ id, pathname },
    );
    defer self.allocator.free(payload);
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .POST,
        .payload = payload,
        .headers = .{
            .authorization = .{ .override = self.api_key },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    return .{
        .status = result.status,
        .body = try response.toOwnedSlice(),
        .allocator = self.allocator,
    };
}

pub fn import(self: *Nekoweb, big_id: []const u8) !Response(null) {
    const url = try std.fmt.allocPrint(
        self.allocator,
        api_url ++ "/files/import/{s}",
        .{big_id},
    );
    defer self.allocator.free(url);
    const payload = "";
    var response = std.ArrayList(u8).init(self.allocator);
    errdefer response.deinit();

    const result = try self.client.fetch(.{
        .method = .POST,
        .payload = payload,
        .headers = .{
            .authorization = .{ .override = self.api_key },
            .content_type = .{ .override = "application/x-www-form-urlencoded" },
        },
        .response_storage = .{ .dynamic = &response },
        .location = .{ .url = url },
    });

    return .{
        .status = result.status,
        .body = try response.toOwnedSlice(),
        .allocator = self.allocator,
    };
}
