//
//  TabView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/8/21.
//

import Foundation
import SwiftUI
import UIKit

private struct LCHideSystemTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(.hidden, for: .tabBar)
        } else {
            content
        }
    }
}

struct LCTabView: View {
    @State var errorShow = false
    @State var crashReportShow = false
    @State var errorInfo = ""
    
    @EnvironmentObject var sharedModel : SharedModel
    @EnvironmentObject var sceneDelegate: SceneDelegate
    @State var shouldToggleMainWindowOpen = false
    @Environment(\.scenePhase) var scenePhase
    @StateObject var downloadHelper = DownloadHelper()
    @AppStorage("LCThemeAccentHex", store: LCUtils.appGroupUserDefault) private var themeAccentHex = "409EFF"
    @AppStorage("LCThemeAppearance", store: LCUtils.appGroupUserDefault) private var themeAppearance = "system"
    @AppStorage("darkModeIcon", store: LCUtils.appGroupUserDefault) private var darkModeIcon = false
    @AppStorage("LCAppListGrid", store: LCUtils.appGroupUserDefault) private var appListGrid = false

    init() {
        if #available(iOS 15.0, *) {
            UITabBar.appearance().isHidden = true
        }
    }

    let pub = NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)
    
    var body: some View {
        TabView(selection: $sharedModel.selectedTab) {
            if DataManager.shared.model.multiLCStatus != 2 {
                LCSourcesView()
                    .tabItem {
                        Label("lc.tabView.sources".loc, systemImage: "books.vertical")
                    }
                    .tag(LCTabIdentifier.sources)
            }
            LCAppListView()
                .tabItem {
                    Label("lc.tabView.apps".loc, systemImage: "square.stack.3d.up.fill")
                }
                .tag(LCTabIdentifier.apps)
            if DataManager.shared.model.multiLCStatus != 2 {
                LCTweaksView()
                    .tabItem{
                        Label("lc.tabView.tweaks".loc, systemImage: "wrench.and.screwdriver")
                    }
                    .tag(LCTabIdentifier.tweaks)
            }
            
            LCSettingsView()
                .tabItem {
                    Label("lc.tabView.settings".loc, systemImage: "gearshape.fill")
                }
                .tag(LCTabIdentifier.settings)
            }
            .modifier(LCHideSystemTabBar())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                homeDock
            }
            .background(Color.clear)
            .tint(LCTheme.color(hex: themeAccentHex))
            .preferredColorScheme(LCTheme.colorScheme(for: themeAppearance))
            .downloadAlert(helper: downloadHelper)
            .environmentObject(downloadHelper)
            .alert("lc.common.error".loc, isPresented: $errorShow){
            Button("lc.common.ok".loc, action: {
            })
            Button("lc.common.copy".loc, action: {
                copyError()
            })
            } message: {
                Text(errorInfo)
            }
            .sheet(isPresented: $crashReportShow) {
            NavigationView {
                ScrollView {
                    Text(errorInfo)
                        .font(.system(size: 12).monospaced())
                        .fixedSize(horizontal: false, vertical: false)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if #available(iOS 16.0, *) {
                            if let log = UserDefaults.lcShared().url(forKey: "LC32BitTranslationLayerLogFile") {
                                ShareLink(item: log)
                            } else {
                                ShareLink(item: errorInfo)
                            }
                        } else {
                            Button("lc.common.copy".loc) {
                                copyError()
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("lc.common.ok".loc, action: {
                            crashReportShow = false
                        })
                    }
                }
                .navigationTitle("lc.common.error".loc)
                .navigationBarTitleDisplayMode(.inline)
            }
            }
            .task {
                closeDuplicatedWindow()
                checkLastLaunchError()
                checkTeamId()
                checkAndSaveBundleId()
                checkGetTaskAllow()
                checkPrivateContainerBookmark()
            }
            .onReceive(pub) { out in
                if let scene1 = sceneDelegate.window?.windowScene, let scene2 = out.object as? UIWindowScene, scene1 == scene2 {
                    if shouldToggleMainWindowOpen {
                        DataManager.shared.model.mainWindowOpened = false
                    }
                }
            }
            .onOpenURL { url in
                dispatchURL(url: url)
            }
    }

    private var homeDock: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            if UserDefaults.sideStoreExist() {
                Button {
                    LCUtils.openSideStore()
                } label: {
                    dockAppIcon {
                        Image(uiImage: BuiltInSideStoreAppInfo.shared.iconIsDarkIcon(darkModeIcon))
                            .resizable()
                            .scaledToFit()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("SideStore")
            }

            Button {
                appListGrid.toggle()
            } label: {
                dockAppIcon {
                    ZStack {
                        LinearGradient(
                            colors: [Color(red: 0.20, green: 0.48, blue: 0.94), Color(red: 0.12, green: 0.28, blue: 0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: appListGrid ? "list.bullet" : "square.grid.2x2.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appListGrid ? "Switch to list layout" : "Switch to app grid")

            Button {
                sharedModel.selectedTab = .settings
            } label: {
                dockAppIcon {
                    Image("SettingsAppIcon")
                        .resizable()
                        .scaledToFit()
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("lc.tabView.settings".loc)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(width: 320, height: 78)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
        .frame(maxWidth: .infinity)
        .padding(.top, 5)
        .padding(.bottom, 4)
    }

    private func dockAppIcon<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: 58, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    
    func dispatchURL(url: URL) {
        repeat {
            if url.isFileURL {
                sharedModel.selectedTab = .apps
                break
            }
            if url.scheme?.lowercased() == "sidestore" {
                sharedModel.selectedTab = .apps
                break
            }
            
            guard let host = url.host?.lowercased() else {
                return
            }
            
            switch host {
            case "livecontainer-launch", "install", "open-web-page", "open-url":
                sharedModel.selectedTab = .apps
            case "certificate":
                sharedModel.selectedTab = .settings
            case "source":
                sharedModel.selectedTab = .sources
            default:
                return
            }
            
        } while(false)

        sharedModel.deepLink = url
    }
    
    func closeDuplicatedWindow() {
        if let session = sceneDelegate.window?.windowScene?.session, DataManager.shared.model.mainWindowOpened {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { e in
                print(e)
            }
        } else {
            shouldToggleMainWindowOpen = true
        }
        DataManager.shared.model.mainWindowOpened = true
    }
    
    func checkLastLaunchError() {
        var errorStr = UserDefaults.standard.string(forKey: "error")
        
        if errorStr == nil && UserDefaults.standard.bool(forKey: "SigningInProgress") {
            errorStr = "lc.signer.crashDuringSignErr".loc
            UserDefaults.standard.removeObject(forKey: "SigningInProgress")
        }
        
        guard let errorStr else {
            return
        }
        UserDefaults.standard.removeObject(forKey: "error")
        errorInfo = errorStr
        crashReportShow = true
    }
    
    func copyError() {
        UIPasteboard.general.string = errorInfo
    }
    
    func checkTeamId() {
        if let certificateTeamId = UserDefaults.standard.string(forKey: "LCCertificateTeamId") {
            if DataManager.shared.model.multiLCStatus != 2 {
                return
            }
            
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if certificateTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
            return
        }
        
        guard let currentTeamId = LCSharedUtils.teamIdentifier() else {
            print("Failed to determine team id.")
            return
        }
        
        if DataManager.shared.model.multiLCStatus == 2 {
            guard let primaryLCTeamId = Bundle.main.infoDictionary?["PrimaryLiveContainerTeamId"] as? String else {
                print("Unable to find PrimaryLiveContainerTeamId")
                return
            }
            if currentTeamId != primaryLCTeamId {
                errorInfo = "lc.settings.multiLC.teamIdMismatch".loc
                errorShow = true
                return
            }
        }
        UserDefaults.standard.set(currentTeamId, forKey: "LCCertificateTeamId")
    }
    
    func checkAndSaveBundleId() {
        if DataManager.shared.model.multiLCStatus == 2 {
            let scheme = UserDefaults.lcAppUrlScheme() ?? ""
            LCUtils.appGroupUserDefault.set(Bundle.main.bundleIdentifier, forKey: "LCBundleID.\(scheme)")
        }
        
        if UserDefaults.standard.bool(forKey: "LCBundleIdChecked") {
            return
        }
        
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "application-identifier" as CFString, nil), let appIdentifier = value.takeRetainedValue() as? String else {
            errorInfo = "Unable to determine application-identifier"
            errorShow = true
            return
        }
        
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return
        }
        
        var correctBundleId = ""
        if appIdentifier.count > 11 {
            let startIndex = appIdentifier.index(appIdentifier.startIndex, offsetBy: 11)
            correctBundleId = String(appIdentifier[startIndex...])
        }
        
        if(bundleId != correctBundleId) {
            errorInfo = "lc.settings.bundleIdMismatch %@ %@".localizeWithFormat(bundleId, correctBundleId)
            errorShow = true
        }
        UserDefaults.standard.set(true, forKey: "LCBundleIdChecked")
    }
    
    func checkGetTaskAllow() {
        let task = SecTaskCreateFromSelf(nil)
        guard let value = SecTaskCopyValueForEntitlement(task, "get-task-allow" as CFString, nil), (value.takeRetainedValue() as? NSNumber)?.boolValue ?? false else {
            errorInfo = "lc.settings.notDevCert".loc
            errorShow = true
            return
        }
    }
    
    func checkPrivateContainerBookmark() {
        if sharedModel.multiLCStatus == 2 {
            return
        }
        if LCUtils.appGroupUserDefault.object(forKey: "LCLaunchExtensionPrivateDocBookmark") != nil {
            return
        }
        
        guard let bookmark = LCUtils.bookmark(for: LCPath.docPath) else {
            errorInfo = "Failed to create bookmark for Documents folder?"
            errorShow = true
            return
        }
        LCUtils.appGroupUserDefault.set(bookmark, forKey: "LCLaunchExtensionPrivateDocBookmark")
    }
}
