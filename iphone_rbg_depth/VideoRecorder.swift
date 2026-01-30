//
//  VideoRecorder.swift
//  iphone_rbg_depth
//
//  Records RGB and depth video streams to separate files
//

import Foundation
import AVFoundation
import CoreVideo
import Photos

class VideoRecorder {

    // MARK: - Properties

    private var rgbWriter: AVAssetWriter?
    private var rgbInput: AVAssetWriterInput?
    private var rgbAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var depthWriter: AVAssetWriter?
    private var depthInput: AVAssetWriterInput?
    private var depthAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    private var isRecording = false
    private var startTime: CMTime?
    private var frameCount: Int = 0

    private let rgbURL: URL
    private let depthURL: URL

    // Cached depth normalization values
    private var depthMin: Float = 0.5  // Typical near value
    private var depthMax: Float = 5.0  // Typical far value

    // MARK: - Initialization

    init() {
        // Create temporary file URLs
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium).replacingOccurrences(of: ":", with: "-")

        rgbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RGB_\(timestamp).mov")
        depthURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Depth_\(timestamp).mov")
    }

    // MARK: - Recording Control

    func startRecording(rgbWidth: Int, rgbHeight: Int, depthWidth: Int, depthHeight: Int, fps: Int) throws {
        guard !isRecording else {
            print("⚠️ Already recording")
            return
        }

        // Delete old files if they exist
        try? FileManager.default.removeItem(at: rgbURL)
        try? FileManager.default.removeItem(at: depthURL)

        // Setup RGB writer
        rgbWriter = try AVAssetWriter(outputURL: rgbURL, fileType: .mov)

        let rgbSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: rgbWidth,
            AVVideoHeightKey: rgbHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 2_000_000,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        rgbInput = AVAssetWriterInput(mediaType: .video, outputSettings: rgbSettings)
        rgbInput?.expectsMediaDataInRealTime = true
        // Apply 90-degree rotation for portrait orientation
        rgbInput?.transform = CGAffineTransform(rotationAngle: .pi / 2)

        rgbAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: rgbInput!,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )

        if rgbWriter!.canAdd(rgbInput!) {
            rgbWriter!.add(rgbInput!)
        }

        // Setup depth writer (8-bit grayscale - compatible format)
        depthWriter = try AVAssetWriter(outputURL: depthURL, fileType: .mov)

        let depthSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: depthWidth,
            AVVideoHeightKey: depthHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 1_000_000,
                AVVideoExpectedSourceFrameRateKey: fps
            ]
        ]

        depthInput = AVAssetWriterInput(mediaType: .video, outputSettings: depthSettings)
        depthInput?.expectsMediaDataInRealTime = true
        // Apply 90-degree rotation for portrait orientation
        depthInput?.transform = CGAffineTransform(rotationAngle: .pi / 2)

        depthAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: depthInput!,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
        )

        if depthWriter!.canAdd(depthInput!) {
            depthWriter!.add(depthInput!)
        }

        // Start writing
        rgbWriter!.startWriting()
        depthWriter!.startWriting()

        isRecording = true
        startTime = nil
        frameCount = 0

        print("✅ Recording started")
        print("   RGB: \(rgbURL.lastPathComponent)")
        print("   Depth: \(depthURL.lastPathComponent)")
    }

    func stopRecording(completion: @escaping (URL?, URL?, Error?) -> Void) {
        guard isRecording else {
            completion(nil, nil, NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not recording"]))
            return
        }

        isRecording = false

        print("⏹️ Stopping recording... (\(frameCount) frames)")

        // Mark inputs as finished
        rgbInput?.markAsFinished()
        depthInput?.markAsFinished()

        // Keep strong references
        guard let rgbWriterCopy = rgbWriter,
              let depthWriterCopy = depthWriter else {
            completion(nil, nil, NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Writers not initialized"]))
            return
        }

        let rgbURLCopy = rgbURL
        let depthURLCopy = depthURL

        // Wait a bit for final frames to flush
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) {
            // Finish writing RGB
            rgbWriterCopy.finishWriting {
                print("  RGB writer finished with status: \(rgbWriterCopy.status.rawValue)")
                if let error = rgbWriterCopy.error {
                    print("  RGB error: \(error.localizedDescription)")
                }

                // Finish writing depth
                depthWriterCopy.finishWriting {
                    print("  Depth writer finished with status: \(depthWriterCopy.status.rawValue)")
                    if let error = depthWriterCopy.error {
                        print("  Depth error: \(error.localizedDescription)")
                    }

                    if rgbWriterCopy.status == .completed && depthWriterCopy.status == .completed {
                        print("✅ Recording saved successfully")
                        print("   RGB: \(rgbURLCopy.path)")
                        print("   Depth: \(depthURLCopy.path)")
                        completion(rgbURLCopy, depthURLCopy, nil)
                    } else {
                        let error = rgbWriterCopy.error ?? depthWriterCopy.error
                        print("❌ Recording failed: \(error?.localizedDescription ?? "unknown error")")
                        completion(nil, nil, error)
                    }
                }
            }
        }

        // Clear references after completion
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
            self.rgbWriter = nil
            self.depthWriter = nil
            self.rgbInput = nil
            self.depthInput = nil
            self.rgbAdaptor = nil
            self.depthAdaptor = nil
        }
    }

    // MARK: - Frame Writing

    func writeRGBFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isRecording else { return }

        // Set start time from first frame
        if startTime == nil {
            startTime = timestamp
            rgbWriter?.startSession(atSourceTime: timestamp)
            depthWriter?.startSession(atSourceTime: timestamp)
        }

        guard let rgbInput = rgbInput, let rgbAdaptor = rgbAdaptor else { return }

        if rgbInput.isReadyForMoreMediaData {
            rgbAdaptor.append(pixelBuffer, withPresentationTime: timestamp)
            frameCount += 1
        }
    }

    func writeDepthFrame(_ pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard isRecording, startTime != nil else { return }
        guard let depthInput = depthInput, let depthAdaptor = depthAdaptor else { return }

        // Convert Float32 depth to BGRA grayscale for video encoding
        guard let convertedBuffer = convertDepthToBGRA(pixelBuffer) else {
            print("⚠️ Failed to convert depth buffer")
            return
        }

        if depthInput.isReadyForMoreMediaData {
            depthAdaptor.append(convertedBuffer, withPresentationTime: timestamp)
        }
    }

    private func convertDepthToBGRA(_ depthBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthBuffer) else {
            return nil
        }

        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)

        // Create BGRA pixel buffer
        var outputBuffer: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!
        ] as CFDictionary

        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &outputBuffer
        )

        guard status == kCVReturnSuccess, let output = outputBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }

        guard let outputAddress = CVPixelBufferGetBaseAddress(output) else {
            return nil
        }

        let outputPtr = outputAddress.assumingMemoryBound(to: UInt8.self)
        let outputStride = CVPixelBufferGetBytesPerRow(output)

        // Use fixed depth range for speed (0.5m to 5m is typical)
        let depthRange = depthMax - depthMin

        // Fast conversion using stride-based access
        for y in 0..<height {
            let rowOffset = y * outputStride
            for x in 0..<width {
                let depth = floatBuffer[y * width + x]

                let normalized: UInt8
                if depth > 0 {
                    // Clamp and normalize
                    let clamped = min(max(depth, depthMin), depthMax)
                    let value = (clamped - depthMin) / depthRange
                    normalized = UInt8((1.0 - value) * 255.0)  // Inverted: close=dark
                } else {
                    normalized = 0  // Invalid depth = black
                }

                let pixelOffset = rowOffset + x * 4
                outputPtr[pixelOffset] = normalized      // B
                outputPtr[pixelOffset + 1] = normalized  // G
                outputPtr[pixelOffset + 2] = normalized  // R
                outputPtr[pixelOffset + 3] = 255         // A
            }
        }

        return output
    }

    func getIsRecording() -> Bool {
        return isRecording
    }

    func getFrameCount() -> Int {
        return frameCount
    }

    // MARK: - Save to Photos

    static func saveToPhotos(rgbURL: URL, depthURL: URL, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                completion(false, NSError(domain: "VideoRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Photos access denied"]))
                return
            }

            PHPhotoLibrary.shared().performChanges({
                // Save RGB video
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: rgbURL)

                // Save depth video
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: depthURL)

            }) { success, error in
                if success {
                    print("✅ Videos saved to Photos library")

                    // Clean up temporary files
                    try? FileManager.default.removeItem(at: rgbURL)
                    try? FileManager.default.removeItem(at: depthURL)
                } else {
                    print("❌ Failed to save to Photos: \(error?.localizedDescription ?? "unknown error")")
                }

                completion(success, error)
            }
        }
    }
}
