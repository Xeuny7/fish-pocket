import SwiftUI
import WatchConnectivity

/// Account access, frequently used settings and tools in the 探索 tab.
struct ExploreTabView: View {
    enum Route: Hashable {
        case account, models, schedules, installedPlugins, settings
        case miniApps, plugins, connectors, phoneControl, remote, watch, shortcuts, share
    }

    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openSession) private var openSession
    @Binding var path: [Route]
    @State private var phoneControl = PhoneControlService()
    @State private var watch = WatchPairing.current
    @State private var miniApps = MiniAppStore.shared
    /// 设置 and the pages pushed from it wear the settings look, which a page takes from the stack
    /// it is in: put on just before 设置 is pushed, taken off once the stack is back at this page,
    /// which the look does not change. Never in the same update as a push: before iOS 26 the stack,
    /// shown again just after another tab, pushed 设置 a second time when its look changed with it.
    @State private var settingsLook = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink(value: Route.account) { ExploreAccountRow(account: app.account) }
                }
                .groupedRow()
                Section {
                    quickLink(.models, "模型", "cpu")
                    // A button, not a link: the look goes on first and 设置 is pushed after it
                    // (`openSettings`), so the chevron is drawn here as a link's would be.
                    Button(action: openSettings) {
                        label(Text("设置"), .settings, Text("访问权限、语音和外观")) {
                            Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).foregroundStyle(Palette.faint)
                        }
                    }
                    .foregroundStyle(Palette.ink)
                } header: {
                    Text("常用设置").foregroundStyle(Palette.secondary)
                }
                .groupedRow()
                Section {
                    row(.miniApps, Text(MiniAppsPage.tabTitle), .miniApps, "与 AI 共创",
                        status: miniApps.apps.isEmpty ? nil : String(localized: "\(miniApps.apps.count) 个 Mini App"))
                } header: {
                    Text("创作").foregroundStyle(Palette.secondary)
                }
                .groupedRow()
                Section {
                    row(.plugins, Text("插件市场"), .plugins, "查找和安装插件")
                    quickLink(.installedPlugins, "已安装插件", "puzzlepiece.extension")
                    row(.connectors, Text("连接器"), .connectors, "GitHub、Notion 等服务和本机能力", status: connectorStatus)
                } header: {
                    Text("扩展智能体").foregroundStyle(Palette.secondary)
                }
                .groupedRow()
                Section {
                    quickLink(.schedules, "自动化", "clock.arrow.2.circlepath",
                              status: app.scheduleCount.map { String(localized: "\($0) 个") })
                    row(.phoneControl, Text("操控手机"), .phoneControl, "让智能体点按其他 App", status: phoneControl.state == .running ? String(localized: "运行中") : nil,
                        live: phoneControl.state == .running)
                    row(.remote, Text("远程控制"), .remote, "在手机上管电脑里的智能体", status: remoteStatus,
                        warns: app.remote.expired)
                    if WCSession.isSupported() {
                        row(.watch, Text("Apple Watch"), .watch, "在手腕上看会话、做确认",
                            status: watch == .installed ? String(localized: "已安装") : nil)
                    }
                } header: {
                    Text("设备").foregroundStyle(Palette.secondary)
                }
                .groupedRow()
                Section {
                    row(.shortcuts, Text("快捷指令"), .shortcuts, "用 Siri 和自动化打开 Bot、Mini App")
                    // Opens over everything: the mark of the links that leave the page.
                    Button { Haptics.tap(); app.webRequest = UUID() } label: {
                        label(Text("网页版"), .web, Text("插件自带的界面在这里打开")) { leavesArrow }
                    }
                    .foregroundStyle(Palette.ink)
                    row(.share, Text("分享 Fish Pocket"), .share, "海报、二维码或链接")
                } header: {
                    Text("其他").foregroundStyle(Palette.secondary)
                }
                .groupedRow()
                Section {
                    ForEach(SupportLink.all) { link in
                        Link(destination: link.url) {
                            label(Text(link.title), link.glyph, link.detail) { leavesArrow }
                        }
                        .foregroundStyle(Palette.ink)
                        .settlesRating(link.rates)
                    }
                } header: {
                    Text("反馈与社区").foregroundStyle(Palette.secondary)
                } footer: {
                    SupportLink.footer.foregroundStyle(Palette.secondary)
                }
                .groupedRow()
            }
            .groupedList()
            .tabEdgesSoftened()
            .refreshable { await app.account.refreshDetails() }
            .navigationTitle("探索")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .account: AccountPage().settingsStyle()
                case .models: ModelProvidersPage().settingsStyle()
                case .schedules: SchedulesView(openSession: openSession.map { open in { open($0) } }).settingsStyle()
                case .installedPlugins: PluginsView().settingsStyle()
                case .miniApps: MiniAppsPage()
                case .plugins: PluginStoreView()
                case .connectors: BotConnectorsPage().settingsStyle()
                case .phoneControl: PhoneControlView().environment(\.systemLists, true)
                case .remote: RemoteControlPage().environment(\.systemLists, true)
                case .watch: WatchSetupPage()
                case .shortcuts: ShortcutsGuidePage()
                case .share: ShareAppPage()
                case .settings: SettingsView(pushed: true)
                }
            }
            // The rows say whether iCTRL runs and whether the watch has the app; both change while
            // the user is in another app.
            .task { await phoneControl.refresh() }
            .task { await app.account.refreshDetails() }
            .onAppear { watch = WatchPairing.current; miniApps.refresh() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                watch = WatchPairing.current
                Task { await phoneControl.refresh() }
                if path.isEmpty { Task { await app.account.refreshDetails() } }
            }
        }
        .featurePage()
        .environment(\.systemLists, settingsLook)
        .onChange(of: path.isEmpty) { _, root in if root { settingsLook = false } }
        .inkTint()
    }

    /// The look first, 设置 in the next update (`settingsLook`).
    private func openSettings() {
        settingsLook = true
        // A second tap before it shows pushes nothing more.
        DispatchQueue.main.async { if path.isEmpty { path.append(.settings) } }
    }

    /// Once signed in: computers online, offline, or the sign-in to renew. Before, the line under
    /// the name already says what it is for.
    private var remoteStatus: String? {
        let remote = app.remote
        return remote.signedIn || remote.expired ? DrawerView.remoteControlNote(remote) : nil
    }

    private var connectorStatus: String? {
        let team = app.botTeam
        let connected = team.status == .ready ? team.connectors.filter { $0["state"].string == "ready" }.count : 0
        return connected > 0 ? String(localized: "\(connected) 个已连接") : nil
    }

    private func row(_ route: Route, _ title: Text, _ icon: ExploreGlyph.Kind, _ detail: LocalizedStringKey,
                     status: String? = nil, warns: Bool = false, live: Bool = false) -> some View {
        NavigationLink(value: route) {
            label(title, icon, Text(detail)) {
                if let status {
                    HStack(spacing: 5) {
                        if live { Circle().fill(Palette.running).frame(width: 7, height: 7) }
                        Text(status)
                    }
                    .font(.footnote)
                    .foregroundStyle(warns ? Palette.waiting : Palette.secondary)
                    .lineLimit(1)
                }
            }
        }
    }

    private func quickLink(_ route: Route, _ title: LocalizedStringKey, _ icon: String, status: String? = nil) -> some View {
        NavigationLink(value: route) {
            LabeledContent {
                if let status { Text(status).foregroundStyle(Palette.secondary) }
            } label: {
                Label(title, systemImage: icon)
            }
            .padding(.vertical, 4)
        }
    }

    /// The mark of the rows that leave the page: the web version and the links at the foot.
    private var leavesArrow: some View {
        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.faint)
    }

    /// The entry's drawn icon, the name and a line on what it is for, and what it says on the right.
    private func label(_ title: Text, _ icon: ExploreGlyph.Kind, _ detail: Text,
                       @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 14) {
            ExploreGlyph(kind: icon)
            VStack(alignment: .leading, spacing: 3) {
                title.font(.body).foregroundStyle(Palette.ink)
                detail.font(.footnote).foregroundStyle(Palette.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            // The status whole first: cut short it says nothing ("1…" for one service connected),
            // and the line under the name has a second row to go to.
            trailing().layoutPriority(1)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// A snapshot of the official account. AccountPage owns sign-in and wallet actions.
private struct ExploreAccountRow: View {
    let account: AccountModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        layout {
            AccountAvatar(url: avatarURL, size: 46)
            VStack(alignment: .leading, spacing: 5) {
                Text("DeepSeek 账号")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(accountStatus)
                    .font(.subheadline)
                    .foregroundStyle(Palette.secondary)
                if account.signedIn { balances }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var avatarURL: URL? {
        guard account.signedIn else { return nil }
        return account.profileValue?["avatarUrl"].string.flatMap(URL.init(string:))
    }

    private var accountStatus: String {
        if account.signedIn {
            if let name = account.displayName, !name.isEmpty { return name }
            return account.profile == nil ? String(localized: "账号资料加载中…") : String(localized: "已登录")
        }
        if account.attemptActive { return String(localized: "正在登录…") }
        if account.streamFailed { return String(localized: "账号状态暂不可用") }
        if account.view == nil { return String(localized: "加载中…") }
        return String(localized: "未登录")
    }

    @ViewBuilder
    private var balances: some View {
        if let amount = formatted(account.wallets ?? []) {
            Text("充值余额 \(amount)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.ink)
        } else {
            Text(account.balance == nil ? String(localized: "余额加载中…") : String(localized: "余额暂不可用"))
                .font(.footnote)
                .foregroundStyle(Palette.secondary)
        }
        if let amount = formatted(account.bonusWallets) {
            Text("赠金余额 \(amount)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Palette.secondary)
        }
    }

    private func formatted(_ wallets: [JSON]) -> String? {
        let amounts = wallets.compactMap { wallet -> String? in
            guard let amount = wallet["balance"].string, !amount.isEmpty else { return nil }
            return formatBalance(amount, currency: wallet["currency"].string)
        }
        return amounts.isEmpty ? nil : amounts.joined(separator: " + ")
    }
}
