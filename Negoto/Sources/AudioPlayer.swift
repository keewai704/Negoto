import AVFoundation
import Foundation
import NegotoCore

/// Plays a card's sounds and text-to-speech in sequence, like Anki's audio queue.
@MainActor
final class AudioPlayer: NSObject, AVAudioPlayerDelegate, AVSpeechSynthesizerDelegate {
    private var queue: [AVTag] = []
    private var player: AVAudioPlayer?
    private var avPlayer: AVPlayer?
    private var avPlayerObserver: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()
    private var mediaFolder: URL?
    private var resolver: MediaResolver?
    private var oggCache: [String: Data] = [:]

    override init() {
        super.init()
        synthesizer.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    func configure(mediaFolder: URL, resolver: MediaResolver) {
        self.mediaFolder = mediaFolder
        self.resolver = resolver
    }

    /// Replaces whatever is playing with the given tags (videos are shown inline instead).
    func play(_ tags: [AVTag]) {
        stop()
        queue = tags.filter { tag in
            if case .sound(let f) = tag { return !CardPage.isVideo(f) }
            return true
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        playNext()
    }

    func stop() {
        queue = []
        player?.stop()
        player = nil
        avPlayer?.pause()
        avPlayer = nil
        if let o = avPlayerObserver { NotificationCenter.default.removeObserver(o) }
        avPlayerObserver = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    private func playNext() {
        guard !queue.isEmpty else { return }
        let tag = queue.removeFirst()
        switch tag {
        case .sound(let filename):
            if !playSound(filename) { playNext() }
        case .tts(let text, let lang, let voices, let speed):
            speak(text, lang: lang, voices: voices, speed: speed)
        }
    }

    private func playSound(_ filename: String) -> Bool {
        guard let folder = mediaFolder else { return false }
        let name = resolver?.resolve(filename) ?? filename
        let url = folder.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        if let p = try? AVAudioPlayer(contentsOf: url), p.duration > 0 {
            start(p)
            return true
        }
        // Ogg Vorbis isn't supported by AVFoundation: decode it ourselves.
        if let wav = oggCache[name] ?? decodeOgg(url) {
            oggCache[name] = wav
            if let p = try? AVAudioPlayer(data: wav) {
                start(p)
                return true
            }
        }
        // Last resort: AVPlayer handles a few more container formats.
        let item = AVPlayerItem(url: url)
        let av = AVPlayer(playerItem: item)
        avPlayerObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.playNext() }
        }
        avPlayer = av
        av.play()
        return true
    }

    private func decodeOgg(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), OggVorbis.isOgg(data) else { return nil }
        return OggVorbis.decodeToWAV(data)
    }

    private func start(_ p: AVAudioPlayer) {
        player = p
        p.delegate = self
        p.prepareToPlay()
        p.play()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.playNext() }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in self.playNext() }
    }

    private func speak(_ text: String, lang: String, voices: [String], speed: Double) {
        let utterance = AVSpeechUtterance(string: text)
        let bcp47 = lang.replacingOccurrences(of: "_", with: "-")
        let all = AVSpeechSynthesisVoice.speechVoices()
        var voice: AVSpeechSynthesisVoice?
        for wanted in voices {
            let short = wanted.replacingOccurrences(of: "Apple_", with: "").replacingOccurrences(of: "_", with: " ")
            voice = all.first { $0.identifier == wanted || $0.name == wanted || $0.name == short }
            if voice != nil { break }
        }
        if voice == nil, !bcp47.isEmpty {
            let matching = all.filter { $0.language.lowercased() == bcp47.lowercased() }
            voice = matching.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: bcp47)
            if voice == nil, let langOnly = bcp47.split(separator: "-").first {
                voice = all.first { $0.language.lowercased().hasPrefix(langOnly.lowercased()) }
            }
        }
        utterance.voice = voice
        let rate = Double(AVSpeechUtteranceDefaultSpeechRate) * speed
        utterance.rate = Float(min(max(rate, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.playNext() }
    }
}
