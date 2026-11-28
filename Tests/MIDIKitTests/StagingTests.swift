import Foundation
import Testing
@testable import MIDIKit

private func clip(_ path: String, _ text: String) -> (info: BuiltClip, data: Data) {
    let data = Data(text.utf8)
    return (BuiltClip(path: path, section: "a", clip: nil, bar: 1, bars: 1, sha256: sha256(data)), data)
}

private func withFolder(_ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("staging-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: folder) }
    try body(folder)
}

private func exists(_ folder: URL, _ path: String) -> Bool {
    FileManager.default.fileExists(atPath: folder.appendingPathComponent(path).path)
}

@Test func replacesOnlyItsOwnUnchangedFiles() throws {
    try withFolder { folder in
        _ = try Staging.write([clip("a/01 x.mid", "1"), clip("b.mid", "2")], source: "s", to: folder)
        #expect(throws: LayoutError.self) { try Staging.write([clip("b.mid", "3")], source: "s", to: folder) }
        try Data("mine".utf8).write(to: folder.appendingPathComponent("notes.txt"))
        _ = try Staging.write([clip("b.mid", "3")], source: "s", to: folder, replace: true)
        #expect(!exists(folder, "a"))
        #expect(exists(folder, "notes.txt"))

        try Data("edited".utf8).write(to: folder.appendingPathComponent("b.mid"))
        #expect(throws: LayoutError.self) {
            try Staging.write([clip("c.mid", "4")], source: "s", to: folder, replace: true)
        }
        #expect(!exists(folder, "c.mid"))
    }
}

@Test func refusesAFolderItDidNotMake() throws {
    try withFolder { folder in
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appendingPathComponent("other.mid"))
        for replace in [false, true] {
            #expect(throws: LayoutError.self) {
                try Staging.write([clip("b.mid", "1")], source: "s", to: folder, replace: replace)
            }
        }
    }
}

@Test(arguments: ["../x.mid", "/tmp/x.mid", "keep.txt"])
func refusesUnsafeManifestPaths(path: String) throws {
    try withFolder { folder in
        _ = try Staging.write([clip("b.mid", "1")], source: "s", to: folder)
        let manifest = Staging.Manifest(source: "s", files: [clip(path, "1").info])
        try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent(Staging.manifestName))
        #expect(throws: LayoutError.self) {
            try Staging.write([clip("b.mid", "1")], source: "s", to: folder, replace: true)
        }
    }
}
