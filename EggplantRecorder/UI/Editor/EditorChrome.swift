import AppKit
import SwiftUI

enum EditorChrome {
    static let window = Color(red: 245 / 255, green: 245 / 255, blue: 247 / 255) // #f5f5f7
    static let rail = Color.white
    static let play = Color(red: 229 / 255, green: 229 / 255, blue: 234 / 255) // #e5e5ea
    static let field = Color.white
    static let fieldStroke = Color(red: 199 / 255, green: 199 / 255, blue: 204 / 255) // #c7c7cc
    static let export = Color(red: 0, green: 122 / 255, blue: 1) // #007aff
    static let secondaryButton = Color(red: 232 / 255, green: 232 / 255, blue: 237 / 255) // #e8e8ed
    static let text = Color(red: 29 / 255, green: 29 / 255, blue: 31 / 255) // #1d1d1f
    static let label = Color(red: 58 / 255, green: 58 / 255, blue: 60 / 255) // #3a3a3c
    static let muted = Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255) // #6e6e73
    static let track = Color(red: 210 / 255, green: 210 / 255, blue: 215 / 255) // #d2d2d7
    static let trim = Color(red: 0, green: 122 / 255, blue: 1)
    static let divider = Color.black.opacity(0.14)

    static let nsWindow = NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 247 / 255, alpha: 1)
    static let railWidth: CGFloat = 288
}
