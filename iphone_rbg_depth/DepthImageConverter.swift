//
//  DepthImageConverter.swift
//  iphone_rbg_depth
//
//  Utility for converting depth CVPixelBuffers to UIImages
//

import UIKit
import CoreVideo
import Accelerate

class DepthImageConverter {

    /// Converts a CVPixelBuffer (depth map) to a grayscale UIImage
    /// - Parameter depthPixelBuffer: The depth data from ARFrame.sceneDepth?.depthMap
    /// - Returns: UIImage representation of depth (closer = darker, farther = lighter)
    static func convertDepthToImage(_ depthPixelBuffer: CVPixelBuffer) -> UIImage? {
        CVPixelBufferLockBaseAddress(depthPixelBuffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthPixelBuffer, .readOnly)
        }

        let width = CVPixelBufferGetWidth(depthPixelBuffer)
        let height = CVPixelBufferGetHeight(depthPixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthPixelBuffer) else {
            return nil
        }

        // Depth data is Float32 (meters)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let count = width * height

        // Find min and max depth for normalization
        var minValue: Float = .infinity
        var maxValue: Float = 0.0

        for i in 0..<count {
            let value = floatBuffer[i]
            if value.isFinite && value > 0 {
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
            }
        }

        // Handle edge case
        if minValue == .infinity || maxValue == 0 {
            minValue = 0
            maxValue = 10.0
        }

        // Create grayscale image (8-bit per pixel)
        let bytesPerRow = width
        var grayscaleData = [UInt8](repeating: 0, count: count)

        let range = maxValue - minValue

        for i in 0..<count {
            let depth = floatBuffer[i]

            if depth.isFinite && depth > 0 {
                // Normalize to 0-255 (inverted: closer = darker)
                let normalized = (depth - minValue) / range
                let inverted = 1.0 - normalized  // Invert so close = dark
                grayscaleData[i] = UInt8(inverted * 255.0)
            } else {
                // Invalid depth = black
                grayscaleData[i] = 0
            }
        }

        // Create CGImage from grayscale data
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        guard let context = CGContext(
            data: &grayscaleData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        guard let cgImage = context.makeImage() else {
            return nil
        }

        // Rotate 90 degrees for portrait orientation
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }

    /// Converts RGB CVPixelBuffer to UIImage
    /// - Parameter pixelBuffer: The RGB pixel buffer from ARFrame.capturedImage
    /// - Returns: UIImage representation
    static func convertRGBToImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        // Rotate 90 degrees for portrait orientation
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
}
