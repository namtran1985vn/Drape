import Foundation

/// Vị trí đặt sản phẩm. Đây là biến quan trọng nhất — model cần biết CHÍNH XÁC
/// đặt vào đâu, nếu không nó sẽ tự sáng tác và làm hỏng bố cục phòng.
enum Placement: String, CaseIterable, Identifiable, Sendable {
    case sofaThrow
    case tableRunner
    case cushionCover
    case bedThrow
    case curtain
    case rug
    case wallHanging
    case custom

    var id: String { rawValue }

    /// Nhãn tiếng Việt cho UI
    var label: String {
        switch self {
        case .sofaThrow:   "Vắt trên sofa"
        case .tableRunner: "Khăn trải bàn / runner"
        case .cushionCover: "Vỏ gối tựa"
        case .bedThrow:    "Khăn trải giường"
        case .curtain:     "Rèm cửa"
        case .rug:         "Thảm sàn"
        case .wallHanging: "Treo tường"
        case .custom:      "Tự mô tả"
        }
    }

    /// Mô tả bằng tiếng Anh gửi cho model (model hiểu tiếng Anh chính xác hơn nhiều)
    var instruction: String {
        switch self {
        case .sofaThrow:
            "draped naturally over the back and left armrest of the sofa, with soft realistic folds falling toward the seat"
        case .tableRunner:
            "laid flat as a table runner down the center of the table, edges hanging slightly over both sides"
        case .cushionCover:
            "used as the fabric cover of the existing throw cushion, replacing only the cushion's surface pattern while keeping its exact shape, size and position"
        case .bedThrow:
            "folded across the foot of the bed, draping over both sides with natural weight and folds"
        case .curtain:
            "hanging as curtain panels on the existing window, following the existing curtain rod and window dimensions"
        case .rug:
            "laid flat on the floor in the open area, following the floor's perspective and partially under the existing furniture"
        case .wallHanging:
            "hung flat on the empty wall area as a textile wall hanging, centered and at natural eye height"
        case .custom:
            ""
        }
    }
}

enum PromptBuilder {

    /// - Parameters:
    ///   - placement: preset vị trí
    ///   - customInstruction: dùng khi placement == .custom
    ///   - extraNotes: ghi chú thêm của user (VD: "làm phòng sáng hơn một chút")
    static func build(
        placement: Placement,
        customInstruction: String = "",
        extraNotes: String = ""
    ) -> String {
        let where_ = placement == .custom
            ? customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
            : placement.instruction

        var prompt = """
        You are compositing a real product into a real interior photograph.

        IMAGE 1 is the ROOM (the scene).
        IMAGE 2 is the PRODUCT (a handwoven home textile).

        TASK: Place the product from IMAGE 2 into the room from IMAGE 1, \(where_).

        HARD CONSTRAINTS — the room must stay real:
        - Keep the room's architecture, camera angle, focal length and perspective EXACTLY unchanged.
        - Do NOT add, remove, resize or move any existing furniture, walls, windows, plants or decor.
        - Do NOT change the wall colour, flooring, or the overall composition and framing.
        - Change ONLY the area where the product is placed.

        PRODUCT FIDELITY — this is a real catalogue item:
        - Reproduce the exact weave pattern, thread texture, colours and proportions shown in IMAGE 2.
        - Do NOT invent, simplify, restyle or recolour the pattern. Do NOT mirror or repeat it incorrectly.
        - Keep the product's real-world scale plausible relative to the furniture around it.

        PHYSICAL REALISM:
        - Match the room's existing lighting direction, colour temperature, exposure and shadow softness.
        - Add correct contact shadows and ambient occlusion where the fabric touches surfaces.
        - Fabric must drape with real weight: folds, creases and foreshortening that follow the surface geometry.
        - Keep the same grain, noise level and depth of field as IMAGE 1.

        OUTPUT: one photorealistic interior photograph. No text, no watermark, no logo, no border, no collage.
        """

        let notes = extraNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            prompt += "\n\nADDITIONAL REQUEST FROM THE USER: \(notes)"
        }
        return prompt
    }
}
