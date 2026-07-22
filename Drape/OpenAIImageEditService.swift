import Foundation
import UIKit

// MARK: - Cấu hình

enum ImageModel: String, CaseIterable, Identifiable, Sendable {
    case mini    = "gpt-image-1-mini"   // rẻ + nhanh — dùng để preview / thử vị trí
    case v1_5    = "gpt-image-1.5"      // mặc định — giữ chi tiết tốt nhất
    case v1      = "gpt-image-1"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .mini: "Nhanh (nháp)"
        case .v1_5: "Chất lượng cao"
        case .v1:   "gpt-image-1"
        }
    }
}

enum OutputSize: String, CaseIterable, Identifiable, Sendable {
    case square    = "1024x1024"
    case portrait  = "1024x1536"
    case landscape = "1536x1024"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .square: "Vuông 1:1"
        case .portrait: "Dọc 2:3"
        case .landscape: "Ngang 3:2"
        }
    }
}

struct EditRequest: Sendable {
    var roomImage: UIImage
    var productImage: UIImage
    var prompt: String
    var model: ImageModel = .v1_5
    var size: OutputSize = .portrait
    var quality: String = "high"        // "low" | "medium" | "high" | "auto"
    var maskImage: UIImage? = nil       // optional — vùng trắng/trong suốt = cho phép sửa
}

struct EditResult: Sendable {
    var image: UIImage
    var totalTokens: Int?
}

enum OpenAIError: LocalizedError {
    case missingKey
    case encodingFailed
    case api(status: Int, message: String)
    case emptyResponse
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .missingKey:
            "Chưa có API key. Vào Cài đặt để nhập key OpenAI."
        case .encodingFailed:
            "Không nén được ảnh."
        case .api(let status, let message):
            switch status {
            case 401: "API key không hợp lệ hoặc đã bị thu hồi."
            case 403: "Tổ chức của key này chưa được verify để dùng model tạo ảnh."
            case 429: "Vượt rate limit hoặc hết credit OpenAI. Thử lại sau."
            case 400: "Yêu cầu bị từ chối: \(message)"
            default:  "Lỗi OpenAI (\(status)): \(message)"
            }
        case .emptyResponse:
            "OpenAI không trả về ảnh nào."
        case .decodeFailed:
            "Không đọc được ảnh trả về."
        }
    }
}

// MARK: - Service

actor OpenAIImageEditService {

    private let endpoint = URL(string: "https://api.openai.com/v1/images/edits")!
    private let visionEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 240   // sinh ảnh có thể mất 30–90s
        config.timeoutIntervalForResource = 300
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    func edit(_ request: EditRequest) async throws -> EditResult {
        guard let apiKey = APIKeyStore.key, !apiKey.isEmpty else {
            throw OpenAIError.missingKey
        }

        // Downscale trước khi gửi: ảnh 12MP không giúp gì, chỉ tốn input token và thời gian.
        guard
            let roomData = request.roomImage.jpegForUpload(maxDimension: 1536),
            let productData = request.productImage.jpegForUpload(maxDimension: 1024)
        else { throw OpenAIError.encodingFailed }

        var form = MultipartForm()
        form.addField("model", request.model.rawValue)
        form.addField("prompt", request.prompt)
        form.addField("input_fidelity", "high")     // giữ hoa văn dệt + kiến trúc phòng
        form.addField("size", request.size.rawValue)
        form.addField("quality", request.quality)
        form.addField("output_format", "webp")
        form.addField("output_compression", "90")
        form.addField("n", "1")

        // THỨ TỰ QUAN TRỌNG: ảnh phòng trước (IMAGE 1), sản phẩm sau (IMAGE 2).
        form.addFile("image[]", filename: "room.jpg", mimeType: "image/jpeg", data: roomData)
        form.addFile("image[]", filename: "product.jpg", mimeType: "image/jpeg", data: productData)

        if let mask = request.maskImage, let maskData = mask.pngData() {
            // mask áp lên ảnh đầu tiên (ảnh phòng)
            form.addFile("mask", filename: "mask.png", mimeType: "image/png", data: maskData)
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = form.finalize()

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard (200..<300).contains(status) else {
            let message = Self.extractErrorMessage(from: data)
            throw OpenAIError.api(status: status, message: message)
        }

        struct APIResponse: Decodable {
            struct Item: Decodable { let b64_json: String? }
            struct Usage: Decodable { let total_tokens: Int? }
            let data: [Item]?
            let usage: Usage?
        }

        guard let decoded = try? JSONDecoder().decode(APIResponse.self, from: data) else {
            throw OpenAIError.decodeFailed
        }
        guard let b64 = decoded.data?.first?.b64_json,
              let imageData = Data(base64Encoded: b64),
              let image = UIImage(data: imageData)
        else { throw OpenAIError.emptyResponse }

        return EditResult(image: image, totalTokens: decoded.usage?.total_tokens)
    }

    /// Phân tích phòng → tự động chọn vị trí tối ưu nhất để đặt sản phẩm.
    func analyzePlacement(roomImage: UIImage) async throws -> Placement {
        guard let apiKey = APIKeyStore.key, !apiKey.isEmpty else {
            throw OpenAIError.missingKey
        }

        guard let roomData = roomImage.jpegForUpload(maxDimension: 1024) else {
            throw OpenAIError.encodingFailed
        }

        let base64 = roomData.base64EncodedString()
        let placementOptions = Placement.allCases
            .filter { $0 != .custom }
            .map { "- \($0.label)" }
            .joined(separator: "\n")

        struct VisionRequest: Encodable {
            struct Message: Encodable {
                struct Content: Encodable {
                    let type: String
                    let text: String?
                    let image_url: ImageUrl?

                    enum CodingKeys: String, CodingKey {
                        case type, text, image_url
                    }

                    struct ImageUrl: Encodable {
                        let url: String
                    }
                }
                let role: String
                let content: [Content]
            }
            let model: String
            let messages: [Message]
            let temperature: Double = 0.3
            let max_tokens: Int = 200
        }

        let prompt = """
        Phân tích bức ảnh phòng này. Xác định vị trí TỐI ƯU nhất để trưng bày một chiếc khăn/vải dệt handwoven cho khách hàng có thể nhìn rõ và thấy đẹp.

        Lựa chọn CHỈ MỘT từ danh sách sau:
        \(placementOptions)

        Trả lời CHỈ tên vị trí, không giải thích.
        """

        let request = VisionRequest(
            model: "gpt-4-turbo",
            messages: [.init(
                role: "user",
                content: [
                    .init(type: "text", text: prompt, image_url: nil),
                    .init(
                        type: "image_url",
                        text: nil,
                        image_url: .init(url: "data:image/jpeg;base64,\(base64)")
                    )
                ]
            )]
        )

        var urlRequest = URLRequest(url: visionEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        guard (200..<300).contains(status) else {
            let message = Self.extractErrorMessage(from: data)
            throw OpenAIError.api(status: status, message: message)
        }

        struct VisionResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let content: String
                }
                let message: Message
            }
            let choices: [Choice]
        }

        guard let decoded = try? JSONDecoder().decode(VisionResponse.self, from: data),
              let responseText = decoded.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            throw OpenAIError.decodeFailed
        }

        for placement in Placement.allCases {
            if responseText.localizedCaseInsensitiveContains(placement.label) {
                return placement
            }
        }

        return .sofaThrow
    }

    /// Kiểm tra key có sống không (dùng ở màn Cài đặt).
    func validate(key: String) async -> Bool {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (_, resp) = try? await session.data(for: req) else { return false }
        return (resp as? HTTPURLResponse)?.statusCode == 200
    }

    private static func extractErrorMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable {
            struct E: Decodable { let message: String? }
            let error: E?
        }
        if let e = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let m = e.error?.message { return m }
        return String(data: data, encoding: .utf8) ?? "unknown"
    }
}

// MARK: - Multipart

struct MultipartForm {
    private let boundary = "Boundary-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, data: Data) {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func finalize() -> Data {
        var out = body
        out.append("--\(boundary)--\r\n")
        return out
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

// MARK: - Image prep

extension UIImage {
    /// Xoay đúng chiều + resize cạnh dài về `maxDimension` + nén JPEG.
    func jpegForUpload(maxDimension: CGFloat, quality: CGFloat = 0.88) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (size.width * scale).rounded(),
                            height: (size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let normalized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: target))   // tự áp dụng imageOrientation
        }
        return normalized.jpegData(compressionQuality: quality)
    }
}
