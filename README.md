# TapVoice

将 8BitDo Micro（推荐 K / Keyboard 档）变成低延迟声音触发器的 Android 应用。

## 当前能力

- 14 个手柄热区，已录音按键显示绿色状态点，实体按键触发时提供 UI 反馈。
- 主界面固定横屏，使用蓝色手柄视觉资产，点击态与录音态由 Flutter UI 叠加状态环反馈。
- 使用系统麦克风录制 AAC `.m4a`，每段最多 10 秒；音频和按键映射保存在应用私有目录及 SharedPreferences。
- Android 无障碍服务只消费已绑定的 `KeyEvent`，由 `SoundPool` 预加载并播放短音频。
- 可在应用内开启后台前台服务、通知权限和无障碍权限。

## 使用方式

1. 将 8BitDo Micro 切换到 **K 档**并通过蓝牙连接 Android 手机。
2. 在 TapVoice 中选中虚拟按键，点击“录制”，完成录音后会回到该按键的选中状态；如需试听请点击“Play”。
3. 点击“去开启”，在系统设置中授权 TapVoice 的无障碍服务；同时允许通知权限以显示后台待命通知。
4. 切至后台后按下已绑定的实体按键进行触发。

> 不同手机厂商的锁屏与电池策略可能限制无障碍服务。实机测试时请为 TapVoice 关闭电池优化，并确认手柄处于 K 档。

## 本地开发

TapVoice 当前只构建 Android 平台。首次运行前请准备：

- Flutter stable（项目要求 Dart `^3.11.4`）
- Android Studio、Android SDK 和 JDK 17+
- Android 模拟器或已开启 USB 调试的 Android 真机

在项目根目录执行：

```bash
flutter doctor
flutter pub get
flutter devices
flutter run -d <Android设备ID>
```

如果只有一个可用设备，也可以直接运行 `flutter run`。启动后：

- `r`：热重载 Flutter 界面
- `R`：热重启 Flutter 应用
- `q`：停止开发服务

修改 `android/` 下的 Kotlin、Manifest 或权限配置后，需要停止并重新执行 `flutter run`，热重载不会重新加载原生代码。

### 真机联调

先在手机打开“开发者选项”和“USB 调试”，连接后确认：

```bash
adb devices
flutter devices
```

首次启动时允许麦克风和通知权限；在应用内点击“去开启”，授权 TapVoice 无障碍服务。然后将 8BitDo Micro 切到 K 档并在系统蓝牙中连接。模拟器可以验证 UI 和录音，但不能替代实体手柄的后台/锁屏按键测试。

### 质量检查与打包

```bash
flutter analyze
flutter test
flutter build apk --debug
```

如果 Gradle 缓存或依赖状态异常，可先执行 `flutter clean && flutter pub get` 后重试。后台/锁屏能力还需要在目标 Android 机型上关闭电池优化并进行实测。
