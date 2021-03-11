const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const Allocator = std.mem.Allocator;

const array_map = @This();

pub fn AutoArrayMap(comptime K: type, comptime V: type) type {
    return ArrayMap(K, V, std.hash_map.getAutoEqlFn(K));
}

pub fn ArrayMap(
    comptime K: type,
    comptime V: type,
    comptime eql: fn (a: K, b: K) bool,
) type {
    return struct {
        unmanaged: Unmanaged,
        allocator: *Allocator,

        pub const Unmanaged = ArrayMapUnmanaged(K, V, eql);
        pub const Entry = Unmanaged.Entry;
        pub const GetOrPutResult = Unmanaged.GetOrPutResult;

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return .{
                .unmanaged = .{},
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.unmanaged.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            return self.unmanaged.clearRetainingCapacity();
        }

        pub fn clearAndFree(self: *Self) void {
            return self.unmanaged.clearAndFree(self.allocator);
        }

        pub fn count(self: Self) usize {
            return self.unmanaged.count();
        }

        /// Increases capacity, guaranteeing that insertions up until the
        /// `expected_count` will not cause an allocation, and therefore cannot fail.
        pub fn ensureCapacity(self: *Self, new_capacity: usize) !void {
            return self.unmanaged.ensureCapacity(self.allocator, new_capacity);
        }

        /// Returns the number of total elements which may be present before it is
        /// no longer guaranteed that no allocations will be performed.
        pub fn capacity(self: *Self) usize {
            return self.unmanaged.capacity();
        }

        /// Clobbers any existing data. To detect if a put would clobber
        /// existing data, see `getOrPut`.
        pub fn put(self: *Self, key: K, value: V) !void {
            return self.unmanaged.put(self.allocator, key, value);
        }

        /// Inserts a key-value pair into the map, asserting that no previous
        /// entry with the same key is already present
        pub fn putNoClobber(self: *Self, key: K, value: V) !void {
            return self.unmanaged.putNoClobber(self.allocator, key, value);
        }

        /// Inserts a new `Entry` into the map, returning the previous one, if any.
        pub fn fetchPut(self: *Self, key: K, value: V) !?Entry {
            return self.unmanaged.fetchPut(self.allocator, key, value);
        }

        /// Inserts a new `Entry` into the map, returning the previous one, if any.
        /// If insertion happuns, asserts there is enough capacity without allocating.
        pub fn fetchPutAssumeCapacity(self: *Self, key: K, value: V) ?Entry {
            return self.unmanaged.fetchPutAssumeCapacity(key, value);
        }

        pub fn getEntry(self: Self, key: K) ?*Entry {
            return self.unmanaged.getEntry(key);
        }

        pub fn getIndex(self: Self, key: K) ?usize {
            return self.unmanaged.getIndex(key);
        }

        pub fn get(self: Self, key: K) ?V {
            return self.unmanaged.get(key);
        }

        /// If key exists this function cannot fail.
        /// If there is an existing item with `key`, then the result
        /// `Entry` pointer points to it, and found_existing is true.
        /// Otherwise, puts a new item with undefined value, and
        /// the `Entry` pointer points to it. Caller should then initialize
        /// the value (but not the key).
        pub fn getOrPut(self: *Self, key: K) !GetOrPutResult {
            return self.unmanaged.getOrPut(self.allocator, key);
        }

        pub fn getOrPutValue(self: *Self, key: K, value: V) !*Entry {
            return self.unmanaged.getOrPutValue(self.allocator, key, value);
        }

        pub fn contains(self: Self, key: K) bool {
            return self.unmanaged.contains(key);
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the map, and then returned from this function. The entry is
        /// removed from the underlying array by swapping it with the last
        /// element.
        pub fn swapRemove(self: *Self, key: K) ?Entry {
            return self.unmanaged.swapRemove(key);
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the map, and then returned from this function. The entry is
        /// removed from the underlying array by shifting all elements forward
        /// thereby maintaining the current ordering.
        pub fn orderedRemove(self: *Self, key: K) ?Entry {
            return self.unmanaged.orderedRemove(key);
        }

        /// Asserts there is an `Entry` with matching key, deletes it from the map
        /// by swapping it with the last element, and discards it.
        pub fn swapRemoveAssertDiscard(self: *Self, key: K) void {
            return self.unmanaged.swapRemoveAssertDiscard(key);
        }

        /// Asserts there is an `Entry` with matching key, deletes it from the map
        /// by by shifting all elements forward thereby maintaining the current ordering.
        pub fn orderedRemoveAssertDiscard(self: *Self, key: K) void {
            return self.unmanaged.orderedRemoveAssertDiscard(key);
        }

        pub fn items(self: Self) []Entry {
            return self.unmanaged.items();
        }

        pub fn clone(self: Self) !Self {
            var other = try self.unmanaged.clone(self.allocator);
            return other.promote(self.allocator);
        }

        /// Shrinks the underlying `Entry` array to `new_len` elements.
        /// Keeps capacity the same.
        pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
            return self.unmanaged.shrinkRetainingCapacity(new_len);
        }

        /// Shrinks the underlying `Entry` array to `new_len` element.s
        /// Reduces allocated capacity.
        pub fn shrinkAndFree(self: *Self, new_len: usize) void {
            return self.unmanaged.shrinkAndFree(self.allocator, new_len);
        }

        /// Removes the last inserted `Entry` in the map and returns it.
        pub fn pop(self: *Self) Entry {
            return self.unmanaged.pop();
        }
    };
}


pub fn ArrayMapUnmanaged(
    comptime K: type,
    comptime V: type,
    comptime eql: fn (a: K, b: K) bool,
) type {
    return struct {
        entries: std.ArrayListUnmanaged(Entry) = .{},

        pub const Entry = struct {
            key: K,
            value: V,
        };

        pub const GetOrPutResult = struct {
            entry: *Entry,
            found_existing: bool,
            index: usize,
        };

        const Self = @This();

        const RemovalType = enum {
            swap,
            ordered,
        };

        pub const Managed = ArrayMap(K, V, eql);

        pub fn promote(self: Self, allocator: *Allocator) Managed {
            return .{
                .unmanaged = self,
                .allocator = allocator,
            };
        }

        pub fn count(self: Self) usize {
            return self.entries.items.len;
        }

        pub fn deinit(self: *Self, allocator: *Allocator) void {
            self.entries.deinit(allocator);
            self.* = undefined;
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.entries.items.len = 0;
        }

        pub fn clearAndFree(self: *Self, allocator: *Allocator) void {
            self.entries.shrinkAndFree(allocator, 0);
        }

        pub fn ensureCapacity(self: *Self, allocator: *Allocator, new_capacity: usize) !void {
            try self.entries.ensureCapacity(allocator, new_capacity);
        }

        /// Returns the number of total elements which may be present before it is
        /// no longer guaranteed that no allocations will be performed.
        pub fn capacity(self: Self) usize {
            return self.entries.capacity;
        }

        /// Clobbers any existing data. To detect if a put would clobber
        /// existing data, see `getOrPut`.
        pub fn put(self: *Self, allocator: *Allocator, key: K, value: V) !void {
            const result = try self.getOrPut(allocator, key);
            result.entry.value = value;
        }

        /// Inserts a key-value pair into the map, asserting that no previous
        /// entry with the same key is already present
        pub fn putNoClobber(self: *Self, allocator: *Allocator, key: K, value: V) !void {
            const result = try self.getOrPut(allocator, key);
            assert(!result.found_existing);
            result.entry.value = value;
        }

        pub fn getOrPut(self: *Self, allocator: *Allocator, key: K) !GetOrPutResult {
            self.ensureCapacity(allocator, self.entries.items.len + 1) catch |err| {
                // "If key exists this function cannot fail."
                const index = self.getIndex(key) orelse return err;
                return GetOrPutResult{
                    .entry = &self.entries.items[index],
                    .found_existing = true,
                    .index = index,
                };
            };
            return self.getOrPutAssumeCapacity(key);
        }

        pub fn getOrPutValue(self: *Self, allocator: *Allocator, key: K, value: V) !*Entry {
            const res = try self.getOrPut(allocator, key);
            if (!res.found_existing)
                res.entry.value = value;

            return res.entry;
        }

        pub fn getOrPutAssumeCapacity(self: *Self, key: K) GetOrPutResult {
            for (self.entries.items) |*item, i| {
                if (eql(key, item.key)) {
                    return GetOrPutResult{
                        .entry = item,
                        .found_existing = true,
                        .index = i,
                    };
                }
            }
            const new_entry = self.entries.addOneAssumeCapacity();
            new_entry.* = .{
                .key = key,
                .value = undefined,
            };
            return GetOrPutResult{
                .entry = new_entry,
                .found_existing = false,
                .index = self.entries.items.len - 1,
            };
        }

        pub fn getEntry(self: Self, key: K) ?*Entry {
            const index = self.getIndex(key) orelse return null;
            return &self.entries.items[index];
        }

        pub fn getIndex(self: Self, key: K) ?usize {
            // Linear scan.
            for (self.entries.items) |*item, i| {
                if (eql(key, item.key)) {
                    return i;
                }
            }
            return null;
        }

        pub fn get(self: Self, key: K) ?V {
            return if (self.getEntry(key)) |entry| entry.value else null;
        }

        /// Inserts a new `Entry` into the map, returning the previous one, if any.
        pub fn fetchPut(self: *Self, allocator: *Allocator, key: K, value: V) !?Entry {
            const gop = try self.getOrPut(allocator, key);
            var result: ?Entry = null;
            if (gop.found_existing) {
                result = gop.entry.*;
            }
            gop.entry.value = value;
            return result;
        }

        /// Inserts a new `Entry` into the map, returning the previous one, if any.
        /// If insertion happens, asserts there is enough capacity without allocating.
        pub fn fetchPutAssumeCapacity(self: *Self, key: K, value: V) ?Entry {
            const gop = self.getOrPutAssumeCapacity(key);
            var result: ?Entry = null;
            if (gop.found_existing) {
                result = gop.entry.*;
            }
            gop.entry.value = value;
            return result;
        }

        pub fn contains(self: Self, key: K) bool {
            return self.getEntry(key) != null;
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the map, and then returned from this function. The entry is
        /// removed from the underlying array by swapping it with the last
        /// element.
        pub fn swapRemove(self: *Self, key: K) ?Entry {
            return self.removeInternal(key, .swap);
        }

        /// If there is an `Entry` with a matching key, it is deleted from
        /// the map, and then returned from this function. The entry is
        /// removed from the underlying array by shifting all elements forward
        /// thereby maintaining the current ordering.
        pub fn orderedRemove(self: *Self, key: K) ?Entry {
            return self.removeInternal(key, .ordered);
        }

        /// Asserts there is an `Entry` with matching key, deletes it from the map
        /// by swapping it with the last element, and discards it.
        pub fn swapRemoveAssertDiscard(self: *Self, key: K) void {
            assert(self.swapRemove(key) != null);
        }

        /// Asserts there is an `Entry` with matching key, deletes it from the map
        /// by by shifting all elements forward thereby maintaining the current ordering.
        pub fn orderedRemoveAssertDiscard(self: *Self, key: K) void {
            assert(self.orderedRemove(key) != null);
        }

        pub fn items(self: Self) []Entry {
            return self.entries.items;
        }

        pub fn clone(self: Self, allocator: *Allocator) !Self {
            var other: Self = .{};
            try other.entries.appendSlice(allocator, self.entries.items);
            return other;
        }

        fn removeInternal(self: *Self, key: K, comptime removal_type: RemovalType) ?Entry {
            // Linear scan.
            for (self.entries.items) |item, i| {
                if (eql(key, item.key)) {
                    switch (removal_type) {
                        .swap => return self.entries.swapRemove(i),
                        .ordered => return self.entries.orderedRemove(i),
                    }
                }
            }
            return null;
        }

        /// Shrinks the underlying `Entry` array to `new_len` elements.
        /// Keeps capacity the same.
        pub fn shrinkRetainingCapacity(self: *Self, new_len: usize) void {
            self.entries.shrinkRetainingCapacity(new_len);
        }

        /// Shrinks the underlying `Entry` array to `new_len` elements.
        /// Reduces allocated capacity.
        pub fn shrinkAndFree(self: *Self, allocator: *Allocator, new_len: usize) void {
            self.entries.shrinkAndFree(allocator, new_len);
        }

        /// Removes the last inserted `Entry` in the map and returns it.
        pub fn pop(self: *Self) Entry {
            const top = self.entries.pop();
            return top;
        }
    };
}

test "basic array map usage" {
    var map = AutoArrayMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    testing.expect((try map.fetchPut(1, 11)) == null);
    testing.expect((try map.fetchPut(2, 22)) == null);
    testing.expect((try map.fetchPut(3, 33)) == null);
    testing.expect((try map.fetchPut(4, 44)) == null);

    try map.putNoClobber(5, 55);
    testing.expect((try map.fetchPut(5, 66)).?.value == 55);
    testing.expect((try map.fetchPut(5, 55)).?.value == 66);

    const gop1 = try map.getOrPut(5);
    testing.expect(gop1.found_existing == true);
    testing.expect(gop1.entry.value == 55);
    testing.expect(gop1.index == 4);
    gop1.entry.value = 77;
    testing.expect(map.getEntry(5).?.value == 77);

    const gop2 = try map.getOrPut(99);
    testing.expect(gop2.found_existing == false);
    testing.expect(gop2.index == 5);
    gop2.entry.value = 42;
    testing.expect(map.getEntry(99).?.value == 42);

    const gop3 = try map.getOrPutValue(5, 5);
    testing.expect(gop3.value == 77);

    const gop4 = try map.getOrPutValue(100, 41);
    testing.expect(gop4.value == 41);

    testing.expect(map.contains(2));
    testing.expect(map.getEntry(2).?.value == 22);
    testing.expect(map.get(2).? == 22);

    const rmv1 = map.swapRemove(2);
    testing.expect(rmv1.?.key == 2);
    testing.expect(rmv1.?.value == 22);
    testing.expect(map.swapRemove(2) == null);
    testing.expect(map.getEntry(2) == null);
    testing.expect(map.get(2) == null);

    // Since we've used `swapRemove` above, the index of this entry should remain unchanged.
    testing.expect(map.getIndex(100).? == 1);
    const gop5 = try map.getOrPut(5);
    testing.expect(gop5.found_existing == true);
    testing.expect(gop5.entry.value == 77);
    testing.expect(gop5.index == 4);

    // Whereas, if we do an `orderedRemove`, it should move the index forward one spot.
    const rmv2 = map.orderedRemove(100);
    testing.expect(rmv2.?.key == 100);
    testing.expect(rmv2.?.value == 41);
    testing.expect(map.orderedRemove(100) == null);
    testing.expect(map.getEntry(100) == null);
    testing.expect(map.get(100) == null);
    const gop6 = try map.getOrPut(5);
    testing.expect(gop6.found_existing == true);
    testing.expect(gop6.entry.value == 77);
    testing.expect(gop6.index == 3);

    map.swapRemoveAssertDiscard(3);
}

test "ensure capacity" {
    var map = AutoArrayMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    try map.ensureCapacity(20);
    const initial_capacity = map.capacity();
    testing.expect(initial_capacity >= 20);
    var i: i32 = 0;
    while (i < 20) : (i += 1) {
        testing.expect(map.fetchPutAssumeCapacity(i, i + 10) == null);
    }
    // shouldn't resize from putAssumeCapacity
    testing.expect(initial_capacity == map.capacity());
}

test "clone" {
    var original = AutoArrayMap(i32, i32).init(std.testing.allocator);
    defer original.deinit();

    var i: u8 = 0;
    while (i < 10) : (i += 1) {
        try original.putNoClobber(i, i * 10);
    }

    var copy = try original.clone();
    defer copy.deinit();

    i = 0;
    while (i < 10) : (i += 1) {
        testing.expect(copy.get(i).? == i * 10);
    }
}

test "shrink" {
    var map = AutoArrayMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    const num_entries = 20;
    var i: i32 = 0;
    while (i < num_entries) : (i += 1)
        testing.expect((try map.fetchPut(i, i * 10)) == null);

    testing.expect(map.count() == num_entries);

    // Test `shrinkRetainingCapacity`.
    map.shrinkRetainingCapacity(17);
    testing.expect(map.count() == 17);
    testing.expect(map.capacity() == 20);
    i = 0;
    while (i < num_entries) : (i += 1) {
        const gop = try map.getOrPut(i);
        if (i < 17) {
            testing.expect(gop.found_existing == true);
            testing.expect(gop.entry.value == i * 10);
        } else testing.expect(gop.found_existing == false);
    }

    // Test `shrinkAndFree`.
    map.shrinkAndFree(15);
    testing.expect(map.count() == 15);
    testing.expect(map.capacity() == 15);
    i = 0;
    while (i < num_entries) : (i += 1) {
        const gop = try map.getOrPut(i);
        if (i < 15) {
            testing.expect(gop.found_existing == true);
            testing.expect(gop.entry.value == i * 10);
        } else testing.expect(gop.found_existing == false);
    }
}

test "pop" {
    var map = AutoArrayMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    testing.expect((try map.fetchPut(1, 11)) == null);
    testing.expect((try map.fetchPut(2, 22)) == null);
    testing.expect((try map.fetchPut(3, 33)) == null);
    testing.expect((try map.fetchPut(4, 44)) == null);

    const pop1 = map.pop();
    testing.expect(pop1.key == 4 and pop1.value == 44);
    const pop2 = map.pop();
    testing.expect(pop2.key == 3 and pop2.value == 33);
    const pop3 = map.pop();
    testing.expect(pop3.key == 2 and pop3.value == 22);
    const pop4 = map.pop();
    testing.expect(pop4.key == 1 and pop4.value == 11);
}

test "items array map" {
    var reset_map = AutoArrayMap(i32, i32).init(std.testing.allocator);
    defer reset_map.deinit();

    // test ensureCapacity with a 0 parameter
    try reset_map.ensureCapacity(0);

    try reset_map.putNoClobber(0, 11);
    try reset_map.putNoClobber(1, 22);
    try reset_map.putNoClobber(2, 33);

    var keys = [_]i32{
        0, 2, 1,
    };

    var values = [_]i32{
        11, 33, 22,
    };

    var buffer = [_]i32{
        0, 0, 0,
    };

    const first_entry = reset_map.items()[0];

    var count: usize = 0;
    for (reset_map.items()) |entry| {
        buffer[@intCast(usize, entry.key)] = entry.value;
        count += 1;
    }
    testing.expect(count == 3);
    testing.expect(reset_map.count() == count);

    for (buffer) |v, i| {
        testing.expect(buffer[@intCast(usize, keys[i])] == values[i]);
    }

    count = 0;
    for (reset_map.items()) |entry| {
        buffer[@intCast(usize, entry.key)] = entry.value;
        count += 1;
        if (count >= 2) break;
    }

    for (buffer[0..2]) |v, i| {
        testing.expect(buffer[@intCast(usize, keys[i])] == values[i]);
    }

    var entry = reset_map.items()[0];
    testing.expect(entry.key == first_entry.key);
    testing.expect(entry.value == first_entry.value);
}

test "capacity" {
    var map = AutoArrayMap(i32, i32).init(std.testing.allocator);
    defer map.deinit();

    try map.put(1, 11);
    try map.put(2, 22);
    try map.put(3, 33);
    try map.put(4, 44);

    testing.expect(map.count() == 4);
    const capacity = map.capacity();
    testing.expect(capacity >= map.count());

    map.clearRetainingCapacity();

    testing.expect(map.count() == 0);
    testing.expect(map.capacity() == capacity);

    map.clearAndFree();
    testing.expect(map.capacity() == 0);
}
