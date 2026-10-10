import SwiftUI

extension Font {
    /// Inter, bundled in Shared/Fonts (SIL Open Font License). Registered through ATSApplicationFontsPath.
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let face = switch weight {
        case .ultraLight, .thin, .light: "Inter-Light"
        case .medium: "Inter-Medium"
        case .semibold, .bold, .heavy, .black: "Inter-SemiBold"
        default: "Inter-Regular"
        }
        return .custom(face, size: size)
    }
}
