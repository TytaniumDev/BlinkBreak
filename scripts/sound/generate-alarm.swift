#!/usr/bin/env swift
//
// generate-alarm.swift
//
// Synthesizes a ~28-second pulsing two-tone alarm pattern and writes it to
// BlinkBreak/Resources/Sounds/break-alarm.caf. Run from the repo root:
//
//     swift scripts/sound/generate-alarm.swift
//
// iOS caps custom UNNotificationSound files at 30 seconds, so we stay safely under.
//

import Foundation
import AVFoundation

// MARK: - Parameters

let sampleRate: Double = 44100
let totalDuration: Double = 28.0
let totalFrames = Int(sampleRate * totalDuration)

// Each "beep cycle" is two short tones + rest:
//   beep1 (800 Hz) : 150 ms
//   gap            : 100 ms
//   beep2 (1000 Hz): 150 ms
//   rest           : 800 ms
// Total cycle: 1200 ms → 23 full cycles + a partial cycle in 28 s.
let beepDur: Double = 0.15
let beepGap: Double = 0.10
let restDur: Double = 0.80
let cycleDur: Double = beepDur + beepGap + beepDur + restDur  // 1.2 s
let freq1: Double = 800
let freq2: Double = 1000
let amplitude: Double = 0.5
let fadeDur: Double = 0.010  // 10 ms fade in/out to avoid click artifacts

// MARK: - Audio buffer

guard let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: sampleRate,
    channels: 1,
    interleaved: false
) else {
    fatalError("Failed to build audio format")
}

guard let buffer = AVAudioPCMBuffer(
    pcmFormat: format,
    frameCapacity: AVAudioFrameCount(totalFrames)
) else {
    fatalError("Failed to build audio buffer")
}
buffer.frameLength = AVAudioFrameCount(totalFrames)

guard let samples = buffer.int16ChannelData?[0] else {
    fatalError("Failed to get channel data")
}

// MARK: - Synthesis

func envelope(_ t: Double, duration: Double) -> Double {
    if t < fadeDur { return t / fadeDur }
    if t > duration - fadeDur { return max(0, (duration - t) / fadeDur) }
    return 1.0
}

for i in 0..<totalFrames {
    let t = Double(i) / sampleRate
    let cycle = t.truncatingRemainder(dividingBy: cycleDur)
    var sample: Double = 0

    if cycle < beepDur {
        // First beep — 800 Hz
        let env = envelope(cycle, duration: beepDur)
        sample = env * amplitude * sin(2 * .pi * freq1 * t)
    } else if cycle < beepDur + beepGap {
        // Gap between beeps
        sample = 0
    } else if cycle < 2 * beepDur + beepGap {
        // Second beep — 1000 Hz
        let local = cycle - beepDur - beepGap
        let env = envelope(local, duration: beepDur)
        sample = env * amplitude * sin(2 * .pi * freq2 * t)
    } else {
        // Rest
        sample = 0
    }

    samples[i] = Int16(max(-1, min(1, sample)) * 32767)
}

// MARK: - Write to CAF

let repoRoot = FileManager.default.currentDirectoryPath
let outputURL = URL(fileURLWithPath: repoRoot)
    .appendingPathComponent("BlinkBreak/Resources/Sounds/break-alarm.caf")

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let outputSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM,
    AVSampleRateKey: sampleRate,
    AVNumberOfChannelsKey: 1,
    AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false,
    AVLinearPCMIsBigEndianKey: false,
    AVLinearPCMIsNonInterleaved: false
]

let file = try AVAudioFile(
    forWriting: outputURL,
    settings: outputSettings,
    commonFormat: .pcmFormatInt16,
    interleaved: false
)
try file.write(from: buffer)

print("✓ Wrote \(outputURL.path)")
print("  Duration: \(totalDuration)s")
print("  Frames: \(totalFrames)")
