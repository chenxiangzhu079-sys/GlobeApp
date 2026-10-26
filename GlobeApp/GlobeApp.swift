// GlobeApp.swift
// 地球仪 v2：ImmersiveMap 引擎全屏 3D 地球 + 搜索/定位/查地名（A）+ 自制按钮列（B）+ 地图设置页（C）。
// 引擎没有内置地理编码，搜索与反查走 OSM Nominatim（见 GeoServices.swift）；
// 引擎不提供「屏幕点→经纬度」的公开接口，查地名改为「中心准星」模式：把地点转到屏幕中心，点底部坐标条查名。

import SwiftUI
import ImmersiveMap

@main
struct GlobeApp: App {
    var body: some Scene {
        WindowGroup {
            MapScreen()
        }
    }
}

// MARK: - 主界面

struct MapScreen: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var locationManager = LocationManager()
    @State private var camera = ImmersiveMapCameraController()

    @State private var markers: [PlaceMarker] = []
    @State private var info: PlaceInfo?
    @State private var searchText = ""
    @State private var results: [GeocodeResult] = []
    @State private var isSearching = false
    @State private var showResults = false
    @State private var isLocatingName = false
    @State private var autoRotate = false
    @State private var showSettings = false
    @State private var centerLat = 27.0
    @State private var centerLon = 108.0
    @State private var callbacksReady = false
    @FocusState private var searchFocused: Bool

    private let rotateTimer = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    /// 开局视角：以中国为中心的全球视角。
    private static let overview = ImmersiveMapCameraPosition(latitudeDegrees: 27,
                                                             longitudeDegrees: 108,
                                                             zoom: 1.8,
                                                             bearing: 0,
                                                             pitch: 0.08)

    var body: some View {
        ZStack {
            mapLayer
            VStack(spacing: 8) {
                searchBar
                if showResults {
                    resultsList
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)

            VStack {
                Spacer()
                HStack(alignment: .bottom) {
                    centerChip
                    Spacer()
                    buttonColumn
                }
                if let info {
                    infoCard(info)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
        .onReceive(rotateTimer) { _ in
            rotateStep()
        }
        .onAppear {
            wireCallbacks()
        }
    }

    // MARK: 地图本体（设置全部走引擎现成开关）

    private var mapLayer: some View {
        ImmersiveMapView()
            .camera(camera, position: Self.overview)
            .enableCameraUIControls(settings.engineControls)
            .night(settings.night)
            .labels(isEnabled: settings.labels)
            .groundRelief(isEnabled: settings.relief)
            .buildingExtrusion(buildingsMinimumZoom: settings.buildings ? 14 : 22)
            .trees(isEnabled: settings.trees)
            .atmosphere(isEnabled: settings.atmosphere)
            .shadows(isEnabled: settings.shadows)
            .globe(isEnabled: settings.sphere)
            .markers(markers, coordinate: \.coordinate, anchor: .bottom) { marker in
                PinView(title: marker.title, isMe: marker.isMe)
            }
            .ignoresSafeArea()
    }

    // MARK: 顶部搜索

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索城市、地名", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit { runSearch() }
            if isSearching {
                ProgressView()
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                    results = []
                    showResults = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            if results.isEmpty {
                Text(isSearching ? "搜索中…" : "没有找到结果")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ForEach(results) { result in
                    Button {
                        select(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.shortName)
                                .font(.subheadline).bold()
                                .foregroundStyle(.primary)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    Divider().padding(.leading, 12)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: 右侧按钮列（B）

    private var buttonColumn: some View {
        VStack(spacing: 10) {
            roundButton("location.fill", label: "定位到我") { locateMe() }
            roundButton("globe.asia.australia.fill", label: "回到全球") { goHome() }
            roundButton("location.north.fill", label: "回正北") { resetNorth() }
            roundButton("plus", label: "放大") { zoomStep(1) }
            roundButton("minus", label: "缩小") { zoomStep(-1) }
            roundButton(autoRotate ? "pause.fill" : "rotate.3d", label: "自动旋转") {
                autoRotate.toggle()
            }
            roundButton("gearshape.fill", label: "设置") { showSettings = true }
        }
    }

    private func roundButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 42, height: 42)
        }
        .background(.ultraThinMaterial, in: Circle())
        .accessibilityLabel(label)
    }

    // MARK: 底部中心坐标条（查地名的落点：中心准星）

    private var centerChip: some View {
        Button {
            lookupCenterName()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                Text(String(format: "中心 %.3f°, %.3f°", centerLat, centerLon))
                    .font(.caption).monospacedDigit()
                if isLocatingName {
                    ProgressView().controlSize(.mini)
                } else {
                    Text("查地名")
                        .font(.caption).bold()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 地点信息卡

    private func infoCard(_ place: PlaceInfo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(place.title)
                    .font(.subheadline).bold()
                    .lineLimit(2)
                if !place.detail.isEmpty {
                    Text(place.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(String(format: "纬度 %.5f  经度 %.5f", place.coordinate.latitude, place.coordinate.longitude))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                info = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .padding(.top, 8)
    }

    // MARK: 行为

    private func wireCallbacks() {
        guard !callbacksReady else { return }
        callbacksReady = true
        camera.onUserInteractionBegan = {
            autoRotate = false
        }
        camera.onCameraPositionChanged = { position in
            let lat = (position.latitudeDegrees * 1000).rounded() / 1000
            let lon = (position.longitudeDegrees * 1000).rounded() / 1000
            if lat != centerLat || lon != centerLon {
                centerLat = lat
                centerLon = lon
            }
        }
        camera.onMapBackgroundTap = {
            info = nil
        }
        locationManager.onLocation = { coordinate in
            let place = GeoCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            markers = [PlaceMarker(title: "我的位置", coordinate: place, isMe: true)]
            info = PlaceInfo(title: "我的位置", detail: "", coordinate: place)
            camera.fly(to: ImmersiveMapCameraPosition(latitudeDegrees: coordinate.latitude,
                                                      longitudeDegrees: coordinate.longitude,
                                                      zoom: 10,
                                                      bearing: 0,
                                                      pitch: 0.3))
        }
        locationManager.onDenied = {
            info = PlaceInfo(title: "定位不可用",
                             detail: "请在 系统设置 → 地球仪 里允许定位",
                             coordinate: GeoCoordinate(latitude: centerLat, longitude: centerLon))
        }
    }

    private func runSearch() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        isSearching = true
        showResults = true
        Task {
            let found = await GeocodeService.search(query)
            results = found
            isSearching = false
        }
    }

    private func select(_ result: GeocodeResult) {
        guard let coordinate = result.coordinate else { return }
        showResults = false
        searchFocused = false
        autoRotate = false
        markers = [PlaceMarker(title: result.shortName, coordinate: coordinate)]
        info = PlaceInfo(title: result.shortName, detail: result.subtitle, coordinate: coordinate)
        camera.fly(to: ImmersiveMapCameraPosition(latitudeDegrees: coordinate.latitude,
                                                  longitudeDegrees: coordinate.longitude,
                                                  zoom: result.suggestedZoom,
                                                  bearing: 0,
                                                  pitch: 0.25))
    }

    private func lookupCenterName() {
        guard !isLocatingName else { return }
        isLocatingName = true
        let lat = centerLat
        let lon = centerLon
        Task {
            let found = await GeocodeService.reverse(latitude: lat, longitude: lon)
            isLocatingName = false
            if let found {
                info = found
            } else {
                info = PlaceInfo(title: "这里没有地名记录",
                                 detail: "可能是海洋或无人区",
                                 coordinate: GeoCoordinate(latitude: lat, longitude: lon))
            }
        }
    }

    private func locateMe() {
        autoRotate = false
        locationManager.requestLocation()
    }

    private func goHome() {
        autoRotate = false
        camera.fly(to: Self.overview)
    }

    private func resetNorth() {
        guard let current = camera.currentCameraPosition() else { return }
        camera.fly(to: ImmersiveMapCameraPosition(latitudeDegrees: current.latitudeDegrees,
                                                  longitudeDegrees: current.longitudeDegrees,
                                                  zoom: current.zoom,
                                                  bearing: 0,
                                                  pitch: current.pitch))
    }

    private func zoomStep(_ delta: Double) {
        guard let current = camera.currentCameraPosition() else { return }
        let zoom = min(max(current.zoom + delta, 0.5), 18)
        camera.fly(to: ImmersiveMapCameraPosition(latitudeDegrees: current.latitudeDegrees,
                                                  longitudeDegrees: current.longitudeDegrees,
                                                  zoom: zoom,
                                                  bearing: current.bearing,
                                                  pitch: current.pitch))
    }

    private func rotateStep() {
        guard autoRotate, let current = camera.currentCameraPosition() else { return }
        // bearing 单位为弧度：每步约 23°，3 秒一步，靠飞行动画衔接成慢转。
        camera.fly(to: ImmersiveMapCameraPosition(latitudeDegrees: current.latitudeDegrees,
                                                  longitudeDegrees: current.longitudeDegrees,
                                                  zoom: current.zoom,
                                                  bearing: current.bearing + 0.4,
                                                  pitch: current.pitch))
    }
}

// MARK: - 标记针

struct PinView: View {
    let title: String
    var isMe: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption).bold()
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
            Image(systemName: isMe ? "location.circle.fill" : "mappin.circle.fill")
                .font(.title2)
                .foregroundStyle(isMe ? .blue : .red, .white)
        }
    }
}

// MARK: - 设置页（C）

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("地图外观") {
                    Toggle("夜间模式", isOn: $settings.night)
                    Toggle("地名标注", isOn: $settings.labels)
                    Toggle("大气层", isOn: $settings.atmosphere)
                    Toggle("阴影效果", isOn: $settings.shadows)
                }
                Section("地形与建筑") {
                    Toggle("地形起伏", isOn: $settings.relief)
                    Toggle("3D 建筑", isOn: $settings.buildings)
                    Toggle("树木", isOn: $settings.trees)
                }
                Section("显示") {
                    Toggle("球体模式（关 = 平面地图）", isOn: $settings.sphere)
                    Toggle("引擎自带相机控件", isOn: $settings.engineControls)
                }
                Section("关于") {
                    LabeledContent("版本", value: "2.0")
                    Text("地图数据 © OpenStreetMap 贡献者（ODbL）；地名搜索：OSM Nominatim；渲染引擎：ImmersiveMap（MIT）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("地图设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
