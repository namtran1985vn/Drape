import SwiftUI
import PhotosUI

// MARK: - ViewModel

@MainActor
@Observable
final class ComposerModel {
    var roomImage: UIImage?
    var productImage: UIImage?
    var placement: Placement = .sofaThrow
    var extraNotes = ""
    var model: ImageModel = .v1_5
    var size: OutputSize = .portrait

    var result: UIImage?
    var isRunning = false
    var isAnalyzing = false
    var errorMessage: String?
    var lastTokens: Int?

    private let service = OpenAIImageEditService()

    var canRun: Bool {
        roomImage != nil && productImage != nil && !isRunning && !isAnalyzing && APIKeyStore.hasKey
    }

    func analyzeAndSetPlacement() async {
        guard let room = roomImage else { return }
        isAnalyzing = true
        errorMessage = nil
        defer { isAnalyzing = false }

        do {
            placement = try await service.analyzePlacement(roomImage: room)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func run() async {
        guard let room = roomImage, let product = productImage else { return }
        isRunning = true
        errorMessage = nil
        defer { isRunning = false }

        let prompt = PromptBuilder.build(
            placement: placement,
            customInstruction: "",
            extraNotes: extraNotes
        )

        do {
            let out = try await service.edit(
                EditRequest(
                    roomImage: room,
                    productImage: product,
                    prompt: prompt,
                    model: model,
                    size: size
                )
            )
            result = out.image
            lastTokens = out.totalTokens
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Main

struct ComposerView: View {
    @State private var vm = ComposerModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Ảnh") {
                    HStack(spacing: 12) {
                        ImageSlot(title: "Phòng", image: $vm.roomImage)
                        ImageSlot(title: "Sản phẩm", image: $vm.productImage)
                    }
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: vm.roomImage) { _, _ in
                    Task { await vm.analyzeAndSetPlacement() }
                }

                if vm.roomImage != nil {
                    Section("Vị trí đặt sản phẩm") {
                        HStack {
                            if vm.isAnalyzing {
                                ProgressView().padding(.trailing, 6)
                                Text("Đang phân tích phòng…").foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                Text(vm.placement.label).fontWeight(.medium)
                            }
                        }
                        .frame(height: 44)
                        TextField("Ghi chú thêm (tuỳ chọn)", text: $vm.extraNotes, axis: .vertical)
                            .lineLimit(1...3)
                    }
                }

                Section("Chất lượng") {
                    Picker("Model", selection: $vm.model) {
                        ForEach(ImageModel.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Khung hình", selection: $vm.size) {
                        ForEach(OutputSize.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Button {
                        Task { await vm.run() }
                    } label: {
                        HStack {
                            if vm.isRunning { ProgressView().padding(.trailing, 6) }
                            Text(vm.isRunning ? "Đang dựng ảnh…" : "Tạo ảnh")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(!vm.canRun)

                    if !APIKeyStore.hasKey {
                        Label("Chưa có API key — mở Cài đặt", systemImage: "key.slash")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                if let error = vm.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                }

                if let result = vm.result {
                    Section("Kết quả") {
                        Image(uiImage: result)
                            .resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        ShareLink(item: Image(uiImage: result), preview: .init("Ảnh sản phẩm"))
                        if let t = vm.lastTokens {
                            Text("\(t) tokens").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Thử sản phẩm")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }
}

// MARK: - Image slot

struct ImageSlot: View {
    let title: String
    @Binding var image: UIImage?
    @State private var item: PhotosPickerItem?

    var body: some View {
        PhotosPicker(selection: $item, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus").font(.title2)
                        Text(title).font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .frame(height: 130)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .onChange(of: item) { _, new in
            Task {
                guard let data = try? await new?.loadTransferable(type: Data.self),
                      let ui = UIImage(data: data) else { return }
                image = ui
            }
        }
    }
}


// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = APIKeyStore.key ?? ""
    @State private var checking = false
    @State private var status: String?

    private let service = OpenAIImageEditService()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-…", text: $keyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("OpenAI API key")
                } footer: {
                    Text("Key được lưu trong Keychain của máy này, không đồng bộ iCloud và không gửi đi đâu ngoài api.openai.com. Tạo key tại platform.openai.com → API keys. Tài khoản cần được verify để dùng model tạo ảnh.")
                }

                Section {
                    Button {
                        Task {
                            checking = true; status = nil
                            let ok = await service.validate(key: keyInput)
                            checking = false
                            status = ok ? "Key hợp lệ ✓" : "Key không dùng được"
                            if ok { APIKeyStore.key = keyInput }
                        }
                    } label: {
                        HStack {
                            if checking { ProgressView().padding(.trailing, 6) }
                            Text("Kiểm tra & lưu")
                        }
                    }
                    .disabled(keyInput.isEmpty || checking)

                    if let status {
                        Text(status).font(.footnote)
                            .foregroundStyle(status.hasSuffix("✓") ? .green : .red)
                    }

                    if APIKeyStore.hasKey {
                        Button("Xoá key", role: .destructive) {
                            APIKeyStore.key = nil
                            keyInput = ""
                            status = nil
                        }
                    }
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { APIKeyStore.key = keyInput; dismiss() }
                }
            }
        }
    }
}
