// GlobeApp v1 — 全屏 3D 地球仪
// 引擎: ImmersiveMap 0.11.0 (MIT, https://github.com/artembobkin/ImmersiveMap)
// 结构与上游自带 iOS 示例一致: 单文件 App, 只用引擎公开的 SwiftUI API。

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

/// v1 只有一屏: 全屏地球。
/// 拖动旋转、捏合缩放、放大到城市/地名都由引擎内置手势与相机控制提供。
private struct MapScreen: View {
    var body: some View {
        ImmersiveMapView()
            .controlsHidden(false)
            .ignoresSafeArea()
    }
}
