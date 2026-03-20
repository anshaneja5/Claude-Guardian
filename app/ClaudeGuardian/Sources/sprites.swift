// sprites.swift — High-quality 16x16 pixel art mascots
// Each mascot: 0=transparent, 1-9=palette colors per mascot
import SwiftUI

// Helper to make sprite variants
func shiftDown(_ s: [[Int]]) -> [[Int]] {
    var r = s; r.insert(Array(repeating: 0, count: s[0].count), at: 0); r.removeLast(); return r
}
func replacePixels(_ s: [[Int]], _ replacements: [(Int,Int,Int)]) -> [[Int]] {
    var r = s; for (row,col,val) in replacements { r[row][col] = val }; return r
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CAT — Pixel art cat head (from OpenGameArt "Cats" by peony, CC-BY 4.0)
// 0=transparent, 1=dark gray fur, 2=outline, 3=mid gray fur,
// 4=light pink, 5=medium pink, 6=orange(eye), 7=brown, 8=white(highlight), 9=light gray
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
struct CatSprites {
    static let idle1: [[Int]] = [
        [0,0,3,0,0,0,0,0,0,0,0,0,0,3,0,0],
        [0,0,5,3,0,0,0,0,0,0,0,0,3,5,0,0],
        [0,0,5,3,0,0,0,0,0,0,0,0,3,5,0,0],
        [0,4,5,5,3,0,0,0,0,0,0,3,5,5,4,0],
        [0,4,5,5,3,0,0,0,0,0,0,3,5,5,4,0],
        [0,3,5,3,3,3,0,0,0,0,3,3,3,5,3,0],
        [0,3,5,3,3,3,3,3,3,3,3,3,3,5,3,0],
        [0,3,3,3,3,3,3,3,3,3,3,3,3,3,3,0],
        [0,3,3,9,9,9,9,9,9,9,9,9,9,3,3,0],
        [3,3,9,6,6,9,9,9,9,9,9,6,6,9,3,3],
        [3,3,6,6,2,8,9,9,9,9,8,2,6,6,3,3],
        [3,3,6,6,2,6,9,9,9,9,6,2,6,6,3,3],
        [3,3,9,6,6,9,9,9,9,9,9,6,6,9,3,3],
        [0,3,3,9,9,9,9,2,2,9,9,9,9,3,3,0],
        [0,0,3,3,3,3,3,3,3,3,3,3,3,3,0,0],
        [0,0,0,3,3,3,3,3,3,3,3,3,3,0,0,0],
    ]

    static let idle2: [[Int]] = replacePixels(idle1, [
        (9,3,9),(9,4,9),(9,11,9),(9,12,9),
        (10,2,9),(10,3,2),(10,4,2),(10,5,2),
        (10,10,2),(10,11,2),(10,12,2),(10,13,9),
        (11,2,9),(11,3,9),(11,4,9),(11,5,9),
        (11,10,9),(11,11,9),(11,12,9),(11,13,9),
        (12,3,9),(12,4,9),(12,11,9),(12,12,9),
    ])

    static let idle3: [[Int]] = shiftDown(idle1)

    static let wave1: [[Int]] = replacePixels(idle1, [
        (0,13,0),
        (1,12,3),(1,13,0),(1,14,3),
        (2,12,3),(2,13,5),(2,14,3),
        (3,12,5),(3,13,5),(3,14,4),
    ])

    static let wave2: [[Int]] = replacePixels(idle1, [
        (0,2,0),
        (1,1,3),(1,2,0),(1,3,3),
        (2,1,3),(2,2,5),(2,3,3),
        (3,1,4),(3,2,5),(3,3,5),
    ])

    static let happy: [[Int]] = replacePixels(idle1, [
        (9,3,9),(9,4,9),(9,11,9),(9,12,9),
        (10,2,9),(10,3,6),(10,4,2),(10,5,9),
        (10,10,9),(10,11,2),(10,12,6),(10,13,9),
        (11,2,9),(11,3,9),(11,4,9),(11,5,9),
        (11,10,9),(11,11,9),(11,12,9),(11,13,9),
        (12,3,9),(12,4,9),(12,11,9),(12,12,9),
        (13,6,9),(13,7,2),(13,8,2),(13,9,9),
    ])

    static let sad1: [[Int]] = replacePixels(idle1, [
        (0,2,0),(0,13,0),
        (1,2,3),(1,13,3),
        (13,6,9),(13,7,2),(13,8,9),(13,9,2),
    ])

    static let sad2: [[Int]] = shiftDown(sad1)

    static func color(for v: Int) -> Color {
        switch v {
        case 1: return Color(red: 0.275, green: 0.275, blue: 0.294)
        case 2: return Color(red: 0.098, green: 0.098, blue: 0.11)
        case 3: return Color(red: 0.33, green: 0.33, blue: 0.353)
        case 4: return Color(red: 1.0, green: 0.769, blue: 0.737)
        case 5: return Color(red: 1.0, green: 0.733, blue: 0.682)
        case 6: return Color(red: 1.0, green: 0.667, blue: 0.247)
        case 7: return Color(red: 0.431, green: 0.337, blue: 0.235)
        case 8: return Color(red: 1.0, green: 1.0, blue: 1.0)
        case 9: return Color(red: 0.376, green: 0.376, blue: 0.392)
        default: return .clear
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// OWL — Round body, big yellow eyes, orange beak+feet, heart-shaped chest
// 0=transparent, 1=medium brown, 2=dark outline, 3=cream, 4=tan chest,
// 5=yellow eye, 6=pupil, 7=orange beak/feet, 8=dark brown wings, 9=light brown
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
struct OwlSprites {
    static let idle1: [[Int]] = [
        [0,0,0,0,0,0,0,8,2,0,0,0,0,0,0,0],
        [0,0,0,0,0,2,1,1,1,1,2,0,0,0,0,0],
        [0,0,0,0,2,1,9,1,1,9,1,2,0,0,0,0],
        [0,0,0,2,1,1,1,1,1,1,1,1,2,0,0,0],
        [0,0,2,1,2,2,2,1,1,2,2,2,1,2,0,0],
        [0,2,8,2,5,5,5,2,2,5,5,5,2,8,2,0],
        [0,2,8,2,5,6,5,1,1,5,6,5,2,8,2,0],
        [0,2,1,2,5,5,5,2,2,5,5,5,2,1,2,0],
        [0,0,2,1,2,2,1,7,7,1,2,2,1,2,0,0],
        [0,0,2,1,1,4,4,4,4,4,4,1,1,2,0,0],
        [0,2,8,1,4,4,4,4,4,4,4,4,1,8,2,0],
        [0,2,8,8,4,3,4,4,4,4,3,4,8,8,2,0],
        [0,0,2,8,1,4,4,4,4,4,4,1,8,2,0,0],
        [0,0,0,2,8,1,4,4,4,4,1,8,2,0,0,0],
        [0,0,0,0,2,7,7,2,2,7,7,2,0,0,0,0],
        [0,0,0,2,7,7,7,2,2,7,7,7,2,0,0,0],
    ]
    static let idle2: [[Int]] = replacePixels(idle1, [
        (5,4,2),(5,5,2),(5,6,2),(5,9,2),(5,10,2),(5,11,2),
        (6,4,1),(6,5,1),(6,6,1),(6,9,1),(6,10,1),(6,11,1),
        (7,4,5),(7,5,5),(7,6,5),(7,9,5),(7,10,5),(7,11,5),
    ])
    static let idle3: [[Int]] = shiftDown(idle1)
    static let wave1: [[Int]] = [
        [0,0,0,0,0,0,0,8,2,0,0,0,0,0,0,0],
        [0,0,0,0,0,2,1,1,1,1,2,0,0,0,0,0],
        [0,0,0,0,2,1,9,1,1,9,1,2,0,0,0,0],
        [0,0,0,2,1,1,1,1,1,1,1,1,2,0,0,0],
        [0,0,2,1,2,2,2,1,1,2,2,2,1,2,0,0],
        [0,2,8,2,5,5,5,2,2,5,5,5,2,8,2,0],
        [0,2,8,2,5,6,5,1,1,5,6,5,2,8,2,0],
        [0,2,1,2,5,5,5,2,2,5,5,5,2,1,2,0],
        [0,0,2,1,2,2,1,7,7,1,2,2,1,2,0,0],
        [0,0,2,1,1,4,4,4,4,4,4,1,1,2,2,0],
        [0,2,8,1,4,4,4,4,4,4,4,4,1,2,8,2],
        [0,2,8,8,4,3,4,4,4,4,3,4,8,2,8,2],
        [0,0,2,8,1,4,4,4,4,4,4,1,8,2,0,0],
        [0,0,0,2,8,1,4,4,4,4,1,8,2,0,0,0],
        [0,0,0,0,2,7,7,2,2,7,7,2,0,0,0,0],
        [0,0,0,2,7,7,7,2,2,7,7,7,2,0,0,0],
    ]
    static let wave2: [[Int]] = replacePixels(wave1, [
        (9,14,8),(9,15,2),
        (10,14,8),(10,15,2),
        (11,14,2),(11,15,0),
    ])
    static let happy: [[Int]] = replacePixels(idle1, [
        (5,4,2),(5,5,2),(5,6,2),(5,9,2),(5,10,2),(5,11,2),
        (6,4,5),(6,5,2),(6,6,5),(6,9,5),(6,10,2),(6,11,5),
        (7,4,1),(7,5,1),(7,6,1),(7,9,1),(7,10,1),(7,11,1),
        (8,6,3),(8,7,7),(8,8,3),(8,9,1),
    ])
    static let sad1: [[Int]] = replacePixels(idle1, [
        (4,4,1),(4,5,2),(4,10,2),(4,11,1),
        (8,6,2),(8,7,1),(8,8,2),
        (9,5,1),(9,6,2),(9,9,2),(9,10,1),
    ])
    static let sad2: [[Int]] = shiftDown(sad1)

    static func color(for v: Int) -> Color {
        switch v {
        case 1: return Color(red: 0.6, green: 0.4, blue: 0.2)
        case 2: return Color(red: 0.169, green: 0.102, blue: 0.055)
        case 3: return Color(red: 0.941, green: 0.894, blue: 0.804)
        case 4: return Color(red: 0.863, green: 0.765, blue: 0.608)
        case 5: return Color(red: 0.98, green: 0.843, blue: 0.216)
        case 6: return Color(red: 0.137, green: 0.098, blue: 0.059)
        case 7: return Color(red: 0.863, green: 0.431, blue: 0.137)
        case 8: return Color(red: 0.333, green: 0.196, blue: 0.098)
        case 9: return Color(red: 0.706, green: 0.51, blue: 0.294)
        default: return .clear
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// SKULL — Clean skull, big eye sockets, teeth
// 1=bone, 2=black, 3=highlight, 4=shadow bone, 5=eye socket, 6=green glow, 7=teeth, 8=dark
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
struct SkullSprites {
    static let idle1: [[Int]] = [
        [0,0,0,0,2,2,2,2,2,2,2,0,0,0,0,0],  // top
        [0,0,0,2,1,1,1,1,1,1,1,2,0,0,0,0],
        [0,0,2,1,1,1,1,1,1,1,1,1,2,0,0,0],
        [0,2,1,1,3,1,1,1,1,1,1,4,1,2,0,0],  // shading left=light right=dark
        [0,2,1,3,1,1,1,1,1,1,1,1,4,2,0,0],
        [2,1,3,1,2,2,2,1,2,2,2,1,4,1,2,0],  // eye socket outlines
        [2,1,3,1,2,5,2,1,2,5,2,1,4,1,2,0],  // eye sockets (with red glow)
        [2,1,1,1,2,2,2,1,2,2,2,1,1,4,2,0],  // below eyes
        [0,2,1,1,1,1,1,1,1,1,1,1,4,2,0,0],
        [0,2,1,1,1,1,2,2,1,1,1,1,4,2,0,0],  // nose hole
        [0,0,2,1,1,1,1,1,1,1,1,1,2,0,0,0],
        [0,0,2,7,2,7,2,7,2,7,2,7,2,0,0,0],  // teeth row
        [0,0,0,2,0,2,0,2,0,2,0,2,0,0,0,0],  // teeth gaps
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ]
    // Blink = eyes glow red
    static let idle2: [[Int]] = replacePixels(idle1, [
        (6,4,5),(6,5,5),(6,6,5),(6,8,5),(6,9,5),(6,10,5), // eyes filled (glow)
    ])
    static let idle3: [[Int]] = shiftDown(idle1)
    // Wave = crossbones appear
    static let wave1: [[Int]] = replacePixels(idle1, [
        (13,2,2),(13,3,1),(13,4,2),(13,11,2),(13,12,1),(13,13,2),
        (14,1,2),(14,5,2),(14,10,2),(14,14,2),
        (14,2,1),(14,3,2),(14,4,1),(14,11,1),(14,12,2),(14,13,1),
    ])
    static let wave2: [[Int]] = replacePixels(wave1, [
        (6,5,6),(6,9,6), // eyes glow green when waving
    ])
    // Happy = green glowing eyes
    static let happy: [[Int]] = replacePixels(idle1, [
        (6,4,6),(6,5,6),(6,6,6),(6,8,6),(6,9,6),(6,10,6),
    ])
    // Sad = dim eyes
    static let sad1: [[Int]] = replacePixels(idle1, [
        (6,4,8),(6,5,8),(6,6,8),(6,8,8),(6,9,8),(6,10,8),
        (11,3,1),(11,5,1),(11,7,1),(11,9,1),(11,11,1), // no teeth gaps (frown)
    ])
    static let sad2: [[Int]] = shiftDown(sad1)

    static func color(for v: Int) -> Color {
        switch v {
        case 1: return Color(red: 0.85, green: 0.82, blue: 0.75)  // bone
        case 2: return Color(red: 0.08, green: 0.08, blue: 0.08)  // black
        case 3: return Color(red: 0.95, green: 0.93, blue: 0.88)  // highlight
        case 4: return Color(red: 0.7, green: 0.67, blue: 0.6)    // shadow
        case 5: return Color(red: 0.8, green: 0.12, blue: 0.1)    // red glow
        case 6: return Color(red: 0.2, green: 0.9, blue: 0.35)    // green glow
        case 7: return Color(red: 0.92, green: 0.9, blue: 0.85)   // teeth
        case 8: return Color(red: 0.3, green: 0.28, blue: 0.25)   // dim
        default: return .clear
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DOG — Cute front-facing puppy with floppy ears, big eyes, tan belly
// 0=transparent, 1=medium brown fur, 2=dark outline, 3=white/cream highlight,
// 4=tongue pink, 5=eye black, 6=nose, 7=dark brown ears, 8=tan belly, 9=light brown
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
struct DogSprites {
    static let idle1: [[Int]] = [
        [0,0,0,0,0,2,2,2,2,2,2,0,0,0,0,0],
        [0,0,0,0,2,1,1,1,1,1,1,2,0,0,0,0],
        [0,0,0,2,1,9,1,1,1,1,9,1,2,0,0,0],
        [0,2,7,2,1,1,1,1,1,1,1,1,2,7,2,0],
        [2,7,7,2,3,5,5,1,1,5,5,3,2,7,7,2],
        [2,7,7,2,3,5,3,1,1,3,5,3,2,7,7,2],
        [2,7,7,1,1,1,1,6,6,1,1,1,1,7,7,2],
        [0,2,7,1,1,1,2,3,2,1,1,1,7,2,0,0],
        [0,0,2,1,1,1,1,1,1,1,1,1,2,0,0,0],
        [0,0,2,1,8,8,8,8,8,8,8,8,1,2,0,0],
        [0,0,2,1,8,8,8,8,8,8,8,8,1,2,0,0],
        [0,0,2,1,1,8,3,8,8,3,8,1,1,2,0,0],
        [0,0,2,1,1,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,2,2,1,1,2,0,2,1,1,2,2,0,0,0],
        [0,0,2,1,1,1,2,0,2,1,1,1,2,0,0,0],
        [0,0,2,2,2,2,2,0,2,2,2,2,2,0,0,0],
    ]
    static let idle2: [[Int]] = replacePixels(idle1, [
        (4,4,1),(4,5,2),(4,6,2),(4,9,2),(4,10,2),(4,11,1),
        (5,4,1),(5,5,3),(5,6,1),(5,9,1),(5,10,3),(5,11,1),
    ])
    static let idle3: [[Int]] = shiftDown(idle1)
    static let wave1: [[Int]] = [
        [0,0,0,0,0,2,2,2,2,2,2,0,0,0,0,0],
        [0,0,0,0,2,1,1,1,1,1,1,2,0,0,0,0],
        [0,0,0,2,1,9,1,1,1,1,9,1,2,0,0,0],
        [0,2,7,2,1,1,1,1,1,1,1,1,2,7,2,0],
        [2,7,7,2,3,5,5,1,1,5,5,3,2,7,7,2],
        [2,7,7,2,3,5,3,1,1,3,5,3,2,7,7,2],
        [2,7,7,1,1,1,1,6,6,1,1,1,1,7,7,2],
        [0,2,7,1,1,1,2,3,2,1,1,1,7,2,0,0],
        [0,0,2,1,1,1,1,4,4,1,1,1,2,0,0,0],
        [0,0,2,1,8,8,8,4,8,8,8,8,1,2,0,0],
        [0,0,2,1,8,8,8,8,8,8,8,8,1,2,2,0],
        [0,0,2,1,1,8,3,8,8,3,8,1,2,1,1,2],
        [0,0,2,1,1,1,1,1,1,1,1,1,2,2,2,0],
        [0,0,2,2,1,1,2,0,2,1,1,2,2,0,0,0],
        [0,0,2,1,1,1,2,0,2,1,1,1,2,0,0,0],
        [0,0,2,2,2,2,2,0,2,2,2,2,2,0,0,0],
    ]
    static let wave2: [[Int]] = replacePixels(wave1, [
        (10,14,1),(10,15,2),
        (11,13,2),(11,14,1),(11,15,2),
        (12,13,0),(12,14,2),(12,15,0),
    ])
    static let happy: [[Int]] = replacePixels(idle1, [
        (4,4,1),(4,5,3),(4,6,3),(4,9,3),(4,10,3),(4,11,1),
        (5,4,1),(5,5,5),(5,6,2),(5,9,2),(5,10,5),(5,11,1),
        (7,6,3),(7,7,3),(7,8,3),
        (8,6,4),(8,7,4),(8,8,4),
    ])
    static let sad1: [[Int]] = replacePixels(idle1, [
        (7,6,2),(7,7,1),(7,8,2),
        (8,5,2),(8,6,1),(8,7,1),(8,8,1),(8,9,2),
    ])
    static let sad2: [[Int]] = shiftDown(sad1)

    static func color(for v: Int) -> Color {
        switch v {
        case 1: return Color(red: 0.706, green: 0.471, blue: 0.235)
        case 2: return Color(red: 0.157, green: 0.098, blue: 0.047)
        case 3: return Color(red: 0.961, green: 0.933, blue: 0.882)
        case 4: return Color(red: 0.941, green: 0.431, blue: 0.471)
        case 5: return Color(red: 0.118, green: 0.086, blue: 0.059)
        case 6: return Color(red: 0.137, green: 0.110, blue: 0.086)
        case 7: return Color(red: 0.431, green: 0.275, blue: 0.137)
        case 8: return Color(red: 0.902, green: 0.824, blue: 0.686)
        case 9: return Color(red: 0.784, green: 0.588, blue: 0.333)
        default: return .clear
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// DRAGON — Cute chibi dragon with horns and wings
// 1=green, 2=black, 3=white, 4=belly yellow, 5=eye red, 6=fire orange, 7=wing membrane, 8=dark green
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
struct DragonSprites {
    static let idle1: [[Int]] = [
        [0,0,0,0,3,2,0,0,0,0,2,3,0,0,0,0],  // horns
        [0,0,0,2,1,3,2,0,0,2,3,1,2,0,0,0],  // horns base
        [0,0,0,2,1,1,1,2,2,1,1,1,2,0,0,0],  // top head
        [0,0,2,1,1,1,1,1,1,1,1,1,1,2,0,0],
        [0,2,1,1,3,5,5,1,1,5,5,3,1,1,2,0],  // eyes
        [0,2,1,1,3,5,3,1,1,3,5,3,1,1,2,0],
        [0,2,1,1,1,1,1,1,1,1,1,1,1,1,2,0],
        [0,0,2,1,1,2,2,1,1,2,2,1,1,2,0,0],  // nostrils
        [0,0,2,1,1,1,4,3,4,1,1,1,2,0,0,0],  // mouth/chin
        [0,0,2,8,4,4,4,4,4,4,4,4,8,2,0,0],  // chest
        [0,2,7,8,1,4,4,4,4,4,4,1,8,7,2,0],  // wings tucked + body
        [0,2,7,8,1,1,4,4,4,4,1,1,8,7,2,0],  // wings
        [0,0,2,1,1,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,2,2,1,1,2,0,2,1,1,2,2,0,0,0],  // legs
        [0,0,2,1,1,1,2,0,2,1,1,1,2,0,0,0],  // feet
        [0,0,2,2,2,2,0,0,0,2,2,2,2,0,0,0],
    ]
    static let idle2: [[Int]] = replacePixels(idle1, [
        (4,4,1),(4,5,2),(4,6,2),(4,10,2),(4,11,2),(4,12,1),
        (5,4,1),(5,5,1),(5,10,1),(5,11,1),
    ])
    static let idle3: [[Int]] = shiftDown(idle1)
    // Wave: wings spread
    static let wave1: [[Int]] = [
        [0,0,0,0,3,2,0,0,0,0,2,3,0,0,0,0],
        [0,0,0,2,1,3,2,0,0,2,3,1,2,0,0,0],
        [0,0,0,2,1,1,1,2,2,1,1,1,2,0,0,0],
        [0,0,2,1,1,1,1,1,1,1,1,1,1,2,0,0],
        [0,2,1,1,3,5,5,1,1,5,5,3,1,1,2,0],
        [0,2,1,1,3,5,3,1,1,3,5,3,1,1,2,0],
        [0,2,1,1,1,1,1,1,1,1,1,1,1,1,2,0],
        [0,0,2,1,1,2,2,1,1,2,2,1,1,2,0,0],
        [0,0,2,1,1,1,4,3,4,1,1,1,2,0,0,0],
        [2,7,2,8,4,4,4,4,4,4,4,4,8,2,7,2],  // wings OUT!
        [2,7,7,8,1,4,4,4,4,4,4,1,8,7,7,2],
        [0,2,7,8,1,1,4,4,4,4,1,1,8,7,2,0],
        [0,0,2,1,1,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,2,2,1,1,2,0,2,1,1,2,2,0,0,0],
        [0,0,2,1,1,1,2,0,2,1,1,1,2,0,0,0],
        [0,0,2,2,2,2,0,0,0,2,2,2,2,0,0,0],
    ]
    static let wave2: [[Int]] = replacePixels(wave1, [
        (9,0,0),(9,1,2),(9,14,2),(9,15,0),  // wings slightly different angle
        (10,0,2),(10,1,7),(10,14,7),(10,15,2),
    ])
    // Happy: fire breath!
    static let happy: [[Int]] = replacePixels(idle1, [
        (4,4,1),(4,5,2),(4,6,2),(4,10,2),(4,11,2),(4,12,1), // squint
        (5,4,1),(5,5,5),(5,6,2),(5,10,2),(5,11,5),(5,12,1),
        (7,4,1),(7,5,3),(7,10,3),(7,11,1), // smile
        (8,13,6),(8,14,6),(8,15,6), // fire!
        (7,13,6),(7,14,6),
        (6,14,6),(6,15,6),
    ])
    // Sad: wings drooped
    static let sad1: [[Int]] = replacePixels(idle1, [
        (7,5,1),(7,6,2),(7,9,2),(7,10,1), // frown
        (8,5,2),(8,6,1),(8,8,1),(8,9,2),
        (12,0,7),(12,1,2),(12,14,2),(12,15,7), // wings droop down
        (13,0,2),(13,1,7),(13,14,7),(13,15,2),
    ])
    static let sad2: [[Int]] = shiftDown(sad1)

    static func color(for v: Int) -> Color {
        switch v {
        case 1: return Color(red: 0.25, green: 0.7, blue: 0.4)    // green
        case 2: return Color(red: 0.08, green: 0.15, blue: 0.08)  // dark outline
        case 3: return Color(red: 0.92, green: 0.95, blue: 0.9)   // white/horn
        case 4: return Color(red: 0.95, green: 0.88, blue: 0.4)   // belly yellow
        case 5: return Color(red: 0.85, green: 0.15, blue: 0.12)  // red eye
        case 6: return Color(red: 1.0, green: 0.55, blue: 0.1)    // fire orange
        case 7: return Color(red: 0.35, green: 0.55, blue: 0.35)  // wing membrane
        case 8: return Color(red: 0.18, green: 0.5, blue: 0.28)   // dark green
        default: return .clear
        }
    }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// CLAUDE — Improved original mascot
// 1=coral, 2=outline, 3=white, 4=blush, 5=eye, 6=green, 7=dark coral, 8=light coral
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
struct ClaudeSprites {
    static let idle1: [[Int]] = [
        [0,0,0,0,0,2,2,2,2,2,2,0,0,0,0,0],
        [0,0,0,2,2,1,1,1,1,1,1,2,2,0,0,0],
        [0,0,2,1,8,8,1,1,1,1,8,8,1,2,0,0],
        [0,2,1,8,1,1,1,1,1,1,1,1,8,1,2,0],
        [0,2,1,1,1,1,1,1,1,1,1,1,1,1,2,0],
        [0,2,1,3,5,5,1,1,1,1,5,5,3,1,2,0],  // eyes
        [0,2,1,3,5,3,1,1,1,1,3,5,3,1,2,0],  // eye highlights
        [0,2,1,1,1,1,1,1,1,1,1,1,1,1,2,0],
        [0,2,1,4,1,1,1,3,3,1,1,1,4,1,2,0],  // cheeks + smile
        [0,0,2,1,1,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,2,7,1,1,1,1,1,1,1,1,7,2,0,0],  // neck/body
        [0,0,2,1,1,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,2,1,2,1,1,1,1,1,1,2,1,2,0,0],  // arms
        [0,0,0,2,2,1,1,1,1,1,1,2,2,0,0,0],
        [0,0,0,0,2,1,1,2,2,1,1,2,0,0,0,0],  // legs
        [0,0,0,0,2,2,2,2,2,2,2,2,0,0,0,0],
    ]
    static let idle2: [[Int]] = replacePixels(idle1, [
        (5,3,1),(5,4,2),(5,5,2),(5,10,2),(5,11,2),(5,12,1),
        (6,3,1),(6,4,1),(6,5,1),(6,10,1),(6,11,1),(6,12,1),
    ])
    static let idle3: [[Int]] = shiftDown(idle1)
    static let wave1: [[Int]] = [
        [0,0,0,0,0,2,2,2,2,2,2,0,0,0,0,0],
        [0,0,0,2,2,1,1,1,1,1,1,2,2,0,0,0],
        [0,0,2,1,8,8,1,1,1,1,8,8,1,2,0,0],
        [0,2,1,8,1,1,1,1,1,1,1,1,8,1,2,0],
        [0,2,1,1,1,1,1,1,1,1,1,1,1,1,2,0],
        [0,2,1,3,5,5,1,1,1,1,5,5,3,1,2,0],
        [0,2,1,3,5,3,1,1,1,1,3,5,3,1,2,0],
        [0,2,1,1,1,1,1,1,1,1,1,1,1,1,2,0],
        [0,2,1,4,1,1,1,3,3,1,1,1,4,1,2,0],
        [0,0,2,1,1,1,1,1,1,1,1,1,1,2,0,0],
        [0,0,2,7,1,1,1,1,1,1,1,1,7,2,2,0],
        [0,0,2,1,1,1,1,1,1,1,1,1,2,1,1,2],  // arm waving right
        [0,0,2,1,2,1,1,1,1,1,1,2,0,2,1,2],
        [0,0,0,2,2,1,1,1,1,1,1,2,0,0,2,0],
        [0,0,0,0,2,1,1,2,2,1,1,2,0,0,0,0],
        [0,0,0,0,2,2,2,2,2,2,2,2,0,0,0,0],
    ]
    static let wave2: [[Int]] = replacePixels(wave1, [
        (10,14,1),(10,15,2),  // hand higher
        (11,13,2),(11,14,1),(11,15,2),
        (12,13,0),(12,14,2),(12,15,0),
    ])
    static let happy: [[Int]] = replacePixels(idle1, [
        (5,3,1),(5,4,3),(5,5,3),(5,10,3),(5,11,3),(5,12,1),
        (6,3,1),(6,4,5),(6,5,2),(6,10,2),(6,11,5),(6,12,1),
        (8,6,3),(8,7,3),(8,8,3),(8,9,3),  // big smile
    ])
    static let sad1: [[Int]] = replacePixels(idle1, [
        (8,6,2),(8,7,1),(8,8,1),(8,9,2),  // frown
        (7,5,2),(7,10,2),                  // eyebrows
        (12,0,1),(12,1,2),(12,14,2),(12,15,1), // arms droop
        (13,0,2),(13,15,2),
    ])
    static let sad2: [[Int]] = shiftDown(sad1)

    static func color(for v: Int) -> Color {
        switch v {
        case 1: return Color(red: 0.93, green: 0.5, blue: 0.35)   // coral
        case 2: return Color(red: 0.2, green: 0.15, blue: 0.13)   // outline
        case 3: return Color(red: 1.0, green: 0.97, blue: 0.95)   // white
        case 4: return Color(red: 1.0, green: 0.65, blue: 0.6)    // blush
        case 5: return Color(red: 0.12, green: 0.1, blue: 0.1)    // eye
        case 6: return Color(red: 0.3, green: 0.85, blue: 0.4)    // green
        case 7: return Color(red: 0.75, green: 0.38, blue: 0.25)  // dark coral
        case 8: return Color(red: 1.0, green: 0.6, blue: 0.45)    // light coral
        default: return .clear
        }
    }
}
