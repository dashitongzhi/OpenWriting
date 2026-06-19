enum SidebarItem: String, CaseIterable, Identifiable {
    case home
    case projects
    case writingDesk
    case outline
    case library

    var id: Self { self }

    var title: String {
        switch self {
        case .home:
            return "首页"
        case .projects:
            return "项目空间"
        case .writingDesk:
            return "写作台"
        case .outline:
            return "章节树"
        case .library:
            return "创作资源"
        }
    }

    var symbolName: String {
        switch self {
        case .home:
            return "house"
        case .projects:
            return "square.grid.2x2"
        case .writingDesk:
            return "square.and.pencil"
        case .outline:
            return "list.bullet.rectangle.portrait"
        case .library:
            return "books.vertical"
        }
    }

    var summary: String {
        switch self {
        case .home:
            return "总览当前章节、模型配置和快速开始入口。"
        case .projects:
            return "这里会放项目列表、筛选器和最近打开的手稿。"
        case .writingDesk:
            return "这里会直接进入当前章节的正文创作与续写。"
        case .outline:
            return "这里会放章节树、场景卡片和剧情推进视图。"
        case .library:
            return "这里会集中管理人物、地点、世界观素材和写作 Skill。"
        }
    }
}
