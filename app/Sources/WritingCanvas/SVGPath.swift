import CoreGraphics
import SwiftUI

/// A resolved (absolute-coordinate) SVG path command. KanjiVG uses only these.
public enum SVGCommand: Equatable {
    case move(CGPoint)
    case line(CGPoint)
    case cubic(CGPoint, CGPoint, CGPoint)  // control1, control2, end
    case close
}

/// Parses KanjiVG path `d` strings into drawable geometry.
/// Supports M/m, L/l, C/c, S/s, Z/z; unsupported commands (A/Q/T/H/V) are skipped.
public enum SVGPath {
    public static func parse(_ d: String) -> [SVGCommand] {
        let chars = Array(d)
        var i = 0
        var commands: [SVGCommand] = []
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var lastControl: CGPoint?
        var cmd: Character = " "

        func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," ||
                    chars[i] == "\n" || chars[i] == "\t" || chars[i] == "\r" { i += 1 }
        }
        func readNumber() -> CGFloat? {
            skipSeparators()
            var s = ""
            if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
            while i < chars.count, chars[i].isNumber { s.append(chars[i]); i += 1 }
            if i < chars.count, chars[i] == "." {
                s.append(chars[i]); i += 1
                while i < chars.count, chars[i].isNumber { s.append(chars[i]); i += 1 }
            }
            if i < chars.count, chars[i] == "e" || chars[i] == "E" {
                s.append(chars[i]); i += 1
                if i < chars.count, chars[i] == "+" || chars[i] == "-" { s.append(chars[i]); i += 1 }
                while i < chars.count, chars[i].isNumber { s.append(chars[i]); i += 1 }
            }
            return Double(s).map { CGFloat($0) }
        }
        func readPoint(relative: Bool) -> CGPoint? {
            guard let x = readNumber(), let y = readNumber() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while i < chars.count {
            skipSeparators()
            if i >= chars.count { break }
            if chars[i].isLetter {
                cmd = chars[i]
                i += 1
            } else {
                // Implicit repeat of the previous command; a repeated move becomes a line.
                if cmd == "M" { cmd = "L" } else if cmd == "m" { cmd = "l" }
            }
            switch cmd {
            case "M", "m":
                guard let p = readPoint(relative: cmd == "m") else { return commands }
                current = p; subpathStart = p; lastControl = nil
                commands.append(.move(p))
            case "L", "l":
                guard let p = readPoint(relative: cmd == "l") else { return commands }
                current = p; lastControl = nil
                commands.append(.line(p))
            case "C", "c":
                let rel = cmd == "c"
                guard let c1 = readPoint(relative: rel),
                      let c2 = readPoint(relative: rel),
                      let end = readPoint(relative: rel) else { return commands }
                commands.append(.cubic(c1, c2, end)); lastControl = c2; current = end
            case "S", "s":
                let rel = cmd == "s"
                guard let c2 = readPoint(relative: rel),
                      let end = readPoint(relative: rel) else { return commands }
                let c1: CGPoint
                if let lc = lastControl {
                    c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    c1 = current
                }
                commands.append(.cubic(c1, c2, end)); lastControl = c2; current = end
            case "Z", "z":
                commands.append(.close); current = subpathStart; lastControl = nil
            default:
                // Unsupported command: skip its operands up to the next command letter.
                lastControl = nil
                while i < chars.count, !chars[i].isLetter { i += 1 }
            }
        }
        return commands
    }

    public static func path(from commands: [SVGCommand]) -> Path {
        var path = Path()
        for command in commands {
            switch command {
            case let .move(p): path.move(to: p)
            case let .line(p): path.addLine(to: p)
            case let .cubic(c1, c2, end): path.addCurve(to: end, control1: c1, control2: c2)
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
