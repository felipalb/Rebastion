import SpriteKit
import UIKit

/// Procedurally generated textures shared by every scene node.
@MainActor
enum SceneTextures {
    /// Bright core with a soft halo. Tinted per ball / bullet with additive blending.
    static let glow: SKTexture = {
        let size = CGSize(width: 64, height: 64)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [
                UIColor.white.cgColor,
                UIColor.white.cgColor,
                UIColor.white.withAlphaComponent(0.45).cgColor,
                UIColor.white.withAlphaComponent(0).cgColor,
            ] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.22, 0.42, 1])!
            let center = CGPoint(x: 32, y: 32)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 32, options: [])
        }
        return SKTexture(image: image)
    }()

    /// Soft dot used for particles.
    static let spark: SKTexture = {
        let size = CGSize(width: 24, height: 24)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            let center = CGPoint(x: 12, y: 12)
            context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 12, options: [])
        }
        return SKTexture(image: image)
    }()

    /// Four-pointed star with a hot center, used for muzzle flashes and impact flares.
    static let flare: SKTexture = {
        let size = CGSize(width: 96, height: 96)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let center = CGPoint(x: 48, y: 48)
            let path = UIBezierPath()
            for i in 0..<8 {
                let angle = CGFloat(i) * .pi / 4 - .pi / 2
                let radius: CGFloat = i.isMultiple(of: 2) ? 47 : 7
                let p = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.close()
            UIColor.white.withAlphaComponent(0.9).setFill()
            path.fill()
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 22, options: [])
        }
        return SKTexture(image: image)
    }()

    static func background(size: CGSize, dangerLineY: CGFloat) -> SKTexture {
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            let colors = [Neon.arenaTop.cgColor, Neon.arenaBottom.cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            cg.setStrokeColor(UIColor.white.withAlphaComponent(0.045).cgColor)
            cg.setLineWidth(1)
            let spacing: CGFloat = 32
            var x: CGFloat = spacing / 2
            while x < size.width {
                cg.move(to: CGPoint(x: x, y: 0))
                cg.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = spacing / 2
            while y < size.height {
                cg.move(to: CGPoint(x: 0, y: y))
                cg.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            cg.strokePath()

            // Glow below the defense line.
            let dangerColors = [Neon.coral.withAlphaComponent(0).cgColor, Neon.coral.withAlphaComponent(0.16).cgColor] as CFArray
            let danger = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: dangerColors, locations: [0, 1])!
            cg.drawLinearGradient(danger, start: CGPoint(x: 0, y: dangerLineY - 60), end: CGPoint(x: 0, y: dangerLineY), options: [])

            cg.setStrokeColor(Neon.coral.withAlphaComponent(0.55).cgColor)
            cg.setLineWidth(2)
            cg.setLineDash(phase: 0, lengths: [10, 8])
            cg.move(to: CGPoint(x: 0, y: dangerLineY))
            cg.addLine(to: CGPoint(x: size.width, y: dangerLineY))
            cg.strokePath()
        }
        return SKTexture(image: image)
    }
}
