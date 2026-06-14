import SwiftUI
import UniformTypeIdentifiers
import ShotTelemetryKit

/// Firmware OTA flow. Send the machine WiFi credentials and ask it to enter OTA
/// mode; it joins the network and reports its IP. Then pick a `.bin` from Files /
/// iCloud Drive and the app uploads it straight to the device — no browser needed.
struct OTAView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    private var client: ShotStopperClient { model.client }

    @State private var ssid = ""
    @State private var password = ""
    @State private var uploader = FirmwareUploader()
    @State private var showImporter = false

    private var deviceIP: String { client.settings.wifiIP }

    var body: some View {
        Form {
            Section {
                Text("Send the machine your 2.4 GHz WiFi, then start OTA mode. "
                     + "When it reports an address, choose a firmware .bin to upload.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("WiFi") {
                TextField("Network name (SSID)", text: $ssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            .disabled(client.settings.otaRequested)

            Section {
                if client.settings.otaRequested {
                    activeOTASection
                    Button("Exit OTA mode", role: .cancel) {
                        uploader.reset()
                        client.setOTARequested(false)
                    }
                } else {
                    Button {
                        client.setWiFi(ssid: ssid, password: password)
                        client.setOTARequested(true)
                    } label: {
                        Label("Start OTA mode", systemImage: "arrow.up.circle")
                    }
                    .disabled(ssid.isEmpty)
                }
            }

            Section {
                LabeledContent("Current firmware", value: "v\(client.settings.firmwareVersion)")
            }
        }
        .navigationTitle("Firmware OTA")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: binTypes) { result in
            if case .success(let url) = result {
                Task { await uploader.upload(fileURL: url, toIP: deviceIP) }
            }
        }
        .onAppear { ssid = client.settings.wifiSSID }
    }

    @ViewBuilder
    private var activeOTASection: some View {
        if deviceIP.isEmpty {
            HStack {
                ProgressView()
                Text("Connecting to WiFi…").foregroundStyle(.secondary)
            }
        } else {
            LabeledContent("Device address", value: deviceIP)

            switch uploader.status {
            case .idle:
                Button {
                    showImporter = true
                } label: {
                    Label("Choose firmware (.bin)…", systemImage: "folder")
                }
                if let url = URL(string: "http://\(deviceIP)/") {
                    Link(destination: url) {
                        Label("Or open the web uploader", systemImage: "safari")
                            .font(.footnote)
                    }
                }

            case .uploading(let fraction):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction)
                    Text("Uploading… \(Int(fraction * 100))%")
                        .font(.footnote).foregroundStyle(.secondary)
                }

            case .success:
                Label("Update sent — the machine is restarting.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                    Button("Try again") { showImporter = true }
                }
            }
        }
    }

    private var binTypes: [UTType] {
        [UTType(filenameExtension: "bin") ?? .data, .data]
    }
}
