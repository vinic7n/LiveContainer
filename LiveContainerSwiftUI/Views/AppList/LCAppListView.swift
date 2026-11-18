//
//  ContentView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Combine
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private struct LCAppGridToolbarVisibility: ViewModifier {
    let isGrid: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .toolbar(isGrid ? .hidden : .visible, for: .navigationBar)
        } else {
            content
        }
    }
}

class SearchContext: ObservableObject {
    @Published var query: String = ""
    @Published var debouncedQuery: String = ""
    @Published var isTyping: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        $query
            .debounce(for: .seconds(0.2), scheduler: DispatchQueue.main)
            .sink { [weak self] value in
                self?.isTyping = true
                self?.debouncedQuery = value
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self?.isTyping = false
                }
            }
            .store(in: &cancellables)
    }
}

struct AppReplaceOption : Hashable {
    var isReplace: Bool
    var nameOfFolderToInstall: String
    var appToReplace: LCAppModel?
}

struct LCAppListView : View, LCAppBannerDelegate, LCAppModelDelegate {
    @State var didAppear = false
    // ipa choosing stuff
    @State var choosingIPA = false
    @State var errorShow = false
    @State var errorInfo = ""
    
    // ipa installing stuff
    @State var installprogressVisible = false
    @State var installProgressPercentage : Float = 0.0
    @State var installObserver : NSKeyValueObservation?
    
    @State var installOptions: [AppReplaceOption]
    @StateObject var installReplaceAlert = AlertHelper<AppReplaceOption>()
    
    @State var webViewOpened = false
    @State var webViewURL : URL = URL(string: "about:blank")!
    @StateObject private var webViewUrlInput = InputHelper()
    
    @EnvironmentObject var downloadHelper: DownloadHelper
    @StateObject private var installUrlInput = InputHelper()
    
    @State private var jitLog = ""
    @StateObject private var jitAlert = YesNoHelper()
    
    @StateObject private var runWhenMultitaskAlert = YesNoHelper()
    
    @StateObject private var generatedIconStyleSelector = AlertHelper<GeneratedIconStyle>()
    
    @State var safariViewOpened = false
    @State var safariViewURL = URL(string: "https://google.com")!
    
    @State private var navigateTo : AnyView?
    @State private var isNavigationActive = false
    
    @State private var helpPresent = false
    
    @State private var customSortViewPresent = false
    
    @EnvironmentObject private var sharedModel : SharedModel
    @EnvironmentObject private var sharedAppSortManager : LCAppSortManager
    
    @AppStorage("LCMultitaskMode", store: LCUtils.appGroupUserDefault) var multitaskMode: MultitaskMode = .virtualWindow
    @AppStorage("LCAppListGrid", store: LCUtils.appGroupUserDefault) private var appListGrid = false
    @AppStorage("LCHomeScreenLargeIcons", store: LCUtils.appGroupUserDefault) private var homeScreenLargeIcons = false
    @AppStorage("LCHomeScreenShowClockWidget", store: LCUtils.appGroupUserDefault) private var showHomeClockWidget = false
    @AppStorage("LCHomeScreenClockWidgetRows", store: LCUtils.appGroupUserDefault) private var homeClockWidgetRows = 2
    @AppStorage("LCHomeScreenClockWidgetIndex", store: LCUtils.appGroupUserDefault) private var homeClockWidgetIndex = 0
    @State private var draggedHomeAppID: String?
    @State private var homePageIndex = 0
    @State private var isHomeSearchVisible = false
    @State private var homeAppPendingUninstall: LCAppModel?
    @StateObject private var homeUninstallConfirmation = YesNoHelper()
    @StateObject private var homeDeleteDataConfirmation = YesNoHelper()
    
    @State private var isViewAppeared = false
    
    @ObservedObject var searchContext: SearchContext = SearchContext()
    var sortedApps: [LCAppModel] {
        sharedAppSortManager.getSortedApps(
            sharedModel.apps,
            sortType: sharedAppSortManager.appSortType,
            customSortOrder: sharedAppSortManager.customSortOrder
        )
    }
    
    var sortedHiddenApps: [LCAppModel] {
        sharedAppSortManager.getSortedApps(
            sharedModel.hiddenApps,
            sortType: sharedAppSortManager.appSortType,
            customSortOrder: sharedAppSortManager.customSortOrder
        )
    }
    
    var filteredApps: [LCAppModel] {
        let apps = sortedApps
        if searchContext.debouncedQuery.isEmpty {
            return apps
        } else {
            return apps.filter { app in
                app.appInfo.displayName().localizedCaseInsensitiveContains(searchContext.debouncedQuery) ||
                app.appInfo.bundleIdentifier()!.localizedCaseInsensitiveContains(searchContext.debouncedQuery)
            }
        }
    }
    
    var filteredHiddenApps: [LCAppModel] {
        let apps = sortedHiddenApps
        if searchContext.debouncedQuery.isEmpty || !sharedModel.isHiddenAppUnlocked {
            return apps
        } else {
            return apps.filter { app in
                app.appInfo.displayName().localizedCaseInsensitiveContains(searchContext.debouncedQuery) ||
                app.appInfo.bundleIdentifier()!.localizedCaseInsensitiveContains(searchContext.debouncedQuery)
            }
        }
    }
    
    init() {
        _installOptions = State(initialValue: [])
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                NavigationLink(
                    destination: navigateTo,
                    isActive: $isNavigationActive,
                    label: {
                        EmptyView()
                })
                .hidden()

                appBannerCollection(filteredApps, homeScreen: true)
                    .padding(.horizontal, appListGrid ? 8 : 0)
                    .padding(.top, appListGrid ? 24 : 0)

                VStack {
                    if LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding") {
                        if sharedModel.isHiddenAppUnlocked {
                            VStack {
                                HStack {
                                    Text("lc.appList.hiddenApps".loc)
                                        .font(.system(.title2).bold())
                                    Spacer()
                                }
                                appBannerCollection(filteredHiddenApps)
                                
                            }
                            .padding()
                            .transition(.opacity)
                            .animation(searchContext.isTyping ? nil : .easeInOut, value: filteredHiddenApps)
                            
                            if sharedModel.hiddenApps.count == 0 {
                                Text("lc.appList.hideAppTip".loc)
                                    .foregroundStyle(.gray)
                            }
                        }
                    } else if sharedModel.hiddenApps.count > 0 {
                        VStack {
                            HStack {
                                Text("lc.appList.hiddenApps".loc)
                                    .font(.system(.title2).bold())
                                Spacer()
                            }
                            if appListGrid {
                                if sharedModel.isHiddenAppUnlocked {
                                    appBannerCollection(filteredHiddenApps)
                                } else {
                                    LazyVGrid(columns: gridColumns, spacing: 10) {
                                        ForEach(filteredHiddenApps, id: \.self) { _ in
                                            LCAppSkeletonBanner()
                                                .frame(height: LCAppBannerRootView.gridBannerHeight)
                                        }
                                    }
                                    .onTapGesture { Task { await authenticateUser() } }
                                }
                            } else {
                                ForEach(filteredHiddenApps, id: \.self) { app in
                                    if sharedModel.isHiddenAppUnlocked {
                                        LCAppBanner(appModel: app, delegate: self)
                                    } else {
                                        LCAppSkeletonBanner()
                                    }
                                }
                                .animation(.easeInOut, value: sharedModel.isHiddenAppUnlocked)
                                .onTapGesture {
                                    Task { await authenticateUser() }
                                }
                            }
                        }
                        .padding()
                        .animation(searchContext.isTyping ? nil : .easeInOut, value: filteredHiddenApps)
                    }

                    let appCount = sharedModel.isHiddenAppUnlocked ? filteredApps.count + filteredHiddenApps.count : filteredApps.count
                    if !appListGrid {
                        Text(appCount > 0 || searchContext.debouncedQuery != "" ? "lc.appList.appCounter %lld".localizeWithFormat(appCount) : (sharedModel.multiLCStatus == 2 ? "lc.appList.convertToSharedToShowInLC2".loc : "lc.appList.installTip".loc))
                            .padding(.horizontal)
                            .foregroundStyle(.gray)
                            .animation(searchContext.isTyping ? nil : .easeInOut, value: appCount)
                            .onTapGesture(count: 3) {
                                Task { await authenticateUser() }
                            }
                    }
                }.animation(searchContext.isTyping ? nil : .easeInOut, value: LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding"))

                if sharedModel.multiLCStatus == 2 {
                    Text("lc.appList.manageInPrimaryTip".loc).foregroundStyle(.gray).padding()
                }

            }
            .background {
                LCHomeScreenWallpaperView()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if appListGrid {
                    homeScreenFooter
                }
            }
            .navigationBarProgressBar(show:$installprogressVisible, progress: $installProgressPercentage)
            .coordinateSpace(name: "scroll")
            .onAppear {
                if !didAppear {
                    onAppear()
                }
            }
            .onChange(of: searchContext.query) { _ in homePageIndex = 0 }
            .onChange(of: appListGrid) { _ in homePageIndex = 0 }
            .onChange(of: showHomeClockWidget) { _ in homePageIndex = 0 }
            .onChange(of: homeClockWidgetRows) { _ in homePageIndex = 0 }
            
            .navigationTitle("lc.appList.myApps".loc)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if sharedModel.multiLCStatus != 2 {
                        if !installprogressVisible {
                            Menu {
                                
                                Button("lc.appList.installFromIpa".loc, systemImage: "doc.badge.plus", action: {
                                    choosingIPA = true
                                })
                                Button("lc.appList.installFromUrl".loc, systemImage: "link.badge.plus", action: {
                                    Task{ await startInstallFromUrl() }
                                })
                            } label: {
                                Label("add", systemImage: "plus")
                            }
                            
                        } else {
                            ProgressView().progressViewStyle(.circular).padding(.horizontal, 8)
                        }
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if !UserDefaults.sideStoreExist() {
                        Button("Help", systemImage: "questionmark") {
                            helpPresent = true
                        }
                    }
                    

                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("lc.appList.openLink".loc, systemImage: "link", action: {
                        Task { await onOpenWebViewTapped() }
                    })
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by", selection: $sharedAppSortManager.appSortType) {
                            ForEach(AppSortType.allCases, id: \.self) { sortType in
                                Label(sortType.displayName, systemImage: sortType.systemImage)
                                    .tag(sortType)
                            }
                        }
                        .onChange(of: sharedAppSortManager.appSortType) { newValue in
                            if sharedAppSortManager.appSortType == .custom {
                                customSortViewPresent = true
                            }
                        }
                        if sharedAppSortManager.appSortType == .custom {
                            Divider()
                            
                            Button {
                                customSortViewPresent = true
                            } label: {
                                Label("lc.appList.sort.customManage".loc, systemImage: "slider.horizontal.3")
                            }
                        }
                    } label: {
                        Label("Sort by", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .modifier(LCAppGridToolbarVisibility(isGrid: appListGrid))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .background(Color.clear)
        .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
        } message: {
            Text(errorInfo)
        }
        .alert("lc.appBanner.confirmUninstallTitle".loc, isPresented: $homeUninstallConfirmation.show) {
            Button("lc.appBanner.uninstall".loc, role: .destructive) {
                homeUninstallConfirmation.close(result: true)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                homeUninstallConfirmation.close(result: false)
            }
        } message: {
            Text("lc.appBanner.confirmUninstallMsg %@".localizeWithFormat(homeAppPendingUninstall?.appInfo.displayName() ?? ""))
        }
        .alert("lc.appBanner.deleteDataTitle".loc, isPresented: $homeDeleteDataConfirmation.show) {
            Button("lc.common.delete".loc, role: .destructive) {
                homeDeleteDataConfirmation.close(result: true)
            }
            Button("lc.common.no".loc, role: .cancel) {
                homeDeleteDataConfirmation.close(result: false)
            }
        } message: {
            Text("lc.appBanner.deleteDataMsg %@".localizeWithFormat(homeAppPendingUninstall?.appInfo.displayName() ?? ""))
        }
        .betterFileImporter(isPresented: $choosingIPA, types: [.ipa, .tipa], multiple: false, callback: { fileUrls in
            Task { await startInstallApp(fileUrls[0]) }
        }, onDismiss: {
            choosingIPA = false
        })
        .alert("lc.appList.installation".loc, isPresented: $installReplaceAlert.show) {
            ForEach(installOptions, id: \.self) { installOption in
                Button(role: installOption.isReplace ? .destructive : nil, action: {
                    installReplaceAlert.close(result: installOption)
                }, label: {
                    Text(installOption.isReplace ? installOption.nameOfFolderToInstall : "lc.appList.installAsNew".loc)
                })
            
            }
            Button(role: .cancel, action: {
                installReplaceAlert.close(result: nil)
            }, label: {
                Text("lc.appList.abortInstallation".loc)
            })
        } message: {
            Text("lc.appList.installReplaceTip".loc)
        }
        .alert("lc.webView.runApp".loc, isPresented: $runWhenMultitaskAlert.show) {
            Button(role: .destructive) {
                runWhenMultitaskAlert.close(result: true)
            } label: {
                Text("lc.common.continue".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                runWhenMultitaskAlert.close(result: false)
            }
        } message: {
            Text("lc.appBanner.confirmRunWhenMultitasking".loc)
        }
        .alert("lc.appList.generatedIconStyleSelector.title".loc, isPresented:$generatedIconStyleSelector.show) {
            Button {
                generatedIconStyleSelector.close(result: .Light)
            } label: {
                Text("lc.appList.generatedIconStyleSelector.light".loc)
            }
            Button {
                generatedIconStyleSelector.close(result: .Dark)
            } label: {
                Text("lc.appList.generatedIconStyleSelector.dark".loc)
            }
            Button {
                generatedIconStyleSelector.close(result: .Original)
            } label: {
                Text("lc.appList.generatedIconStyleSelector.original".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                generatedIconStyleSelector.close(result: nil)
            }
        }
        .textFieldAlert(
            isPresented: $webViewUrlInput.show,
            title:  "lc.appList.enterUrlTip".loc,
            text: $webViewUrlInput.initVal,
            placeholder: "scheme://",
            action: { newText in
                webViewUrlInput.close(result: newText)
            },
            actionCancel: {_ in
                webViewUrlInput.close(result: nil)
            }
        )
        .textFieldAlert(
            isPresented: $installUrlInput.show,
            title:  "lc.appList.installUrlInputTip".loc,
            text: $installUrlInput.initVal,
            placeholder: "https://",
            action: { newText in
                installUrlInput.close(result: newText)
            },
            actionCancel: {_ in
                installUrlInput.close(result: nil)
            }
        )
        .sheet(isPresented: $jitAlert.show, onDismiss: {
            jitAlert.close(result: false)
        }) {
            JITEnablingModal
        }
        .onChange(of: jitAlert.show) { newValue in
            sharedModel.isJITModalOpen = newValue
        }
        .fullScreenCover(isPresented: $webViewOpened) {
            LCWebView(url: $webViewURL, isPresent: $webViewOpened, itmsServicesHandler: { urlStr in
                await installFromPlist(urlStr: urlStr)
            })
        }
        .fullScreenCover(isPresented: $safariViewOpened) {
            SafariView(url: $safariViewURL)
        }
        .sheet(isPresented: $helpPresent) {
            LCHelpView(isPresent: $helpPresent)
        }
        .sheet(isPresented: $customSortViewPresent) {
            LCCustomSortView()
        }
        .onAppear() {
            if !isViewAppeared {
                if let webpageUrlStr = UserDefaults.standard.string(forKey: "webPageToOpen") {
                    Task { await openWebView(urlString: webpageUrlStr) }
                    UserDefaults.standard.set(nil, forKey: "webPageToOpen")
                }
                
                guard sharedModel.selectedTab == .apps, let link = sharedModel.deepLink else { return }
                sharedModel.deepLink = nil
                handleURL(url: link)
                isViewAppeared = true
            }
        }
        .onChange(of: sharedModel.deepLink) { link in
            guard sharedModel.selectedTab == .apps, let link else { return }
            sharedModel.deepLink = nil
            handleURL(url: link)
        }
        .onDrop(of: [.url], isTargeted: nil) { providers in
            guard !appListGrid else { return false }
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url else { return }
                Task {
                    guard let urlToOpen = await webViewUrlInput.open(initVal: url.absoluteString), urlToOpen != "" else {
                        return
                    }
                    await openWebView(urlString: urlToOpen)
                }
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.InstallAppNotification)) { obj in
            if let obj2 = obj.object as? [String: Any], let installUrl = obj2["url"] as? URL {
                Task { await installFromUrl(urlStr: installUrl.absoluteString) }
            }
        }
        .searchable(text: $searchContext.query)

    }

    private var homePageCount: Int {
        homePages.count
    }

    private var homePages: [[LCAppModel]] {
        guard !filteredApps.isEmpty else { return [[]] }
        let hasWidget = showHomeClockWidget && searchContext.debouncedQuery.isEmpty
        let firstPageCapacity = max(1, 24 - (hasWidget ? 2 * homeClockWidgetRows : 0))
        let firstPage = Array(filteredApps.prefix(firstPageCapacity))
        let remaining = Array(filteredApps.dropFirst(firstPageCapacity))
        let laterPages = stride(from: 0, to: remaining.count, by: 24).map { start in
            Array(remaining.dropFirst(start).prefix(24))
        }
        return [firstPage] + laterPages
    }

    private var homeAppTileHeight: CGFloat {
        homeScreenLargeIcons ? 86 : 100
    }

    private var homePageHeight: CGFloat {
        let page = min(max(homePageIndex, 0), homePages.count - 1)
        let layout = homeScreenGridLayout(
            for: homePages[page],
            includesWidget: page == 0 && showHomeClockWidget && searchContext.debouncedQuery.isEmpty
        )
        return CGFloat(layout.rowCount) * homeAppTileHeight + CGFloat(max(0, layout.rowCount - 1)) * 2 + 12
    }

    @ViewBuilder
    private var homeScreenFooter: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(0..<homePageCount, id: \.self) { page in
                    Circle()
                        .fill(page == homePageIndex ? Color.white : Color.white.opacity(0.45))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityLabel("Home screen page \(homePageIndex + 1) of \(homePageCount)")

            Group {
                if isHomeSearchVisible {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search", text: $searchContext.query)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            searchContext.query = ""
                            isHomeSearchVisible = false
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 38)
                    .background(.ultraThinMaterial, in: Capsule())
                } else {
                    Button {
                        isHomeSearchVisible = true
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 38)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 300)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func appBannerCollection(_ apps: [LCAppModel], homeScreen: Bool = false) -> some View {
        if appListGrid {
            if homeScreen {
                let pages = homePages
                if apps.isEmpty && !showHomeClockWidget {
                    Text(sharedModel.multiLCStatus == 2 ? "lc.appList.convertToSharedToShowInLC2".loc : "lc.appList.installTip".loc)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(height: homePageHeight)
                } else {
                    TabView(selection: $homePageIndex) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { pageIndex, pageApps in
                            homeScreenPage(pageApps, pageIndex: pageIndex)
                            .tag(pageIndex)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: homePageHeight)
                    .animation(searchContext.isTyping ? nil : .easeInOut, value: apps)
                }
            } else {
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(apps, id: \.self) { app in
                        LCAppBanner(appModel: app, delegate: self, isGrid: true)
                            .transition(.scale)
                    }
                }
                .animation(searchContext.isTyping ? nil : .easeInOut, value: apps)
            }
        } else {
            LazyVStack {
                ForEach(apps, id: \.self) { app in
                    LCAppBanner(appModel: app, delegate: self)
                        .transition(.scale)
                }
            }
            .animation(searchContext.isTyping ? nil : .easeInOut, value: apps)
        }
    }

    private func homeAppTile(_ app: LCAppModel, pageApps: [LCAppModel]) -> some View {
        HomeScreenAppIcon(app: app, large: homeScreenLargeIcons) {
            guard let relativePath = app.appInfo.relativeBundlePath else { return }
            Task {
                await launchAppWithBundleId(
                    bundleId: relativePath,
                    container: app.uiSelectedContainer?.folderName
                )
            }
        }
            .contextMenu {
                if #available(iOS 16.0, *) {
                    Button {
                        Task {
                            do {
                                if app.appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
                                    guard try await LCUtils.authenticateUser() else { return }
                                }
                                try await app.runApp(multitask: true)
                            } catch {
                                errorInfo = error.localizedDescription
                                errorShow = true
                            }
                        }
                    } label: {
                        Label("lc.appBanner.multitask".loc, systemImage: "macwindow.badge.plus")
                    }
                }

                Menu("lc.appBanner.addToHomeScreen".loc) {
                    Button("lc.appBanner.copyLaunchUrl".loc, systemImage: "link") {
                        copyHomeAppLaunchURL(app)
                    }
                    Button("lc.appBanner.createAppClip".loc, systemImage: "appclip") {
                        Task { await createHomeAppClip(app) }
                    }
                }

                Button {
                    openNavigationView(view: AnyView(LCAppSettingsView(model: app)))
                } label: {
                    Label("lc.tabView.settings".loc, systemImage: "gear")
                }

                if !app.uiIsShared {
                    Button(role: .destructive) {
                        Task { await uninstallHomeApp(app) }
                    } label: {
                        Label("lc.appBanner.uninstall".loc, systemImage: "trash")
                    }
                }
            }
            .onDrag {
                guard let appID = sharedAppSortManager.getUniqueIdentifier(for: app) else {
                    return NSItemProvider()
                }

                draggedHomeAppID = appID
                let provider = NSItemProvider()
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.plainText.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(Data(appID.utf8), nil)
                    return nil
                }
                return provider
            }
            .onDrop(of: [UTType.plainText], delegate: HomeAppReorderDropDelegate(
                app: app,
                apps: pageApps,
                manager: sharedAppSortManager,
                draggedAppID: $draggedHomeAppID,
                widgetIndex: $homeClockWidgetIndex
            ))
            .transition(.scale)
    }

    private func copyHomeAppLaunchURL(_ app: LCAppModel) {
        guard let relativeBundlePath = app.appInfo.relativeBundlePath else { return }
        if let folderName = app.uiSelectedContainer?.folderName {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(relativeBundlePath)&container-folder-name=\(folderName)"
        } else {
            UIPasteboard.general.string = "livecontainer://livecontainer-launch?bundle-name=\(relativeBundlePath)"
        }
    }

    private func createHomeAppClip(_ app: LCAppModel) async {
        guard let style = await generatedIconStyleSelector.open() else { return }
        do {
            guard let profile = app.appInfo.generateWebClipConfig(
                withContainerId: app.uiSelectedContainer?.folderName,
                iconStyle: style
            ) else {
                throw CocoaError(.propertyListWriteInvalid)
            }
            let data = try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
            installMdm(data: data)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    private func uninstallHomeApp(_ app: LCAppModel) async {
        homeAppPendingUninstall = app
        guard await homeUninstallConfirmation.open() == true else {
            homeAppPendingUninstall = nil
            return
        }
        guard let bundlePath = app.appInfo.bundlePath() else {
            homeAppPendingUninstall = nil
            return
        }

        let containers = app.appInfo.containers
        var removeData = false
        if !containers.isEmpty {
            removeData = await homeDeleteDataConfirmation.open() == true
        }
        do {
            try FileManager.default.removeItem(atPath: bundlePath)
            removeApp(app: app)
            if removeData {
                for container in containers {
                    try FileManager.default.removeItem(at: LCPath.dataPath.appendingPathComponent(container.folderName))
                    LCUtils.removeAppKeychain(dataUUID: container.folderName)
                    sharedModel.appDataFolderNames.removeAll { $0 == container.folderName }
                }
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        homeAppPendingUninstall = nil
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }

    private func homeClockWidgetTile(apps: [LCAppModel]) -> some View {
        let widget = HomeScreenClockWidget(rows: homeClockWidgetRows, tileHeight: homeAppTileHeight)
        return widget
            .onDrag {
                draggedHomeAppID = homeClockWidgetDragID
                let provider = NSItemProvider()
                provider.registerDataRepresentation(
                    forTypeIdentifier: UTType.plainText.identifier,
                    visibility: .ownProcess
                ) { completion in
                    completion(Data(homeClockWidgetDragID.utf8), nil)
                    return nil
                }
                return provider
            }
            .onDrop(of: [UTType.plainText], delegate: HomeClockWidgetReorderDropDelegate(
                apps: apps,
                manager: sharedAppSortManager,
                draggedAppID: $draggedHomeAppID,
                widgetIndex: $homeClockWidgetIndex
            ))
    }

    private func homeScreenPage(_ apps: [LCAppModel], pageIndex: Int) -> some View {
        let layout = homeScreenGridLayout(
            for: apps,
            includesWidget: pageIndex == 0 && showHomeClockWidget && searchContext.debouncedQuery.isEmpty
        )

        return GeometryReader { geometry in
            let horizontalSpacing: CGFloat = 8
            let tileWidth = (geometry.size.width - horizontalSpacing * 3) / 4
            ZStack(alignment: .topLeading) {
                ForEach(Array(apps.enumerated()), id: \.element) { index, app in
                    if let cell = layout.appCells[index] {
                        homeAppTile(app, pageApps: sortedApps)
                            .frame(width: tileWidth, height: homeAppTileHeight)
                            .position(
                                x: CGFloat(cell.column) * (tileWidth + horizontalSpacing) + tileWidth / 2,
                                y: CGFloat(cell.row) * (homeAppTileHeight + 2) + homeAppTileHeight / 2
                            )
                    }
                }

                if let widgetCell = layout.widgetCell {
                    homeClockWidgetTile(apps: sortedApps)
                        .frame(
                            width: tileWidth * 2 + horizontalSpacing,
                            height: CGFloat(homeClockWidgetRows) * homeAppTileHeight + CGFloat(max(0, homeClockWidgetRows - 1)) * 2
                        )
                        .position(
                            x: CGFloat(widgetCell.column) * (tileWidth + horizontalSpacing) + tileWidth + horizontalSpacing / 2,
                            y: CGFloat(widgetCell.row) * (homeAppTileHeight + 2)
                                + (CGFloat(homeClockWidgetRows) * homeAppTileHeight + CGFloat(max(0, homeClockWidgetRows - 1)) * 2) / 2
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: CGFloat(layout.rowCount) * homeAppTileHeight + CGFloat(max(0, layout.rowCount - 1)) * 2)
    }

    private func homeScreenGridLayout(for apps: [LCAppModel], includesWidget: Bool) -> HomeScreenGridLayout {
        var occupiedCells = Set<Int>()
        var appCells: [Int: HomeScreenGridCell] = [:]
        var widgetCell: HomeScreenGridCell?
        var cursor = 0
        let insertionIndex = min(max(homeClockWidgetIndex, 0), apps.count)
        let widgetRows = min(max(homeClockWidgetRows, 2), 4)

        for appIndex in 0...apps.count {
            if includesWidget && appIndex == insertionIndex {
                while true {
                    let row = cursor / 4
                    let column = cursor % 4
                    if column <= 2 {
                        let widgetSlots = (0..<widgetRows).flatMap { rowOffset in
                            (0..<2).map { columnOffset in (row + rowOffset) * 4 + column + columnOffset }
                        }
                        if widgetSlots.allSatisfy({ !occupiedCells.contains($0) }) {
                            widgetCell = HomeScreenGridCell(row: row, column: column)
                            occupiedCells.formUnion(widgetSlots)
                            cursor += 1
                            break
                        }
                    }
                    cursor += 1
                }
            }

            guard appIndex < apps.count else { continue }
            while occupiedCells.contains(cursor) { cursor += 1 }
            appCells[appIndex] = HomeScreenGridCell(row: cursor / 4, column: cursor % 4)
            occupiedCells.insert(cursor)
            cursor += 1
        }

        let rowCount = max(1, (occupiedCells.map { $0 / 4 }.max() ?? 0) + 1)
        return HomeScreenGridLayout(appCells: appCells, widgetCell: widgetCell, rowCount: rowCount)
    }

    var JITEnablingModal : some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    Text("lc.appBanner.waitForJitMsg".loc)
                        .padding(.vertical)
                        .id(0)
                    
                    HStack {
                        Text(jitLog)
                            .font(.system(size: 12).monospaced())
                            .fixedSize(horizontal: false, vertical: false)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .onAppear {
                    proxy.scrollTo(0)
                }
            }
            .navigationTitle("lc.appBanner.waitForJitTitle".loc)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("lc.common.cancel".loc, role: .cancel) {
                        jitAlert.close(result: false)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        jitAlert.close(result: true)
                    } label: {
                        Text("lc.appBanner.jitLaunchNow".loc)
                    }
                }
            }
        }
    }
    
    func onOpenWebViewTapped() async {
        guard let urlToOpen = await webViewUrlInput.open(), urlToOpen != "" else {
            return
        }
        await openWebView(urlString: urlToOpen)
        
    }
    func onAppear() {
        for app in sharedModel.apps {
            app.delegate = self
        }
        for app in sharedModel.hiddenApps {
            app.delegate = self
        }
        didAppear = true
    }
    
    
    func openWebView(urlString: String) async {
        guard var urlToOpen = URLComponents(string: urlString), urlToOpen.url != nil else {
            errorInfo = "lc.appList.urlInvalidError".loc
            errorShow = true
            return
        }
        if urlToOpen.scheme == nil || urlToOpen.scheme! == "" {
            urlToOpen.scheme = "https"
        }
        
        if urlToOpen.scheme?.lowercased() == "itms-services" {
            await installFromPlist(urlStr: urlString)
            return
        }
        
        if urlToOpen.scheme != "https" && urlToOpen.scheme != "http" {
            var appToLaunch : LCAppModel? = nil
            var appListsToConsider = [sharedModel.apps]
            if sharedModel.isHiddenAppUnlocked || !LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding") {
                appListsToConsider.append(sharedModel.hiddenApps)
            }
            appLoop:
            for appList in appListsToConsider {
                for app in appList {
                    if let schemes = app.appInfo.urlSchemes() {
                        for scheme in schemes {
                            if let scheme = scheme as? String, scheme == urlToOpen.scheme {
                                appToLaunch = app
                                break appLoop
                            }
                        }
                    }
                }
            }


            guard let appToLaunch = appToLaunch else {
                errorInfo = "lc.appList.schemeCannotOpenError %@".localizeWithFormat(urlToOpen.scheme!)
                errorShow = true
                return
            }
            
            if appToLaunch.appInfo.isLocked && !sharedModel.isHiddenAppUnlocked {
                do {
                    if !(try await LCUtils.authenticateUser()) {
                        return
                    }
                } catch {
                    errorInfo = error.localizedDescription
                    errorShow = true
                    return
                }
            }
            
            do {
                try await appToLaunch.runApp(urlStr: urlToOpen.url!.absoluteString)
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
            
            return
        }
        webViewURL = urlToOpen.url!
        if webViewOpened {
            webViewOpened = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                webViewOpened = true
            })
        } else {
            webViewOpened = true
        }
    }


    
    func startInstallApp(_ fileUrl:URL) async {
        do {
            self.installprogressVisible = true
            try await installIpaFile(fileUrl)
            try FileManager.default.removeItem(at: fileUrl)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            self.installprogressVisible = false
        }
    }
    
    nonisolated func decompress(_ path: String, _ destination: String ,_ progress: Progress) async -> Int32 {
        extract(path, destination, progress)
    }
    
    func installIpaFile(_ url:URL) async throws {
        let fm = FileManager()
        
        let installProgress = Progress.discreteProgress(totalUnitCount: 100)
        self.installProgressPercentage = 0.0
        self.installObserver = installProgress.observe(\.fractionCompleted) { p, v in
            DispatchQueue.main.async {
                self.installProgressPercentage = Float(p.fractionCompleted)
            }
        }
        let decompressProgress = Progress.discreteProgress(totalUnitCount: 100)
        installProgress.addChild(decompressProgress, withPendingUnitCount: 80)
        let payloadPath = fm.temporaryDirectory.appendingPathComponent("Payload")
        if fm.fileExists(atPath: payloadPath.path) {
            try fm.removeItem(at: payloadPath)
        }
        
        // decompress
        guard await decompress(url.path, fm.temporaryDirectory.path, decompressProgress) == 0 else {
            throw "lc.appList.urlFileIsNotIpaError".loc
        }

        let payloadContents = try fm.contentsOfDirectory(atPath: payloadPath.path)
        var appBundleName : String? = nil
        for fileName in payloadContents {
            if fileName.hasSuffix(".app") {
                appBundleName = fileName
                break
            }
        }
        guard let appBundleName = appBundleName else {
            throw "lc.appList.bundleNotFondError".loc
        }

        let appFolderPath = payloadPath.appendingPathComponent(appBundleName)
        
        guard let newAppInfo = LCAppInfo(bundlePath: appFolderPath.path) else {
            throw "lc.appList.infoPlistCannotReadError".loc
        }

        var appRelativePath = "\(newAppInfo.bundleIdentifier()!.sanitizeNonACSII()).app"
        var outputFolder = LCPath.bundlePath.appendingPathComponent(appRelativePath)
        var appToReplace : LCAppModel? = nil
        // Folder exist! show alert for user to choose which bundle to replace
        var sameBundleIdApp = sharedModel.apps.filter { app in
            return app.appInfo.bundleIdentifier()! == newAppInfo.bundleIdentifier()
        }
        if sameBundleIdApp.count == 0 {
            sameBundleIdApp = sharedModel.hiddenApps.filter { app in
                return app.appInfo.bundleIdentifier()! == newAppInfo.bundleIdentifier()
            }
            
            // we found a hidden app, we need to authenticate before proceeding
            if sameBundleIdApp.count > 0 && !sharedModel.isHiddenAppUnlocked {
                do {
                    if !(try await LCUtils.authenticateUser()) {
                        self.installprogressVisible = false
                        return
                    }
                } catch {
                    errorInfo = error.localizedDescription
                    errorShow = true
                    self.installprogressVisible = false
                    return
                }
            }
            
        }
        
        if fm.fileExists(atPath: outputFolder.path) || sameBundleIdApp.count > 0 {
            appRelativePath = "\(newAppInfo.bundleIdentifier()!)_\(Int(CFAbsoluteTimeGetCurrent())).app"
            
            self.installOptions = [AppReplaceOption(isReplace: false, nameOfFolderToInstall: appRelativePath)]
            
            for app in sameBundleIdApp {
                self.installOptions.append(AppReplaceOption(isReplace: true, nameOfFolderToInstall: app.appInfo.relativeBundlePath, appToReplace: app))
            }

            guard let installOptionChosen = await installReplaceAlert.open() else {
                // user cancelled
                self.installprogressVisible = false
                try fm.removeItem(at: payloadPath)
                return
            }
            
            if let appToReplace = installOptionChosen.appToReplace, appToReplace.uiIsShared {
                outputFolder = LCPath.lcGroupBundlePath.appendingPathComponent(installOptionChosen.nameOfFolderToInstall)
            } else {
                outputFolder = LCPath.bundlePath.appendingPathComponent(installOptionChosen.nameOfFolderToInstall)
            }
            appRelativePath = installOptionChosen.nameOfFolderToInstall
            appToReplace = installOptionChosen.appToReplace
            if installOptionChosen.isReplace {
                try fm.removeItem(at: outputFolder)
            }
        }
        // Move it!
        try fm.moveItem(at: appFolderPath, to: outputFolder)
        let finalNewApp = LCAppInfo(bundlePath: outputFolder.path)
        finalNewApp?.relativeBundlePath = appRelativePath
        
        guard let finalNewApp else {
            errorInfo = "lc.appList.appInfoInitError".loc
            errorShow = true
            return
        }
        
        // patch and sign it
        var signError : String? = nil
        var signSuccess = false
        await withUnsafeContinuation({ c in
            if appToReplace?.uiDontSign ?? false || LCUtils.appGroupUserDefault.bool(forKey: "LCDontSignApp") {
                finalNewApp.dontSign = true
            }
            finalNewApp.patchExecAndSignIfNeed(completionHandler: { success, error in
                signError = error
                signSuccess = success
                c.resume()
            }, progressHandler: { signProgress in
                installProgress.addChild(signProgress!, withPendingUnitCount: 20)
            }, forceSign: false)
        })
        
        // we leave it unsigned even if signing failed
        if let signError {
            if signSuccess {
                errorInfo = "\("lc.appList.signSuccessWithError".loc)\n\n\(signError)"
            } else {
                errorInfo = signError.loc
            }
            errorShow = true
        }
        
        if let appToReplace {
            LCAppModel.copy(fromApp: appToReplace, toAppInfo: finalNewApp)
        } else {
            // enable SDK version spoof by defalut
            finalNewApp.spoofSDKVersion = true
        }
        finalNewApp.installationDate = Date.now
        
        DispatchQueue.main.async {
            if let appToReplace {
                let newAppModel = LCAppModel(appInfo: finalNewApp, delegate: self)
                
                if appToReplace.uiIsHidden {
                    sharedModel.hiddenApps.removeAll { $0 == appToReplace }
                    sharedModel.hiddenApps.append(newAppModel)
                } else {
                    sharedModel.apps.removeAll { $0 == appToReplace }
                    sharedModel.apps.append(newAppModel)
                }

            } else {
                let newAppModel = LCAppModel(appInfo: finalNewApp, delegate: self)
                sharedModel.apps.append(newAppModel)
                
                // add url schemes
                if let urlSchemes = finalNewApp.urlSchemes(), urlSchemes.count > 0 {
                    UserDefaults.lcShared().mutableArrayValue(forKey: "LCGuestURLSchemes")
                        .addObjects(from: urlSchemes as! [Any])
                }
            }

            self.installprogressVisible = false
        }
    }
    
    func startInstallFromUrl() async {
        guard let installUrlStr = await installUrlInput.open(), installUrlStr.count > 0 else {
            return
        }
        if let url = URL(string:installUrlStr), url.scheme?.lowercased() == "itms-services" {
            await installFromPlist(urlStr: installUrlStr)
            return
        }
        await installFromUrl(urlStr: installUrlStr)
    }
    
    func installFromPlist(urlStr: String) async {
        if self.installprogressVisible {
            return
        }
        
        if sharedModel.multiLCStatus == 2 {
            errorInfo = "lc.appList.manageInPrimaryTip".loc
            errorShow = true
            return
        }
        
        var plistUrlStr = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if plistUrlStr.lowercased().hasPrefix("itms-services://") {
            if let urlComponents = URLComponents(string: plistUrlStr),
               let queryItems = urlComponents.queryItems,
               let urlParam = queryItems.first(where: { $0.name == "url" })?.value {
                plistUrlStr = urlParam
            } else {
                errorInfo = "lc.appList.plistInvalidError".loc
                errorShow = true
                return
            }
        }
        
        guard let plistUrl = URL(string: plistUrlStr) else {
            errorInfo = "lc.appList.urlInvalidError".loc
            errorShow = true
            return
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: plistUrl)
            
            guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let items = plist["items"] as? [[String: Any]],
                  let firstItem = items.first,
                  let assets = firstItem["assets"] as? [[String: Any]] else {
                errorInfo = "lc.appList.plistParseError".loc
                errorShow = true
                return
            }
            
            var ipaUrlStr: String?
            for asset in assets {
                if let kind = asset["kind"] as? String, kind == "software-package",
                   let url = asset["url"] as? String {
                    ipaUrlStr = url
                    break
                }
            }
            
            guard let ipaUrlStr else {
                errorInfo = "lc.appList.plistNoIpaError".loc
                errorShow = true
                return
            }
            
            await installFromUrl(urlStr: ipaUrlStr)
            
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }
    
    func installFromUrl(urlStr: String) async {
        // ignore any install request if we are installing another app
        if self.installprogressVisible {
            return
        }
        
        if sharedModel.multiLCStatus == 2 {
            errorInfo = "lc.appList.manageInPrimaryTip".loc
            errorShow = true
            return
        }
        
        guard var installUrl = URL(string: urlStr) else {
            errorInfo = "lc.appList.urlInvalidError".loc
            errorShow = true
            return
        }
        
        self.installprogressVisible = true
        defer {
            self.installprogressVisible = false
        }
        
        if installUrl.isFileURL {
            // install from local, we directly call local install method
            let fileExtension = installUrl.pathExtension.lowercased()
            if fileExtension != "ipa" && fileExtension != "tipa" {
                errorInfo = "lc.appList.urlFileIsNotIpaError".loc
                errorShow = true
                return
            }
            
            let fm = FileManager.default
            var didStartAccessing = false
            if !fm.isReadableFile(atPath: installUrl.path),
               let bookmarkData = LCUtils.appGroupUserDefault.data(forKey: "LCLaunchExtensionFileBookmark") {
                do {
                    var isStale = false
                    let resolvedURL = try URL(
                        resolvingBookmarkData: bookmarkData,
                        options: URL.BookmarkResolutionOptions(rawValue: 1 << 10),
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale
                    )
                    installUrl = resolvedURL
                    didStartAccessing = resolvedURL.startAccessingSecurityScopedResource()
                } catch {
                    errorInfo =  "Failed to resolve shared IPA bookmark: \(error.localizedDescription)"
                    errorShow = true
                    return
                }
            }

            if !fm.isReadableFile(atPath: installUrl.path) && !didStartAccessing {
                didStartAccessing = installUrl.startAccessingSecurityScopedResource()
            }

            if !fm.isReadableFile(atPath: installUrl.path) && !didStartAccessing {
                errorInfo = "lc.appList.ipaAccessError".loc
                errorShow = true
                return
            }
            
            defer {
                if didStartAccessing {
                    installUrl.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                try await installIpaFile(installUrl)
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
            
            do {
                // delete ipa if it's in inbox
                var shouldDelete = false
                if let documentsDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let inboxURL = documentsDirectory.appendingPathComponent("Inbox")
                    shouldDelete = installUrl.deletingLastPathComponent().standardizedFileURL == inboxURL.standardizedFileURL
                }
                if shouldDelete {
                    try fm.removeItem(at: installUrl)
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
            }
            return
        }
        
        do {
            let fileManager = FileManager.default
            let destinationURL = fileManager.temporaryDirectory.appendingPathComponent(installUrl.lastPathComponent)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            try await downloadHelper.download(url: installUrl, to: destinationURL)
            if downloadHelper.cancelled {
                return
            }
            try await installIpaFile(destinationURL)
            try fileManager.removeItem(at: destinationURL)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func removeApp(app: LCAppModel) {
        DispatchQueue.main.async {
            sharedModel.apps.removeAll { now in
                return app == now
            }
            sharedModel.hiddenApps.removeAll { now in
                return app == now
            }
            
        }
    }
    
    func changeAppVisibility(app: LCAppModel) {
        DispatchQueue.main.async {
            if app.appInfo.isHidden {
                sharedModel.apps.removeAll { now in
                    return app == now
                }
                if !sharedModel.hiddenApps.contains(app) {
                    sharedModel.hiddenApps.append(app)
                }
                UserDefaults.lcShared().mutableArrayValue(forKey: "LCGuestURLSchemes")
                    .removeObjects(in: app.appInfo.urlSchemes() as! [Any])
            } else {
                sharedModel.hiddenApps.removeAll { now in
                    return app == now
                }
                if !sharedModel.apps.contains(app) {
                    sharedModel.apps.append(app)
                }
                UserDefaults.lcShared().mutableArrayValue(forKey: "LCGuestURLSchemes")
                    .addObjects(from: app.appInfo.urlSchemes() as! [Any])
            }
            
        }
    }
    
    func launchAppWithBundleId(bundleId : String, container : String?, urlStr: String? = nil, forceJIT: Bool? = nil) async {
        if bundleId == "" {
            return
        }
        var appFound : LCAppModel? = nil
        var isFoundAppLocked = false
        for app in sharedModel.apps {
            if app.appInfo.relativeBundlePath == bundleId {
                appFound = app
                if app.appInfo.isLocked {
                    isFoundAppLocked = true
                }
                break
            }
        }
        if appFound == nil && !LCUtils.appGroupUserDefault.bool(forKey: "LCStrictHiding") {
            for app in sharedModel.hiddenApps {
                if app.appInfo.relativeBundlePath == bundleId {
                    appFound = app
                    isFoundAppLocked = true
                    break
                }
            }
        }
        
        if appFound == nil && bundleId == "builtinSideStore" {
            appFound = LCAppModel(appInfo: BuiltInSideStoreAppInfo.shared)
        }
        
        if isFoundAppLocked && !sharedModel.isHiddenAppUnlocked {
            do {
                let result = try await LCUtils.authenticateUser()
                if !result {
                    return
                }
            } catch {
                errorInfo = error.localizedDescription
                errorShow = true
                return
            }
        }
        
        guard let appFound else {
            errorInfo = "lc.appList.appNotFoundError".loc
            errorShow = true
            return
        }

        do {
            try await appFound.runApp(multitask: nil, containerFolderName: container, urlStr: urlStr, forceJIT: forceJIT)
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func authenticateUser() async {
        do {
            if !(try await LCUtils.authenticateUser()) {
                return
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
            return
        }
    }
    
    func jitLaunch(appName: String, classicMode: UInt) async {
        await jitLaunch(withScript: "", appName: appName, classicMode: classicMode)
    }

    func jitLaunch(withScript script: String, appName: String, classicMode: UInt) async {
        await MainActor.run {
            jitLog = ""
        }
        let enableJITTask = Task {
            
            let _ = await LCUtils.askForJIT(withScript: script, appName: appName, classicMode: classicMode) { newMsg in
                Task { await MainActor.run {
                    self.jitLog += "\(newMsg)\n"
                }}
            }
            guard let _ = JITEnablerType(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCJITEnablerType")) else {
                return
            }
        }
        guard let result = await jitAlert.open(), result else {
            UserDefaults.standard.removeObject(forKey: "selected")
            enableJITTask.cancel()
            return
        }
        LCSharedUtils.launchToGuestApp(withClassicMode: classicMode)

    }
    
    func jitLaunch(withPID pid: Int, withScript script: String? = nil, appName: String) async {
        await MainActor.run {
            let encodedData = script?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
                
            
            if let jitEnabler = JITEnablerType(rawValue: LCUtils.appGroupUserDefault.integer(forKey: "LCJITEnablerType")) {
                if jitEnabler == .StosDebug || jitEnabler == .StosDebugLC {
                    let encoded = encodedData.map { "&script=\($0)" } ?? ""
                    if jitEnabler == .StosDebugLC {
                        if let app = sharedModel.apps.first(where: { app in
                            return app.appInfo.urlSchemes().contains("stosdebug") &&
                            (sharedModel.multiLCStatus != 2 || app.appInfo.isShared)
                        }) {
                            if var url = URL(string: "stosdebug://enableJIT?bundleId=\(Bundle.main.bundleIdentifier!)&appName=\(appName)&pid=\(pid)&relaunchApp=false& forcePID=true\(encoded)") {
                                Task { await openWebView(urlString: url.absoluteString) }
                            }
                        } else {
                            errorInfo = "StosDebug is not found. Please install it first and switch it to shared app."
                            errorShow = true
                            return
                        }
                    } else {
                        if var url = URL(string: "stosdebug://enableJIT?bundleId=\(Bundle.main.bundleIdentifier!)&appName=\(appName)&pid=\(pid)&forcePID=true\(encoded)") {
                            UIApplication.shared.open(url)
                        }
                    }
                    return
                }
                
                let encoded = encodedData.map { "&script-data=\($0)" } ?? ""
                if let url = URL(string: "stikjit://enable-jit?bundle-id=\(Bundle.main.bundleIdentifier!)&pid=\(pid)\(encoded)") {
                    if jitEnabler == .StikJITLC {
                        if let app = sharedModel.apps.first(where: { app in
                            return app.appInfo.urlSchemes().contains("stikjit") &&
                            (sharedModel.multiLCStatus != 2 || app.appInfo.isShared)
                        }) {
                            Task { await openWebView(urlString: url.absoluteString) }
                        } else {
                            errorInfo = "StikDebug is not found. Please install it first and switch it to shared app."
                            errorShow = true
                            return
                        }
                    } else {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    func showRunWhenMultitaskAlert() async -> Bool? {
        return await runWhenMultitaskAlert.open()
    }
    
    func installMdm(data: Data) {
        safariViewURL = URL(string:"data:application/x-apple-aspen-config;base64,\(data.base64EncodedString())")!
        safariViewOpened = true
    }
    
    func openNavigationView(view: AnyView) {
        if #available(iOS 16.0, *) {
            navigateTo = AnyView(view.toolbar(.visible, for: .navigationBar))
        } else {
            navigateTo = view
        }
        isNavigationActive = true
    }
    
    func promptForGeneratedIconStyle() async -> GeneratedIconStyle? {
        if #available(iOS 18.0, *) {
            return await generatedIconStyleSelector.open()
        } else {
            return .Light
        }
        
    }
    
    func closeNavigationView() {
        isNavigationActive = false
        navigateTo = nil
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func handleURL(url : URL) {
        if url.isFileURL {
            Task { await installFromUrl(urlStr: url.absoluteString) }
            return
        }
        
        if url.scheme == "sidestore" && UserDefaults.sideStoreExist() {
            UserDefaults.standard.setValue(url.absoluteString, forKey: "launchAppUrlScheme")
            LCUtils.openSideStore(delegate: self)
            return
        }
        
        if url.host == "open-web-page" || url.host == "open-url" {
            if let urlComponent = URLComponents(url: url, resolvingAgainstBaseURL: false), let queryItem = urlComponent.queryItems?.first {
                if queryItem.value?.isEmpty ?? true {
                    return
                }
                
                if let decodedData = Data(base64Encoded: queryItem.value ?? ""),
                   let decodedUrl = String(data: decodedData, encoding: .utf8) {
                    Task { await openWebView(urlString: decodedUrl) }
                }
            }
        } else if url.host == "livecontainer-launch" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var bundleId : String? = nil
                var containerName : String? = nil
                var forceJIT: Bool? = nil
                var urlStr: String? = nil
                for queryItem in components.queryItems ?? [] {
                    if queryItem.name == "bundle-name", let bundleId1 = queryItem.value {
                        bundleId = bundleId1
                    } else if queryItem.name == "container-folder-name", let containerName1 = queryItem.value {
                        containerName = containerName1
                    } else if queryItem.name == "jit", let forceJIT1 = queryItem.value {
                        if forceJIT1 == "true" {
                            forceJIT = true
                        } else if forceJIT1 == "false" {
                            forceJIT = false
                        }
                    } else if queryItem.name == "open-url" {
                        if let decodedData = Data(base64Encoded: queryItem.value ?? ""),
                           let decodedUrl = String(data: decodedData, encoding: .utf8) {
                            urlStr = decodedUrl
                        }
                    }
                }
                if let bundleId, bundleId != "ui"{
                    Task { await launchAppWithBundleId(bundleId: bundleId, container: containerName, urlStr: urlStr, forceJIT: forceJIT) }
                }
            }
        } else if url.host == "install" {
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                var installUrl : String? = nil
                for queryItem in components.queryItems ?? [] {
                    if queryItem.name == "url", let installUrl1 = queryItem.value {
                        installUrl = installUrl1
                    }
                }
                if let installUrl {
                    Task { await installFromUrl(urlStr: installUrl) }
                }
            }
        }
    }
    
}

private struct HomeScreenAppIcon: View {
    @ObservedObject var app: LCAppModel
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkModeIcon = false
    let large: Bool

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: large ? 0 : 4) {
                IconImageView(icon: app.appInfo.iconIsDarkIcon(darkModeIcon) ?? UIImage())
                    .frame(width: large ? 76 : 60, height: large ? 76 : 60)

                if !large {
                    Text(app.appInfo.displayName() ?? app.displayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 1)
                        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: large ? 86 : 100)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.appInfo.displayName() ?? app.displayName)
    }
}

private let homeClockWidgetDragID = "livecontainer.home-widget.clock"

private struct HomeScreenGridCell {
    let row: Int
    let column: Int
}

private struct HomeScreenGridLayout {
    let appCells: [Int: HomeScreenGridCell]
    let widgetCell: HomeScreenGridCell?
    let rowCount: Int
}

private struct HomeScreenClockWidget: View {
    let rows: Int
    let tileHeight: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(context.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                GeometryReader { geometry in
                    let diameter = min(geometry.size.width, geometry.size.height) - 8
                    let calendar = Calendar.current
                    let components = calendar.dateComponents([.hour, .minute, .second], from: context.date)
                    let minute = Double(components.minute ?? 0)
                    let second = Double(components.second ?? 0)
                    let hour = Double((components.hour ?? 0) % 12) + minute / 60

                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .overlay(Circle().stroke(.white.opacity(0.5), lineWidth: 1))

                        ForEach(0..<12, id: \.self) { tick in
                            Capsule()
                                .fill(.white.opacity(tick.isMultiple(of: 3) ? 0.95 : 0.55))
                                .frame(width: tick.isMultiple(of: 3) ? 2.5 : 1.5, height: tick.isMultiple(of: 3) ? 9 : 5)
                                .offset(y: -diameter * 0.43)
                                .rotationEffect(.degrees(Double(tick) * 30))
                        }

                        Rectangle()
                            .fill(.white)
                            .frame(width: 4, height: diameter * 0.25)
                            .offset(y: -diameter * 0.105)
                            .rotationEffect(.degrees(hour * 30))

                        Rectangle()
                            .fill(.white)
                            .frame(width: 2.5, height: diameter * 0.34)
                            .offset(y: -diameter * 0.15)
                            .rotationEffect(.degrees(minute * 6))

                        Rectangle()
                            .fill(.red.opacity(0.9))
                            .frame(width: 1, height: diameter * 0.39)
                            .offset(y: -diameter * 0.17)
                            .rotationEffect(.degrees(second * 6))

                        Circle().fill(.white).frame(width: 7, height: 7)
                    }
                    .frame(width: diameter, height: diameter)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(rows) * tileHeight + CGFloat(max(0, rows - 1)) * 2)
            .foregroundStyle(.white)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.18), lineWidth: 1))
        }
    }
}

private struct HomeAppReorderDropDelegate: DropDelegate {
    let app: LCAppModel
    let apps: [LCAppModel]
    let manager: LCAppSortManager
    @Binding var draggedAppID: String?
    @Binding var widgetIndex: Int

    func dropEntered(info: DropInfo) {
        guard let draggedAppID,
              let toID = manager.getUniqueIdentifier(for: app),
              let to = apps.firstIndex(where: { manager.matches(uniqueId: toID, app: $0) }) else { return }

        if draggedAppID == homeClockWidgetDragID {
            widgetIndex = to
            return
        }

        guard let from = apps.firstIndex(where: { manager.matches(uniqueId: draggedAppID, app: $0) }), from != to else { return }

        var reordered = apps
        let moved = reordered.remove(at: from)
        reordered.insert(moved, at: to)
        let visibleIDs = reordered.compactMap { manager.getUniqueIdentifier(for: $0) }
        let otherIDs = manager.customSortOrder.filter { !visibleIDs.contains($0) }
        manager.customSortOrder = visibleIDs + otherIDs
        manager.appSortType = .custom
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAppID = nil
        return true
    }
}

private struct HomeClockWidgetReorderDropDelegate: DropDelegate {
    let apps: [LCAppModel]
    let manager: LCAppSortManager
    @Binding var draggedAppID: String?
    @Binding var widgetIndex: Int

    func dropEntered(info: DropInfo) {
        guard let draggedAppID,
              draggedAppID != homeClockWidgetDragID,
              let appIndex = apps.firstIndex(where: { manager.matches(uniqueId: draggedAppID, app: $0) }) else { return }
        widgetIndex = appIndex
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedAppID = nil
        return true
    }
}

extension View {
    func apply<V: View>(@ViewBuilder _ block: (Self) -> V) -> V { block(self) }
}
