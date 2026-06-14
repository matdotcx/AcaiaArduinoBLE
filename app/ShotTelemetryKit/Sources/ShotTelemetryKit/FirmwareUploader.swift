import Foundation

/// Uploads a firmware `.bin` to the ShotStopper's web updater over local WiFi.
///
/// The firmware (OTASetup.h) hosts a multipart form POST at `/update` with the
/// file field named `update` — the same upload its browser uploader does, just
/// driven from the app so no browser is needed.
@MainActor
@Observable
public final class FirmwareUploader: NSObject {

    public enum Status: Equatable {
        case idle
        case uploading(Double)   // 0...1
        case success
        case failed(String)
    }

    public private(set) var status: Status = .idle

    public func reset() { status = .idle }

    /// POST the file at `fileURL` to `http://<ip>/update`. `fileURL` is typically a
    /// security-scoped URL from the Files picker (iCloud Drive).
    public func upload(fileURL: URL, toIP ip: String) async {
        status = .uploading(0)

        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }

        guard let fileData = try? Data(contentsOf: fileURL) else {
            status = .failed("Couldn't read the selected file.")
            return
        }
        guard !ip.isEmpty, let url = URL(string: "http://\(ip)/update") else {
            status = .failed("The device hasn't reported an address yet.")
            return
        }

        let boundary = "ShotStopperBoundary-\(UUID().uuidString)"
        let body = Self.multipartBody(boundary: boundary, fieldName: "update",
                                      fileName: fileURL.lastPathComponent, fileData: fileData)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 180

        do {
            let (_, response) = try await URLSession.shared.upload(for: request, from: body, delegate: self)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                status = .failed("Device returned HTTP \(http.statusCode).")
            } else {
                status = .success
            }
        } catch {
            // A dropped connection right after the upload often means the device
            // accepted it and rebooted; surface the raw error so the user can retry.
            status = .failed(error.localizedDescription)
        }
    }

    /// Build a `multipart/form-data` body for a single file field. Pure + testable.
    public nonisolated static func multipartBody(boundary: String, fieldName: String, fileName: String, fileData: Data) -> Data {
        var body = Data()
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n--\(boundary)--\r\n")
        return body
    }
}

extension FirmwareUploader: URLSessionTaskDelegate {
    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        MainActor.assumeIsolated {
            if case .uploading = status { status = .uploading(fraction) }
        }
    }
}

private extension Data {
    mutating func appendString(_ string: String) { append(Data(string.utf8)) }
}
