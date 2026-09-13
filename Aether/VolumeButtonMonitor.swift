import UIKit
import AVFoundation
import MediaPlayer

/// Hardware volume-button bridge.
/// Volume UP → show overlay; Volume DOWN → hide overlay.
/// Silent audio + MPVolumeView restore keep events firing at 0% / 100%.
final class VolumeButtonMonitor {
    var onVolumeUp: (() -> Void)?
    var onVolumeDown: (() -> Void)?

    private var session: AVAudioSession { .sharedInstance() }
    private var observation: NSKeyValueObservation?
    private var silentPlayer: AVAudioPlayer?
    private var volumeView: MPVolumeView?
    private var lastVolume: Float = 0.5
    private var running = false
    private var swallow = false

    func start() {
        guard !running else { return }
        running = true

        // Keep session active so outputVolume KVO fires.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        playSilentLoopIfNeeded()
        attachHiddenVolumeView()

        lastVolume = session.outputVolume
        observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            self?.handle(change: change)
        }
    }

    func stop() {
        guard running else { return }
        running = false
        observation?.invalidate()
        observation = nil
        silentPlayer?.stop()
        silentPlayer = nil
        volumeView?.removeFromSuperview()
        volumeView = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func handle(change: NSKeyValueObservedChange<Float>) {
        guard running, !swallow else { return }
        guard let neu = change.newValue, let old = change.oldValue else { return }
        let delta = neu - old
        if abs(delta) < 0.01 { return }

        if neu > old {
            onVolumeUp?()
        } else if neu < old {
            onVolumeDown?()
        }

        lastVolume = neu
        // Restore so the next press is always a real change.
        DispatchQueue.main.async { [weak self] in
            self?.restoreVolume()
        }
    }

    private func restoreVolume() {
        guard let slider = systemVolumeSlider() else { return }
        swallow = true
        // Park volume mid-range so both + and − always produce events.
        slider.value = 0.5
        lastVolume = 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.swallow = false
        }
    }

    private func attachHiddenVolumeView() {
        guard volumeView == nil else { return }
        let v = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 1, height: 1))
        v.isHidden = true
        v.alpha = 0.01
        if let w = keyWindow() {
            w.addSubview(v)
        }
        volumeView = v
    }

    private func systemVolumeSlider() -> UISlider? {
        if volumeView == nil { attachHiddenVolumeView() }
        return volumeView?.subviews.compactMap { $0 as? UISlider }.first
    }

    private func playSilentLoopIfNeeded() {
        guard silentPlayer == nil else { return }
        // 1-frame-ish silent wav generated at runtime (44-byte header + zeros).
        let url = writeSilentWav()
        silentPlayer = try? AVAudioPlayer(contentsOf: url)
        silentPlayer?.volume = 0.01
        silentPlayer?.numberOfLoops = -1
        silentPlayer?.play()
    }

    private func writeSilentWav() -> URL {
        let sampleRate = 8000
        let samples = 800
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + samples * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        u32(16)
        u16(1)          // PCM
        u16(1)          // mono
        u32(UInt32(sampleRate))
        u32(UInt32(sampleRate * 2))
        u16(2)
        u16(16)
        data.append(contentsOf: Array("data".utf8))
        u32(UInt32(samples * 2))
        data.append(Data(count: samples * 2))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("silent_vol.wav")
        try? data.write(to: url)
        return url
    }

    private func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for s in scenes {
            if let w = s.windows.first(where: { $0.isKeyWindow }) { return w }
            if let w = s.windows.first { return w }
        }
        return UIApplication.shared.windows.first
    }
}
