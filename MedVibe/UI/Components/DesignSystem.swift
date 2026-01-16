import SwiftUI

/// Design system for MedVibe app
/// Provides consistent colors, typography, spacing, and components
struct DesignSystem {
    
    // MARK: - Colors
    
    struct Colors {
        // Primary brand color - medical blue/teal
        static let primary = Color(red: 0.2, green: 0.6, blue: 0.8)
        static let primaryDark = Color(red: 0.15, green: 0.5, blue: 0.7)
        static let primaryLight = Color(red: 0.3, green: 0.7, blue: 0.9)
        
        // Accent colors
        static let accent = Color(red: 0.4, green: 0.7, blue: 0.5)
        static let accentDark = Color(red: 0.3, green: 0.6, blue: 0.4)
        
        // Status colors
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        
        // Background colors
        static let background = Color(.systemBackground)
        static let secondaryBackground = Color(.secondarySystemBackground)
        static let tertiaryBackground = Color(.tertiarySystemBackground)
        
        // Text colors
        static let textPrimary = Color(.label)
        static let textSecondary = Color(.secondaryLabel)
        static let textTertiary = Color(.tertiaryLabel)
        
        // Card/Container
        static let cardBackground = Color(.secondarySystemBackground)
        static let cardBorder = Color(.separator).opacity(0.3)
    }
    
    // MARK: - Typography
    
    struct Typography {
        static let largeTitle = Font.system(.largeTitle, design: .rounded, weight: .bold)
        static let title = Font.system(.title, design: .rounded, weight: .semibold)
        static let title2 = Font.system(.title2, design: .rounded, weight: .semibold)
        static let title3 = Font.system(.title3, design: .rounded, weight: .semibold)
        static let headline = Font.system(.headline, design: .rounded, weight: .semibold)
        static let body = Font.system(.body, design: .rounded, weight: .regular)
        static let bodyBold = Font.system(.body, design: .rounded, weight: .semibold)
        static let callout = Font.system(.callout, design: .rounded, weight: .regular)
        static let subheadline = Font.system(.subheadline, design: .rounded, weight: .regular)
        static let footnote = Font.system(.footnote, design: .rounded, weight: .regular)
        static let caption = Font.system(.caption, design: .rounded, weight: .regular)
        static let caption2 = Font.system(.caption2, design: .rounded, weight: .regular)
    }
    
    // MARK: - Spacing
    
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 24
        static let xxxl: CGFloat = 32
    }
    
    // MARK: - Corner Radius
    
    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 20
    }
    
    // MARK: - Shadows
    
    struct Shadow {
        static let small = ShadowStyle(
            color: Color.black.opacity(0.1),
            radius: 4,
            x: 0,
            y: 2
        )
        static let medium = ShadowStyle(
            color: Color.black.opacity(0.15),
            radius: 8,
            x: 0,
            y: 4
        )
        static let large = ShadowStyle(
            color: Color.black.opacity(0.2),
            radius: 12,
            x: 0,
            y: 6
        )
    }
}

struct ShadowStyle {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

// MARK: - View Modifiers

extension View {
    func cardStyle() -> some View {
        self
            .background(DesignSystem.Colors.cardBackground)
            .cornerRadius(DesignSystem.CornerRadius.medium)
            .shadow(
                color: DesignSystem.Shadow.small.color,
                radius: DesignSystem.Shadow.small.radius,
                x: DesignSystem.Shadow.small.x,
                y: DesignSystem.Shadow.small.y
            )
    }
    
    func primaryButtonStyle() -> some View {
        self
            .font(DesignSystem.Typography.headline)
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.primary)
            .cornerRadius(DesignSystem.CornerRadius.medium)
    }
    
    func secondaryButtonStyle() -> some View {
        self
            .font(DesignSystem.Typography.headline)
            .foregroundColor(DesignSystem.Colors.primary)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.primary.opacity(0.1))
            .cornerRadius(DesignSystem.CornerRadius.medium)
    }
}
