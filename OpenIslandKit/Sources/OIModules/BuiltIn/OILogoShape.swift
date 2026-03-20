package import SwiftUI

// MARK: - OILogoIcon

/// Canvas-drawn OI logo icon — a circle ring containing stylized 'O' (ring) and 'I' (bar) initials.
package struct OILogoIcon: View {
    // MARK: Lifecycle

    package init(size: CGFloat, color: Color) {
        self.size = size
        self.color = color
    }

    // MARK: Package

    package var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            // Outer ring
            let ringInset = side * 0.06
            let outerRect = CGRect(
                x: center.x - side / 2 + ringInset,
                y: center.y - side / 2 + ringInset,
                width: side - ringInset * 2,
                height: side - ringInset * 2,
            )
            let ringPath = Path(ellipseIn: outerRect)
            context.stroke(
                ringPath,
                with: .color(self.color),
                lineWidth: max(side * 0.07, 0.75),
            )

            // "O" — small circle on the left
            let letterY = center.y
            let oRadius = side * 0.14
            let oCenter = CGPoint(x: center.x - side * 0.13, y: letterY)
            let oRect = CGRect(
                x: oCenter.x - oRadius,
                y: oCenter.y - oRadius,
                width: oRadius * 2,
                height: oRadius * 2,
            )
            let oPath = Path(ellipseIn: oRect)
            context.stroke(
                oPath,
                with: .color(self.color),
                lineWidth: max(side * 0.07, 0.75),
            )

            // "I" — vertical bar on the right
            let iX = center.x + side * 0.16
            let iHalfHeight = side * 0.18
            let iWidth = max(side * 0.08, 0.75)
            let iRect = CGRect(
                x: iX - iWidth / 2,
                y: letterY - iHalfHeight,
                width: iWidth,
                height: iHalfHeight * 2,
            )
            let iPath = Path(roundedRect: iRect, cornerRadius: iWidth / 2)
            context.fill(iPath, with: .color(self.color))
        }
        .frame(width: self.size, height: self.size)
    }

    // MARK: Private

    private let size: CGFloat
    private let color: Color
}

// MARK: - Preview

#Preview("OILogoIcon") {
    let teal = Color(red: 0.078, green: 0.722, blue: 0.651)

    HStack(spacing: 16) {
        ForEach([12, 16, 20] as [CGFloat], id: \.self) { size in
            VStack(spacing: 4) {
                OILogoIcon(size: size, color: teal)
                Text("\(Int(size))pt")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding(20)
    .background(.black)
}
