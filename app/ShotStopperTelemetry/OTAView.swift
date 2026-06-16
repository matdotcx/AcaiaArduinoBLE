import SwiftUI
import UniformTypeIdentifiers
import Security
import ShotTelemetryKit

/// Firmware OTA: send WiFi, enter OTA mode, then upload a .bin from Files in-app.
struct OTAView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private var client: ShotStopperClient { model.client }

    @State private var ssid = ""
    @State private var password = ""
    @State private var uploader = FirmwareUploader()
    @State private var showImporter = false

    private var deviceIP: String { client.settings.wifiIP }
    /// The firmware reports `"disconnected"` / `"empty"` (not "") until it actually
    /// joins Wi-Fi, so only treat a real dotted IPv4 as connected — otherwise the
    /// upload UI and `http://<ip>/` link would point at a bogus host.
    private var hasDeviceIP: Bool {
        let parts = deviceIP.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
    private var uploading: Bool { if case .uploading = uploader.status { return true }; return false }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    Text("Firmware OTA").font(DS.title(28)).foregroundStyle(DS.ink).padding(.top, DS.Space.s)

                    if uploading || uploadFinished { uploadingCard }

                    wifiSection
                    deviceSection
                }
                .padding(.horizontal, DS.Space.xl)
                .padding(.bottom, DS.Space.xl)
            }
            backBar
        }
        .background(DS.canvas)
        .navigationBarHidden(true)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: binTypes) { result in
            if case .success(let url) = result {
                Task { await uploader.upload(fileURL: url, toIP: deviceIP) }
            }
        }
        .onAppear {
            ssid = client.settings.wifiSSID
            password = WiFiCredentialStore.loadPassword()   // write-only on the device; remember it locally
        }
    }

    private var uploadFinished: Bool {
        if case .success = uploader.status { return true }
        if case .failed = uploader.status { return true }
        return false
    }

    // MARK: Uploading card (dark)

    @ViewBuilder private var uploadingCard: some View {
        let pct: Int = { if case .uploading(let f) = uploader.status { return Int(f * 100) }; if case .success = uploader.status { return 100 }; return 0 }()
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                if uploading { PulsingDot(color: .white, size: 7) } else { Circle().fill(.white).frame(width: 7, height: 7) }
                DSMonoLabel(uploadStatusText, size: 10, color: Color.white.opacity(0.85))
            }
            Text("\(pct)%").font(DS.numeral(54, .regular)).monospacedDigit().foregroundStyle(.white)
            TargetProgressBar(fraction: Double(pct) / 100, color: DS.orange, height: 10)
            DSMonoLabel(uploadDetailText, size: 9.5, color: Color.white.opacity(0.6))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(rgb: 0x1A1714), in: RoundedRectangle(cornerRadius: DS.R.card, style: .continuous))
    }

    private var uploadStatusText: String {
        switch uploader.status {
        case .uploading: return "UPLOADING · \(deviceIP)"
        case .success:   return "DONE · MACHINE RESTARTING"
        case .failed:    return "UPLOAD FAILED"
        case .idle:      return ""
        }
    }
    private var uploadDetailText: String {
        switch uploader.status {
        case .uploading: return "firmware.bin · keep the app open"
        case .success:   return "the machine is applying the update"
        case .failed(let m): return m.uppercased()
        case .idle: return ""
        }
    }

    // MARK: WiFi

    private var wifiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSMonoLabel("WI-FI", color: DS.inkMuted)
            DSCard {
                VStack(spacing: 0) {
                    fieldRow("Network") {
                        TextField("SSID", text: $ssid).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .multilineTextAlignment(.trailing).font(.system(size: 15))
                    }
                    rowDivider
                    fieldRow("Password") {
                        SecureField("••••••", text: $password).multilineTextAlignment(.trailing).font(.system(size: 15))
                    }
                }
            }
            .disabled(client.settings.otaRequested)
        }
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(DS.inkMuted)
            content()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: Device

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSMonoLabel("DEVICE", color: DS.inkMuted)
            DSCard {
                VStack(spacing: 0) {
                    HStack {
                        Text("Current firmware").font(.system(size: 15)).foregroundStyle(DS.inkMuted)
                        Spacer()
                        Text("v\(client.settings.firmwareVersion)").font(DS.numeral(15, .semibold)).foregroundStyle(DS.ink)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    rowDivider
                    actionArea.padding(16)
                }
            }
        }
    }

    @ViewBuilder private var actionArea: some View {
        if !client.settings.otaRequested {
            Button {
                WiFiCredentialStore.savePassword(password)
                client.setWiFi(ssid: ssid, password: password)
                client.setOTARequested(true)
            } label: { Label("Start OTA mode", systemImage: "arrow.up.circle") }
                .buttonStyle(DSPillStyle(kind: .orange, fullWidth: true))
                .disabled(ssid.isEmpty || password.isEmpty)
        } else if !hasDeviceIP {
            VStack(spacing: 8) {
                HStack(spacing: 8) { ProgressView().tint(DS.orange); Text("Connecting to WiFi…").font(.system(size: 14)).foregroundStyle(DS.inkMuted) }
                Text("Must be a 2.4 GHz network — the controller can't use 5 GHz. Check the SSID and password.")
                    .font(.system(size: 12)).foregroundStyle(DS.inkMuted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Button("Cancel") { client.setOTARequested(false) }
                    .buttonStyle(DSPillStyle(kind: .outlined, fullWidth: true)).padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: 12) {
                if !uploading {
                    Button { showImporter = true } label: { Label("Choose firmware (.bin)…", systemImage: "folder") }
                        .buttonStyle(DSPillStyle(kind: .orange, fullWidth: true))
                    if let url = URL(string: "http://\(deviceIP)/") {
                        Link(destination: url) { Text("Or open the web uploader").font(.system(size: 13)) }
                            .foregroundStyle(DS.inkMuted)
                    }
                }
                Button("Exit OTA mode") { uploader.reset(); client.setOTARequested(false) }
                    .buttonStyle(DSPillStyle(kind: .outlined, fullWidth: true))
            }
        }
    }

    // MARK: Chrome

    private var rowDivider: some View { Rectangle().fill(DS.hairline).frame(height: 1).padding(.leading, 16) }

    private var backBar: some View {
        HStack {
            Button { dismiss() } label: { Label("Back", systemImage: "chevron.left").font(.system(size: 15, weight: .semibold)) }
                .buttonStyle(DSPillStyle(kind: .outlined))
            Spacer()
            Button("Done") { dismiss() }.buttonStyle(DSPillStyle(kind: .ink))
        }
        .padding(.horizontal, DS.Space.xl).padding(.vertical, DS.Space.m)
        .background(DS.canvas)
    }

    private var binTypes: [UTType] { [UTType(filenameExtension: "bin") ?? .data, .data] }
}

/// Remembers the OTA Wi-Fi password in the Keychain. The device's password
/// characteristic is write-only, so the app can't read it back — without this the
/// field blanks every visit and "Start OTA mode" could send an empty password.
enum WiFiCredentialStore {
    private static let service = "org.iaconelli.ShotStopperTelemetry.ota"
    private static let account = "wifi-password"

    static func savePassword(_ password: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard !password.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func loadPassword() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrService as String: service,
                                     kSecAttrAccount as String: account,
                                     kSecReturnData as String: true,
                                     kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
