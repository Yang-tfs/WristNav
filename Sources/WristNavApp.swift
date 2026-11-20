import SwiftUI
import AVFoundation

@main
struct WristNavApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// 静音音频播放器：iOS 后台常驻的关键技巧
/// 循环播放一段无声音频，让系统认为 App 正在播放媒体，
/// 从而避免导航过程中被系统挂起（定位更新中断）。
final class SilentAudioPlayer {
    static let shared = SilentAudioPlayer()
    private var player: AVAudioPlayer?

    func start() {
        guard player == nil else { return }
        // 构造 1 秒静音 WAV（AVAudioPlayer 需要容器格式，不能是裸 PCM）
        let sampleRate = UInt32(44100)
        let channels: UInt16 = 1
        let bits: UInt16 = 16
        let frameCount = sampleRate
        let dataSize = frameCount * UInt32(channels) * UInt32(bits / 8)
        let byteRate = sampleRate * UInt32(channels) * UInt32(bits / 8)
        let blockAlign = channels * (bits / 8)

        var wav = [UInt8]()
        wav.append(contentsOf: Array("RIFF".utf8))
        wav.append(contentsOf: u32(36 + dataSize))
        wav.append(contentsOf: Array("WAVE".utf8))
        wav.append(contentsOf: Array("fmt ".utf8))
        wav.append(contentsOf: u32(16))
        wav.append(contentsOf: u16(1))            // PCM
        wav.append(contentsOf: u16(channels))
        wav.append(contentsOf: u32(sampleRate))
        wav.append(contentsOf: u32(byteRate))
        wav.append(contentsOf: u16(blockAlign))
        wav.append(contentsOf: u16(bits))
        wav.append(contentsOf: Array("data".utf8))
        wav.append(contentsOf: u32(dataSize))
        wav.append(contentsOf: [UInt8](repeating: 0, count: Int(dataSize)))

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            player = try AVAudioPlayer(data: Data(wav))
            player?.numberOfLoops = -1
            player?.volume = 0.0
            player?.prepareToPlay()
            player?.play()
        } catch {
            print("[WristNav] 静音音频启动失败: \(error.localizedDescription)")
        }
    }

    private func u16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8(value >> 8)]
    }

    private func u32(_ value: UInt32) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF),
         UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SilentAudioPlayer.shared.start()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        SilentAudioPlayer.shared.start()
    }
}
