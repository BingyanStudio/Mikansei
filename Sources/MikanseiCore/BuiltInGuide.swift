import Foundation

public extension Entry {
    /// 首次安装（档案文件不存在）时内置的使用说明笔记，两端共享同一份文案。
    static func builtInGuideNote(now: Date = Date()) -> Entry {
        Entry(title: "使用说明", body: guideMarkdown, kind: .note, category: "帮助",
              createdAt: now, updatedAt: now)
    }

    static let guideMarkdown = """
        # 欢迎使用 Mikansei

        这是一个学生向的待办与日程工具。

        ## 快速上手
        - 底部三个标签：**待办 / 日程 / 笔记**
        - 右上角 **＋** 新建；左侧圆圈完成；卡片上 ▶ 开始专注计时
        - 长按月历日期可快速添加日程

        ## 规划
        - 「日程」页顶部 **规划** 入口：
          - **日程规划**：月历涂色选“哪几天做”（常态自动规划）
          - **小时规划**（iPhone）：把今日待办拖进时间轴
        - 待办列表长按拖动可调整顺序

        ## 同步与提醒
        - 设置 → iCloud Drive 同步：与其它设备互通（含 Mikanseta）
        - 支持系统提醒、闹钟提醒与锁屏小组件；规划时段开始会提醒你专注

        ## 笔记
        - 笔记全页编辑，正文支持 **Markdown**，可切换预览

        ---
        """
}
