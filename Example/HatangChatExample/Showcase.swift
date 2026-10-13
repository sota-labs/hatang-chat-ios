#if DEBUG
import HatangChat
import SwiftUI

/// DEBUG-only "showcase" home used to film marketing footage: a small tea shop ("Mộc Hương Tea", fictional)
/// with a product grid and the chat launcher, instead of the developer screen. Turn it on with the launch
/// argument `-showcase YES`; `-showcaseImages <base URL>` points at the product photos (default
/// `http://localhost:8099`). The shopper is identified from `-showcaseUserId`, `-showcaseHash`,
/// `-showcaseName` and `-showcaseEmail` (see `Demo.identify`).
enum Showcase {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "showcase") }
    static var imageBase: String { UserDefaults.standard.string(forKey: "showcaseImages") ?? "http://localhost:8099" }

    struct Product: Identifiable {
        let id: String
        let name: String
        let price: Int
        let compareAt: Int?
        let image: String
    }

    static let products: [Product] = [
        Product(id: "sen", name: "Trà Sen Tây Hồ – hộp quà 200g", price: 1_250_000, compareAt: 1_400_000, image: "sen.jpg"),
        Product(id: "shan", name: "Trà Shan Tuyết cổ thụ 100g", price: 420_000, compareAt: nil, image: "shan.jpg"),
        Product(id: "olong", name: "Trà Ô Long Lâm Đồng 250g", price: 380_000, compareAt: 450_000, image: "olong.jpg"),
        Product(id: "am", name: "Bộ ấm chén men lam Bát Tràng", price: 890_000, compareAt: nil, image: "am.jpg"),
    ]

    static func vnd(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "vi_VN")
        return (f.string(from: NSNumber(value: n)) ?? "\(n)") + "đ"
    }
}

struct ShowcaseView: View {
    let demo: Demo
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                search
                banner
                HStack {
                    Text("Bán chạy").font(.title3.weight(.semibold))
                    Spacer()
                    Text("Xem tất cả").font(.subheadline).foregroundStyle(.secondary)
                }
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Showcase.products) { ProductTile(product: $0) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .background(Color(.systemBackground))
        .overlay(alignment: .bottomTrailing) {
            HatangChatLauncher().padding(20)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color(red: 0.70, green: 0.15, blue: 0.14))
                Image(systemName: "leaf.fill").foregroundStyle(Color(red: 0.95, green: 0.82, blue: 0.55))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mộc Hương Tea").font(.title2.weight(.bold))
                Text("Trà Việt · giao nhanh Hà Nội").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "bag").font(.title3)
                .overlay(alignment: .topTrailing) {
                    Text("2").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(4).background(Circle().fill(.red)).offset(x: 8, y: -8)
                }
        }
        .padding(.top, 8)
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            Text("Tìm trà, ấm chén, quà Tết…")
            Spacer()
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var banner: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(path: "sen.jpg")
                .frame(height: 170)
                .clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text("Hộp quà Tết 2027").font(.headline).foregroundStyle(.white)
                Text("Đặt sớm trước 31/10, giảm thêm 10%").font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ProductTile: View {
    let product: Showcase.Product

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RemoteImage(path: product.image)
                .frame(height: 130)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(product.name).font(.subheadline.weight(.medium)).lineLimit(2, reservesSpace: true)
            HStack(spacing: 6) {
                Text(Showcase.vnd(product.price)).font(.subheadline.weight(.semibold))
                if let c = product.compareAt {
                    Text(Showcase.vnd(c)).font(.caption).strikethrough().foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RemoteImage: View {
    let path: String

    var body: some View {
        AsyncImage(url: URL(string: "\(Showcase.imageBase)/\(path)")) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color(.tertiarySystemBackground)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
