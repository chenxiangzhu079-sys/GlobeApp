# 地球仪 GlobeApp v1

基于开源引擎 [ImmersiveMap](https://github.com/artembobkin/ImmersiveMap) 0.11.0（MIT）的 iPhone 3D 地球仪 App。
第一版只有一屏：全屏地球，拖动旋转、捏合缩放，可一路放大到城市与地名标注（细节需联网加载）。

## 你需要做的（约 10 分钟，之后每次更新重复第 3~5 步）

### 1. 建 GitHub 仓库
- 登录 github.com（没有账号先免费注册一个）
- 右上角 **+ → New repository**，名字填 `GlobeApp`，可见性选 **Public**（Public 不消耗 Actions 额度），点 Create

### 2. 上传本工程
- 把收到的工程压缩包在电脑上**解压**
- 仓库页面点 **Add file → Upload files**，把解压出的**全部文件和文件夹**拖进去（包括 `.github` 文件夹，它是构建配置所在，千万别漏），点 **Commit changes**
- 上传后确认仓库首页能看到 `.github`、`GlobeApp`、`GlobeApp.xcodeproj` 三项

### 3. 等云端构建
- 打开仓库的 **Actions** 页，会看到一条正在跑的 “Build unsigned IPA”（上传即自动触发；以后也可在这页点 **Run workflow** 手动跑）
- 第一次要现下载引擎包并编译，预计 10~30 分钟；等它变成绿勾 ✅
- 如果变红叉 ❌，把失败那一步的日志截图发我

### 4. 下载 IPA
- 点进这次运行记录 → 页面底部 **Artifacts** → 下载 `GlobeApp-v1-unsigned-ipa`
- 解压得到 `GlobeApp-v1-unsigned.ipa`

### 5. 装到 iPhone
- 打开电脑上的 **iLoader**（装 LiveContainer 用过的那个），选择这个 IPA 安装到 iPhone
- 手机上出现「地球仪」App，打开、允许联网，等地球加载出来
- 能拖动旋转、捏合放大到城市 = v1 成功；有任何报错或黑屏，截图发我

## 工程说明（给后续维护看）
- `GlobeApp/GlobeApp.swift` — 全部 App 代码（单文件，结构与上游自带 iOS 示例一致）
- `GlobeApp.xcodeproj` — 由上游示例工程改造：包依赖从本地路径改为远程锁定 `exactVersion 0.11.0`，Bundle ID `com.muse.globeapp`，显示名「地球仪」，手动签名（CI 关闭签名出未签名 IPA）
- `.github/workflows/build.yml` — macos-26 云端构建：`xcodebuild` 编 iphoneos Release → 打包 Payload → 上传未签名 IPA
- 数据署名：地图为 OpenStreetMap（ODbL）/ RESOLVE / Mapterhorn 数据，引擎内置署名徽章会按缩放级别自动显示
