# 库街区 Token & DID 提取器 - iOS 插件

这是一个用于库街区 iOS App 的 dylib 插件，可以提取并复制用户的 Token 和 Device ID。

## 功能特性

- ✅ 自动拦截 HTTP 请求头中的 `token` 和 `devCode`
- ✅ 悬浮按钮一键复制（格式：`token,did`）
- ✅ 支持多种存储方式（NSUserDefaults、Keychain、App Group）
- ✅ 详细的提取结果弹窗

## 技术实现

- **核心技术**: Hook NSURLRequest 的 `allHTTPHeaderFields` 方法
- **编译**: 纯 Objective-C，无需 Theos 或 CydiaSubstrate
- **目标**: iOS 11.0+ (arm64)
- **应用**: 库街区 (com.kurogame.kjq)

## 编译方式

### 方法 1: 使用 GitHub Actions（推荐 - 无需 Mac）

1. **在 GitHub 上创建新仓库**
   - 访问 https://github.com/new
   - 仓库名：`KuroTokenExtractor`（或任意名称）
   - 设为 Public

2. **上传项目文件**
   
   方式 A - 使用 Git 命令行：
   ```bash
   cd KuroTokenExtractor
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/你的用户名/KuroTokenExtractor.git
   git push -u origin main
   ```

   方式 B - 使用 GitHub Desktop：
   - 下载安装 GitHub Desktop: https://desktop.github.com/
   - 打开 GitHub Desktop → File → Add Local Repository
   - 选择项目目录
   - 点击 "Publish repository" 按钮

   方式 C - 手动上传（最简单）：
   - 在 GitHub 仓库页面点击 "uploading an existing file"
   - 将项目目录下的所有文件拖入浏览器
   - 点击 "Commit changes"

3. **等待自动编译**
   - 上传后，GitHub Actions 会自动开始编译
   - 进入仓库的 "Actions" 标签页查看进度
   - 编译时间：约 1-2 分钟

4. **下载编译产物**
   - 编译完成后，点击最新的 workflow run
   - 在 "Artifacts" 区域下载 `KuroTokenExtractor-dylib`
   - 解压 ZIP，得到 `KuroTokenExtractor.dylib` 文件

### 方法 2: 本地编译（需要 Mac）

```bash
# 直接使用 clang 编译
clang -arch arm64 \
  -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
  -mios-version-min=11.0 \
  -dynamiclib \
  -framework Foundation \
  -framework UIKit \
  -framework Security \
  -framework CoreGraphics \
  -framework QuartzCore \
  -fobjc-arc \
  -o KuroTokenExtractor.dylib \
  Tweak.m

# 签名
codesign -f -s - KuroTokenExtractor.dylib
```

## 安装方式

### 使用 TrollFools 注入 dylib（推荐 - 无需越狱）

1. **准备工作**
   - 确保设备已安装 TrollStore 和 TrollFools
   - 确保库街区 App 已通过 TrollStore 安装
   - 将编译好的 `KuroTokenExtractor.dylib` 传输到 iOS 设备

2. **使用 TrollFools 注入**
   
   - 打开 TrollFools
   - 找到已安装的"库街区"应用
   - 点击 "导入 Tweak" 或类似选项
   - 选择 `KuroTokenExtractor.dylib`
   - 重启库街区 App（TrollFools 会自动处理）

   **注意**：TrollFools 不需要重新安装 IPA，它直接向已安装的 App 注入 dylib

   方式 B - 手动注入到 IPA（不推荐，TrollFools 更简单）：
   ```bash
   # 1. 解压 IPA
   unzip 库街区.ipa
   
   # 2. 复制 dylib
   mkdir -p Payload/KuroGameBox.app/Frameworks
   cp KuroTokenExtractor.dylib Payload/KuroGameBox.app/Frameworks/
   
   # 3. 重新打包
   zip -r 库街区_patched.ipa Payload/
   
   # 4. 用 TrollStore 安装修改后的 IPA
   ```

### 使用 Filza（需要越狱）

1. 将 `KuroTokenExtractor.dylib` 复制到：
   `/Library/MobileSubstrate/DynamicLibraries/`
2. 创建 plist 文件：
   `/Library/MobileSubstrate/DynamicLibraries/KuroTokenExtractor.plist`
   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Filter</key>
       <dict>
           <key>Bundles</key>
           <array>
               <string>com.kurogame.kjq</string>
           </array>
       </dict>
   </dict>
   </plist>
   ```
3. 运行 `killall -9 SpringBoard` 注销设备
4. 重新打开库街区 App

## 使用方法

1. **启动应用**
   - 安装插件后，打开库街区 App
   - 等待 3 秒，右侧会出现青色毛玻璃悬浮按钮

2. **触发网络请求**
   - 确保已登录账号
   - 刷新页面或进入不同模块，触发几次网络请求
   - 插件会自动拦截 Token 和 DevCode

3. **提取数据**
   - 点击悬浮按钮
   - 弹窗显示提取结果
   - 数据已自动复制到剪贴板，格式：`token,did`

## 输出格式

```
token,devCode
```

例如：
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...,1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6p7q8r9s0t
```

## 技术细节

### Hook 实现

```objc
// Hook NSURLRequest 的 allHTTPHeaderFields
static NSDictionary* hooked_allHTTPHeaderFields(id self, SEL _cmd) {
    NSDictionary *headers = original_allHTTPHeaderFields(self, _cmd);
    
    if (headers && headers.count > 0) {
        if (headers[@"token"]) {
            [g_capturedHeaders setObject:headers[@"token"] forKey:@"token"];
        }
        if (headers[@"devCode"]) {
            [g_capturedHeaders setObject:headers[@"devCode"] forKey:@"devCode"];
        }
    }
    
    return headers;
}
```

### 数据来源优先级

1. **HTTP 请求头拦截**（主要方式）
   - 拦截所有 NSURLRequest 的 HTTP 头
   - 实时捕获 `token` 和 `devCode` 字段

2. **NSUserDefaults 读取**（备用方式）
   - 搜索键：`token`, `user_token`, `userToken`, `TOKEN`
   - 搜索键：`deviceId`, `deviceID`, `identifyId`, `devCode`

3. **Keychain 读取**（备用方式）
   - Service: `com.kurogame.kjq`
   - Account: `token`, `deviceId`

## 调试方法

使用 macOS Console.app 查看日志：

1. 打开 Console.app
2. 连接 iOS 设备
3. 搜索 `[KuroTokenExtractor]`
4. 查看插件运行状态

**日志示例**：
```
[KuroTokenExtractor] Plugin loaded!
[KuroTokenExtractor] ✓ Hook installed successfully!
[KuroTokenExtractor] ✓ Floating button added!
[KuroTokenExtractor] ✓ Token captured
[KuroTokenExtractor] ✓ devCode captured
[KuroTokenExtractor] Result copied (length: 245)
```

## 常见问题

### 1. 悬浮按钮不显示

**原因**：Hook 安装失败或 Window 未准备好

**解决**：
- 检查 TrollFools 是否正确注入插件
- 尝试重启 App

### 2. 点击按钮后显示"未获取"

**原因**：尚未拦截到 Token/DevCode

**解决**：
- 多刷新几次页面
- 进入不同模块（个人中心、帖子列表等）
- 确保网络请求正常发送

### 3. 提取的 Token 为空

**原因**：未登录账号，或 Token 存储位置变化

**解决**：
- 确保已登录库街区账号
- 检查是否是新版本 App（字段名可能变化）

### 4. App 闪退

**原因**：dylib 加载失败或代码错误

**解决**：
- 使用 TrollFools：检查是否正确注入到库街区 App
- 使用 Filza（越狱）：确认 CydiaSubstrate 已安装并正确加载
- 确认 iOS 版本 ≥ 11.0

## 版本兼容性

- **支持的 iOS 版本**: 11.0+（理论上支持所有 iOS 11+ 版本）
- **支持的注入方式**: 
  - TrollFools（推荐，无需越狱）
  - Filza + CydiaSubstrate（需要越狱）
- **支持的库街区版本**: 3.1.0（理论上支持所有版本，只要 API 字段不变）
- **架构**: arm64（iPhone 5s 及以后设备）

## 安全说明

- ✅ 本插件仅在本地运行，不上传任何数据
- ✅ 提取的 Token 仅保存在剪贴板，不写入文件
- ✅ 所有日志仅用于调试，不包含敏感信息完整内容
- ⚠️ Token 是敏感信息，请勿分享给他人
- ⚠️ 复制后的 Token 请及时使用，避免长时间保留在剪贴板

## 免责声明

本插件仅供学习和研究使用，使用者需自行承担使用风险。开发者不对因使用本插件造成的任何损失负责。

请遵守以下原则：
- 仅用于个人账号的 Token 提取
- 不得用于恶意攻击或非法用途
- 尊重库街区的服务条款

## 开源协议

MIT License

## 贡献

欢迎提交 Issue 和 Pull Request！

## 更新日志

### v1.0.0 (2026-06-23)

- ✨ 初始版本发布
- ✨ 支持 Token 和 DevCode 提取
- ✨ 悬浮按钮 UI
- ✨ 多种存储方式支持
- ✨ GitHub Actions 自动编译
