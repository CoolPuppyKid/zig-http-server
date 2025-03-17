const std = @import("std");
const net = std.net;
const posix = std.posix;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            @panic("Memory Leak In Server Please Report This");
        }
    }

    const address = try std.net.Address.parseIp("0.0.0.0", 5882);
    const tpe: u32 = posix.SOCK.STREAM;
    const protocol = posix.IPPROTO.TCP;
    const listener = try posix.socket(address.any.family, tpe, protocol);
    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &address.any, address.getOsSockLen());
    try posix.listen(listener, 128);

    const file = try std.fs.cwd().openFile("index.html", .{});
    defer file.close();
    const html = try file.readToEndAlloc(allocator, 4086);
    defer allocator.free(html);

    var response = std.ArrayList(u8).init(allocator);
    defer response.deinit();

    try response.appendSlice("HTTP/1.1 200 OK\r\n");
    try response.appendSlice("Content-Type: text/html\r\n");
    try response.appendSlice("Content-Length: ");
    try response.appendSlice(std.fmt.allocPrint(allocator, "{}\r\n", .{html.len}) catch unreachable);
    try response.appendSlice("Connection: close\r\n\r\n");
    try response.appendSlice(html);

    var socket: ?posix.socket_t = null;
    defer {
        if (socket) |sock| {
            posix.close(sock);
        }
    }

    while (true) {
        var client_address: net.Address = undefined;
        var client_address_len: posix.socklen_t = @sizeOf(net.Address);
        socket = posix.accept(listener, &client_address.any, &client_address_len, 0) catch |err| {
            std.debug.print("Error accepting client: {}\n", .{err});
            continue;
        };

        std.debug.print("{} connected!\n", .{client_address});
        try run(socket.?, response.items);
    }
}

fn run(socket: posix.socket_t, response: []const u8) !void {
    write(socket, response) catch |err| {
        std.debug.print("Error writing to client: {}\n", .{err});
    };
    posix.close(socket);
}

fn write(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;
    while (pos < msg.len) {
        const written = posix.write(socket, msg[pos..]) catch |err| {
            std.debug.print("Error writing to client: {}\n", .{err});
            return err;
        };
        if (written == 0) {
            return error.Closed;
        }
        pos += written;
    }
}
