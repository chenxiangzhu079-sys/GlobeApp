// GeoServices.swift
// 地球仪 v2 的服务层：设置存储（UserDefaults）、地名搜索/反查（OSM Nominatim）、定位（CoreLocation）。
// 引擎 ImmersiveMap 本身不带地理编码，这里用 OpenStreetMap 的免费 Nominatim 服务补齐。

import Foundation
import CoreLocation
import ImmersiveMap

// MARK: - 数据模型

/// 地图上的一个标记点（搜索结果或我的位置）。
struct PlaceMarker: Identifiable {
    let id = UUID()
    var title: String
    var coordinate: GeoCoordinate
    var isMe: Bool = false
}

/// 底部信息卡展示的一个地点。
struct PlaceInfo {
    var title: String
    var detail: String
    var coordinate: GeoCoordinate
}

/// Nominatim 搜索结果（原始字段）。
struct GeocodeResult: Identifiable, Decodable {
    let id = UUID()
    var lat: String
    var lon: String
    var displayName: String
    var type: String?
    var placeClass: String?

    enum CodingKeys: String, CodingKey {
        case lat, lon, type
        case displayName = "display_name"
        case placeClass = "class"
    }

    var coordinate: GeoCoordinate? {
        guard let la = Double(lat), let lo = Double(lon) else { return nil }
        return GeoCoordinate(latitude: la, longitude: lo)
    }

    /// 主名：display_name 的第一段。
    var shortName: String {
        displayName.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? displayName
    }

    /// 次级说明：display_name 去掉第一段后的前两段。
    var subtitle: String {
        let parts = displayName.split(separator: ",").dropFirst().prefix(2)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.joined(separator: "，")
    }

    /// 按结果类型给一个合适的飞行缩放级别。
    var suggestedZoom: Double {
        switch type ?? "" {
        case "country", "state", "province": return 4.5
        case "city", "administrative": return 6.5
        case "town", "county": return 8.5
        case "village", "suburb", "district": return 10.5
        default: return 12.5
        }
    }
}

private struct ReverseGeocodeResult: Decodable {
    var displayName: String?
    var name: String?

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
    }
}

// MARK: - 地理编码服务（Nominatim）

enum GeocodeService {
    private static func request(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        // Nominatim 使用政策要求带可识别的 User-Agent。
        req.setValue("GlobeApp/2.0 (personal iOS app)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        return req
    }

    static func search(_ query: String) async -> [GeocodeResult] {
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/search")
        comps?.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: "6"),
            URLQueryItem(name: "accept-language", value: "zh-CN"),
            URLQueryItem(name: "q", value: query)
        ]
        guard let url = comps?.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(for: request(url))
            return (try? JSONDecoder().decode([GeocodeResult].self, from: data)) ?? []
        } catch {
            return []
        }
    }

    /// 反查：给经纬度，返回最近的地名信息。
    static func reverse(latitude: Double, longitude: Double) async -> PlaceInfo? {
        var comps = URLComponents(string: "https://nominatim.openstreetmap.org/reverse")
        comps?.queryItems = [
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "zoom", value: "16"),
            URLQueryItem(name: "accept-language", value: "zh-CN"),
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude))
        ]
        guard let url = comps?.url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(for: request(url))
            guard let decoded = try? JSONDecoder().decode(ReverseGeocodeResult.self, from: data),
                  let display = decoded.displayName else { return nil }
            let parts = display.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let title = decoded.name?.isEmpty == false ? decoded.name! : (parts.first ?? "未知地点")
            let detail = parts.dropFirst().prefix(3).joined(separator: "，")
            return PlaceInfo(title: title,
                             detail: detail,
                             coordinate: GeoCoordinate(latitude: latitude, longitude: longitude))
        } catch {
            return nil
        }
    }
}

// MARK: - 应用设置（持久化到 UserDefaults）

final class AppSettings: ObservableObject {
    @Published var night: Bool { didSet { save(night, "night") } }
    @Published var labels: Bool { didSet { save(labels, "labels") } }
    @Published var relief: Bool { didSet { save(relief, "relief") } }
    @Published var buildings: Bool { didSet { save(buildings, "buildings") } }
    @Published var trees: Bool { didSet { save(trees, "trees") } }
    @Published var atmosphere: Bool { didSet { save(atmosphere, "atmosphere") } }
    @Published var shadows: Bool { didSet { save(shadows, "shadows") } }
    @Published var sphere: Bool { didSet { save(sphere, "sphere") } }
    @Published var engineControls: Bool { didSet { save(engineControls, "engineControls") } }

    init() {
        let d = UserDefaults.standard
        func load(_ key: String, _ fallback: Bool) -> Bool {
            d.object(forKey: "globe." + key) == nil ? fallback : d.bool(forKey: "globe." + key)
        }
        night = load("night", false)
        labels = load("labels", true)
        relief = load("relief", true)
        buildings = load("buildings", true)
        trees = load("trees", true)
        atmosphere = load("atmosphere", true)
        shadows = load("shadows", true)
        sphere = load("sphere", true)
        engineControls = load("engineControls", false)
    }

    private func save(_ value: Bool, _ key: String) {
        UserDefaults.standard.set(value, forKey: "globe." + key)
    }
}

// MARK: - 定位

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: ((CLLocationCoordinate2D) -> Void)?
    var onDenied: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            onDenied?()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            onDenied?()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let coordinate = locations.last?.coordinate {
            onLocation?(coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onDenied?()
    }
}
