# App 图标原稿

`AppIconSource.png` 是用户于 2026-10-13 选定的第二版角色图标原稿（1254 × 1254，绿色与米白简化轮廓），由内置 imagegen 生成。

在项目根目录执行 `swift Scripts/make_icon.swift`，按原稿直接缩放导出 1024 × 1024 的 AppIcon，以及 `App/Resources` 中全部 iPhone / iPad 图标尺寸。输出为不含透明通道的 PNG，不额外裁切或预制圆角。

当前工程使用 Info.plist 指向独立 PNG 图标；Assets 中的 AppIcon 同步保留。重新运行导出脚本不会恢复旧的 Checklist 图标。看板娘立绘尚未接入 App。
