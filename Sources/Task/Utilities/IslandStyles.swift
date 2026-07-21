import SwiftUI

/// Boring Notch 风格的共享样式与修饰符。
enum IslandStyles {
    static let capsuleStroke = Color.white.opacity(0.10)
    static let dividerColor = Color.white.opacity(0.06)
    static let secondaryText = Color.white.opacity(0.45)
    static let tertiaryText = Color.white.opacity(0.30)

    static func titleFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static func bodyFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight)
    }
}

// MARK: - View Modifiers

struct IslandCapsuleBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                IslandMaterialBackground()
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(IslandStyles.capsuleStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(Constants.Island.Shadow.ambientOpacity),
                    radius: Constants.Island.Shadow.ambientRadius,
                    x: 0,
                    y: Constants.Island.Shadow.ambientYOffset)
            .shadow(color: Color.black.opacity(Constants.Island.Shadow.tightOpacity),
                    radius: Constants.Island.Shadow.tightRadius,
                    x: 0,
                    y: Constants.Island.Shadow.tightYOffset)
    }
}

extension View {
    func islandCapsuleBackground(cornerRadius: CGFloat) -> some View {
        modifier(IslandCapsuleBackground(cornerRadius: cornerRadius))
    }
}

// MARK: - Button Styles

struct IslandIconButtonStyle: ButtonStyle {
    var color: Color = IslandStyles.secondaryText
    var hoverColor: Color = Color.white
    var size: CGFloat = 18

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size, weight: .medium))
            .foregroundColor(configuration.isPressed ? hoverColor.opacity(0.7) : color)
            .frame(width: size + 12, height: size + 12)
            .contentShape(Rectangle())
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct IslandGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IslandStyles.titleFont(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.blue.opacity(configuration.isPressed ? 0.7 : 1.0))
            )
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Input Style

struct IslandGlassInput: View {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(IslandStyles.bodyFont(size: 14))
                        .foregroundColor(IslandStyles.secondaryText)
                }
                TextField("", text: $text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(IslandStyles.bodyFont(size: 14))
                    .foregroundColor(.white)
                    .onSubmit(onSubmit)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
