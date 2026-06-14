import SwiftUI
import ShotTelemetryKit

/// Firmware OTA flow. The firmware's updater is a WiFi web upload: we send the
/// machine WiFi credentials and ask it to enter OTA mode; it joins the network,
/// hosts an uploader, and reports its IP. The user then opens that page and
/// uploads the new `.bin` from a browser.
struct OTAView: View {
    @Environment(AppModel.self) private var model
    private var client: ShotStopperClient { model.client }

    @State private var ssid = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                Text("Send the machine your 2.4 GHz WiFi, then start OTA mode. "
                     + "When it shows an address, open it to upload a new firmware .bin.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("WiFi") {
                TextField("Network name (SSID)", text: $ssid)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }

            Section {
                if client.settings.otaRequested {
                    if client.settings.wifiIP.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Connecting to WiFi…").foregroundStyle(.secondary)
                        }
                    } else if let url = URL(string: "http://\(client.settings.wifiIP)/") {
                        Link(destination: url) {
                            Label("Open uploader  (\(client.settings.wifiIP))", systemImage: "safari")
                        }
                    }
                    Button("Exit OTA mode", role: .cancel) { client.setOTARequested(false) }
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
        .onAppear { ssid = client.settings.wifiSSID }
    }
}
