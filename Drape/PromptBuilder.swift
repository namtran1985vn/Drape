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
            "draped over the sofa as a large throw that covers the seat and backrest, spilling over the armrests into natural folds falling toward the floor"
        case .tableRunner:
            "draped over the table, covering the top surface and hanging down over both edges with natural folds"
        case .cushionCover:
            "used as the fabric cover of the existing throw cushion, replacing only the cushion's surface pattern while keeping its exact shape, size and position"
        case .bedThrow:
            "spread over the bed as a large cover that drapes down over both sides and the foot, with natural weight and folds"
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
        IMAGE 2 is the PRODUCT: a large handwoven textile — a throw / cover / blanket meant to be DRAPED over furniture.

        TASK: Take the exact fabric shown in IMAGE 2 and drape it in the room from IMAGE 1 so that it is \(where_). The product should read as a real woven cloth laid over the furniture, not as a flat sticker or a repainted surface.

        PRODUCT FIDELITY — THIS IS THE MOST IMPORTANT RULE:
        - IMAGE 2 is the ground truth for the fabric. Reproduce its weave pattern, motif, stripes, borders, thread texture and colours EXACTLY, pixel-faithfully.
        - Do NOT redraw, invent, simplify, smooth, stylise, recolour or "improve" the pattern. Do NOT swap it for a generic knit or a different design.
        - Keep the correct scale and repeat of the motif; do NOT stretch, shrink, mirror or tile it wrongly.
        - Only bend/warp the pattern to follow the folds and drape of the cloth — the design itself stays identical to IMAGE 2.

        HARD CONSTRAINTS — the room must stay real:
        - Keep the room's architecture, camera angle, focal length and perspective EXACTLY unchanged.
        - Do NOT add, remove, resize or move any existing furniture, walls, windows, plants or decor.
        - Do NOT change the wall colour, flooring, or the overall composition and framing.
        - Change ONLY the area covered by the draped product.

        PHYSICAL REALISM:
        - The cloth drapes with real weight: soft folds, creases, sagging and foreshortening that follow the furniture's geometry.
        - Match the room's existing lighting direction, colour temperature, exposure and shadow softness.
        - Add correct contact shadows and ambient occlusion where the fabric touches surfaces.
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
