enum PoseGuidance {
    static let summary = "人体识别仅供辅助估算，请逐帧复核点位。"
    static let limitations = "骨架和角度是二维画面的辅助估算。遮挡、运动模糊、侧身或多人可能导致关节点偏移、左右肢混淆或缺失；高置信度也可能出错。请逐帧人工复核，不作为三维测量或自动动作评分。"
    static let badge = "辅助估算 · 请复核"
    static let exportNotice = "导出的骨架和角度仅供辅助估算，画面保留“辅助估算 · 请复核”标识。请向接收者说明点位与角度需要人工复核。"
}
