import SwiftUI

struct AboutView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 30) {
                    
                    // App logo
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.cyan.opacity(0.4), .blue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                                .overlay(Circle().stroke(Color.cyan.opacity(0.5), lineWidth: 1.5))
                            
                            Image(systemName: "shield.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.cyan)
                        }
                        
                        Text("about.title".localized)
                            .font(.largeTitle.bold())
                            .foregroundColor(.white)
                        
                        Text("v\(appVersion)")
                            .font(.subheadline.monospaced())
                            .foregroundColor(.cyan.opacity(0.8))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.cyan.opacity(0.12)))
                        
                        Text("about.subtitle".localized)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 20)
                    
                    // Author card
                    VStack(alignment: .leading, spacing: 0) {
                        Text("about.author".localized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                        
                        VStack(spacing: 0) {
                            AuthorRow(
                                icon: "person.fill",
                                iconColor: .cyan,
                                label: "Author",
                                value: "BarabaDev",
                                showDivider: true
                            )
                            AuthorLinkRow(
                                icon: "at",
                                iconColor: Color(red: 0.1, green: 0.6, blue: 1.0),
                                label: "Twitter",
                                value: "@BarabaDev",
                                url: "https://twitter.com/BarabaDev",
                                showDivider: true
                            )
                            AuthorLinkRow(
                                icon: "chevron.left.forwardslash.chevron.right",
                                iconColor: .purple,
                                label: "GitHub",
                                value: "github.com/BarabaDev",
                                url: "https://github.com/BarabaDev",
                                showDivider: true
                            )
                            AuthorLinkRow(
                                icon: "shippingbox.fill",
                                iconColor: .orange,
                                label: "Repository",
                                value: "BarabaDev/SentinelCrash",
                                url: "https://github.com/BarabaDev/SentinelCrash",
                                showDivider: false
                            )
                        }
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .padding(.horizontal, 16)
                    }
                    
                    // App info
                    VStack(alignment: .leading, spacing: 0) {
                        Text("about.application".localized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                        
                        VStack(spacing: 0) {
                            AuthorRow(icon: "iphone",           iconColor: .green,   label: "about.platform".localized,     value: "iOS 15.0+",             showDivider: true)
                            AuthorRow(icon: "lock.open.fill",   iconColor: .cyan,    label: "about.jbMode".localized,      value: "Rootless (/var/jb)",     showDivider: true)
                            AuthorRow(icon: "swift",            iconColor: .orange,  label: "about.language".localized,     value: "Swift 5 / SwiftUI",      showDivider: true)
                            AuthorRow(icon: "doc.text.fill",    iconColor: .yellow,  label: "about.logFormats".localized,  value: ".ips, .crash, .log",     showDivider: true)
                            AuthorRow(icon: "c.circle.fill",    iconColor: .gray,    label: "about.license".localized,      value: "MIT © 2026 BarabaDev",   showDivider: false)
                        }
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .padding(.horizontal, 16)
                    }
                    
                    Text("about.description".localized)
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.6))
                        .padding(.bottom, 30)
                }
            }
        }
        .navigationTitle("about.title".localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Row Components

struct AuthorRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let showDivider: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .frame(width: 28)
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.white)
                Spacer()
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            
            if showDivider {
                Divider()
                    .background(Color.white.opacity(0.07))
                    .padding(.leading, 56)
            }
        }
    }
}

struct AuthorLinkRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let url: String
    let showDivider: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                if let u = URL(string: url) { UIApplication.shared.open(u) }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .frame(width: 28)
                    Text(label)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Spacer()
                    Text(value)
                        .font(.subheadline)
                        .foregroundColor(.cyan)
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            
            if showDivider {
                Divider()
                    .background(Color.white.opacity(0.07))
                    .padding(.leading, 56)
            }
        }
    }
}
