import AppKit
import SwiftUI

// SetArt.swift also uses this initializer in the app's Theme.swift.
extension Color {
    init(hex: String) {
        guard let value = UInt64(hex, radix: 16) else {
            preconditionFailure("Invalid set artwork color: \(hex)")
        }
        self.init(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
    }
}

@main
struct SetEmblemRenderer {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "SetEmblemRenderer", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Expected an output directory."
            ])
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for set in 1...5 {
            let renderer = ImageRenderer(content: SetEmblem(set: set).frame(width: 512, height: 512))
            guard let image = renderer.cgImage else {
                throw NSError(domain: "SetEmblemRenderer", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Could not render set \(set)."
                ])
            }
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "SetEmblemRenderer", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode set \(set)."
                ])
            }
            try data.write(to: output.appendingPathComponent("set-\(set).png"))
        }
    }
}
