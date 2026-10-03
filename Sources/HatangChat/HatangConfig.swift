#if os(iOS)
import HatangChatCore
import SwiftUI

/// How purchases started from chat cards are handled.
///
/// By default "Buy" on a product card writes "I'd like to buy …" in the composer, and a payment card shows
/// a VietQR code and a "Pay" button that opens the web checkout: right for physical goods and real-world
/// services. The App Store requires in-app purchase for digital goods used inside the app; for such apps
/// handle the purchase in `onBuyProduct` (see `ProductCardItem.appStoreProductId`) and set
/// `showExternalCheckout` to false.
public struct HatangCommerce {
    /// "Buy" on a product card. Return true when handled; false falls back to prefilling the composer.
    public var onBuyProduct: (@MainActor (ProductCardItem) -> Bool)?
    /// "Pay" on a payment card. Return true when handled; false falls back to the web checkout.
    public var onPay: (@MainActor (PaymentCard) -> Bool)?
    /// Show the VietQR code and open the web checkout from payment cards.
    public var showExternalCheckout: Bool

    public init(
        onBuyProduct: (@MainActor (ProductCardItem) -> Bool)? = nil,
        onPay: (@MainActor (PaymentCard) -> Bool)? = nil,
        showExternalCheckout: Bool = true
    ) {
        self.onBuyProduct = onBuyProduct
        self.onPay = onPay
        self.showExternalCheckout = showExternalCheckout
    }

    /// External checkout on, no hooks.
    public static var standard: HatangCommerce { HatangCommerce() }
}

extension HatangChat {
    /// Look of the chat views: light/dark choice, theme overrides and wording.
    public struct Appearance: Sendable, Hashable {
        /// How light or dark is chosen.
        public var themeMode: HatangChatThemeMode
        /// Light theme override (default: from the site's brand colour).
        public var theme: HatangChatTheme?
        /// Dark theme override (default: from the site's brand colour).
        public var darkTheme: HatangChatTheme?
        /// Wording overrides per locale, e.g. `[.vi: customVi]`.
        public var strings: [HatangLocale: HatangChatStrings]?

        public init(
            themeMode: HatangChatThemeMode = .site,
            theme: HatangChatTheme? = nil,
            darkTheme: HatangChatTheme? = nil,
            strings: [HatangLocale: HatangChatStrings]? = nil
        ) {
            self.themeMode = themeMode
            self.theme = theme
            self.darkTheme = darkTheme
            self.strings = strings
        }

        /// Strings for `locale`: the override, else the built-in ones.
        public func strings(for locale: HatangLocale) -> HatangChatStrings {
            strings?[locale] ?? .forLocale(locale)
        }

        /// The theme for `site` given the system's colour scheme.
        public func theme(for site: SiteConfig?, systemScheme: ColorScheme) -> HatangChatTheme {
            let dark = isChatDark(site: site, mode: themeMode, scheme: systemScheme)
            return (dark ? darkTheme : theme) ?? .fromSite(site, dark: dark)
        }

        func scope(for state: ChatState, systemScheme: ColorScheme) -> ChatScope {
            ChatScope(theme: theme(for: state.config, systemScheme: systemScheme), locale: state.locale, strings: strings(for: state.locale))
        }
    }
}
#endif
