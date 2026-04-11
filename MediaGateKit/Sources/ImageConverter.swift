// This file is part of MediaGate.
// Copyright © 2025 Kemal Sanlı
//
// MediaGate is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// MediaGate is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
// A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// MediaGate. If not, see <https://www.gnu.org/licenses/>.

import Foundation
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
import WebKit

/// A type that can convert image files to PNG or JPEG.
public protocol ImageConverting: Sendable {
    /// Converts an image file to the appropriate output format.
    ///
    /// Returns an array because multi-page formats (e.g., TIFF) produce
    /// multiple output images.
    ///
    /// - Parameters:
    ///   - input: The source image file URL.
    ///   - outputDir: The directory where converted images should be written.
    /// - Returns: An array of URLs pointing to the converted images.
    func convert(input: URL, outputDir: URL) async throws -> [URL]
}


/// Errors specific to image conversion.
public enum ImageConversionError: LocalizedError, Sendable {
    case failedToCreateImageSource
    case failedToReadImage
    case failedToCreateDestination
    case failedToWriteImage
    case svgRenderingFailed
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .failedToCreateImageSource:
            return "Could not read the image file."
        case .failedToReadImage:
            return "Could not decode the image data."
        case .failedToCreateDestination:
            return "Could not create the output image file."
        case .failedToWriteImage:
            return "Could not write the converted image."
        case .svgRenderingFailed:
            return "SVG rendering failed."
        case .unsupportedFormat(let ext):
            return "Unsupported image format: \(ext)"
        }
    }
}

/// Converts images using Apple-native frameworks: ImageIO, CoreImage, and
/// WKWebView (for SVG rasterization).
public final class NativeImageConverter: ImageConverting, @unchecked Sendable {

    public init() {}

    public func convert(input: URL, outputDir: URL) async throws -> [URL] {
        let ext = input.pathExtension.lowercased()

        switch ext {
        case "svg":
            return try await convertSVG(input: input, outputDir: outputDir)
        case "psd":
            return try await convertPSD(input: input, outputDir: outputDir)
        case "ppm", "pgm", "pbm":
            return try convertNetPBM(input: input, outputDir: outputDir)
        default:
            return try convertWithImageIO(input: input, outputDir: outputDir)
        }
    }

    // MARK: - ImageIO (BMP, WebP, TIFF, TGA, ICO, RAW, PCX)

    /// All RAW photo extensions for detection.
    private static let rawExtensions: Set<String> = [
        "cr2", "nef", "arw", "dng", "orf", "rw2", "raf", "pef",
        "srw", "x3f", "3fr", "erf", "kdc", "mrw", "dcr"
    ]

    /// Converts images using ImageIO. Handles single and multi-page images.
    private func convertWithImageIO(input: URL, outputDir: URL) throws -> [URL] {
        let ext = input.pathExtension.lowercased()
        let isRAW = Self.rawExtensions.contains(ext)

        // RAW photos: use CoreImage pipeline
        if isRAW {
            return try [processRAW(input: input, outputDir: outputDir)]
        }

        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            throw ImageConversionError.failedToCreateImageSource
        }

        let format = SupportedFormats.formatInfo(forExtension: ext)
        let outputExt = format?.outputExtension ?? "png"
        let outputType = outputExt == "jpeg" ? UTType.jpeg : UTType.png
        let pageCount = CGImageSourceGetCount(source)
        let baseName = input.deletingPathExtension().lastPathComponent

        var outputURLs: [URL] = []

        for i in 0..<pageCount {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                throw ImageConversionError.failedToReadImage
            }

            let suffix = pageCount > 1 ? "_\(i + 1)" : ""
            let outputURL = outputDir.appendingPathComponent("\(baseName)\(suffix).\(outputExt)")

            guard let dest = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                outputType.identifier as CFString,
                1,
                nil
            ) else {
                throw ImageConversionError.failedToCreateDestination
            }

            CGImageDestinationAddImage(dest, image, nil)

            guard CGImageDestinationFinalize(dest) else {
                throw ImageConversionError.failedToWriteImage
            }

            outputURLs.append(outputURL)
        }

        return outputURLs
    }

    /// Processes a RAW photo using CoreImage with the actual file URL.
    private func processRAW(input: URL, outputDir: URL) throws -> URL {
        let ciImage: CIImage?

        // Try CIRAWFilter (iOS 15+) first, then CIFilter, then CIImage direct
        if let rawFilter = CIRAWFilter(imageURL: input) {
            ciImage = rawFilter.outputImage
        } else if let filter = CIFilter(imageURL: input, options: [:]) {
            ciImage = filter.outputImage
        } else {
            ciImage = CIImage(contentsOf: input)
        }

        guard let image = ciImage else {
            throw ImageConversionError.failedToReadImage
        }

        let context = CIContext()
        let baseName = input.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName).jpeg")

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImageConversionError.failedToWriteImage
        }

        do {
            try context.writeJPEGRepresentation(
                of: image,
                to: outputURL,
                colorSpace: colorSpace,
                options: [:]
            )
        } catch {
            throw ImageConversionError.failedToWriteImage
        }

        return outputURL
    }

    // MARK: - SVG (WKWebView snapshot)

    /// Rasterizes an SVG file by loading it in an offscreen WKWebView and
    /// taking a snapshot.
    @MainActor
    private func convertSVG(input: URL, outputDir: URL) async throws -> [URL] {
        let svgData = try Data(contentsOf: input)
        guard let svgString = String(data: svgData, encoding: .utf8) else {
            throw ImageConversionError.svgRenderingFailed
        }

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024))
        webView.isOpaque = false
        webView.backgroundColor = .clear

        let html = """
        <!DOCTYPE html>
        <html>
        <head><style>body{margin:0;display:flex;align-items:center;justify-content:center;background:transparent;}</style></head>
        <body>\(svgString)</body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: input.deletingLastPathComponent())

        // Wait for the page to finish loading
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                continuation.resume()
            }
        }

        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = true

        let image = try await webView.takeSnapshot(configuration: config)

        let baseName = input.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName).png")

        guard let pngData = image.pngData() else {
            throw ImageConversionError.failedToWriteImage
        }

        try pngData.write(to: outputURL, options: .atomic)
        return [outputURL]
    }

    // MARK: - PSD (CoreImage flatten)

    /// Converts a PSD file by flattening it with CoreImage.
    private func convertPSD(input: URL, outputDir: URL) async throws -> [URL] {
        guard let ciImage = CIImage(contentsOf: input) else {
            throw ImageConversionError.failedToReadImage
        }

        let context = CIContext()
        let baseName = input.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName).png")

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw ImageConversionError.failedToReadImage
        }

        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageConversionError.failedToCreateDestination
        }

        CGImageDestinationAddImage(dest, cgImage, nil)

        guard CGImageDestinationFinalize(dest) else {
            throw ImageConversionError.failedToWriteImage
        }

        return [outputURL]
    }

    // MARK: - NetPBM (PPM/PGM/PBM)

    /// Decodes PPM, PGM, or PBM files (Netpbm format family).
    ///
    /// These are simple bitmap formats with a text header followed by
    /// raw pixel data.
    private func convertNetPBM(input: URL, outputDir: URL) throws -> [URL] {
        let data = try Data(contentsOf: input)
        guard data.count > 3 else {
            throw ImageConversionError.failedToReadImage
        }

        let header = String(data: data.prefix(2), encoding: .ascii) ?? ""
        let baseName = input.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName).png")

        // Parse the NetPBM header to extract width, height, and max value
        let parsed = try parseNetPBMHeader(data: data, magicNumber: header)
        let cgImage = try createCGImageFromNetPBM(
            pixelData: parsed.pixelData,
            width: parsed.width,
            height: parsed.height,
            components: parsed.components,
            maxVal: parsed.maxVal
        )

        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageConversionError.failedToCreateDestination
        }

        CGImageDestinationAddImage(dest, cgImage, nil)

        guard CGImageDestinationFinalize(dest) else {
            throw ImageConversionError.failedToWriteImage
        }

        return [outputURL]
    }

    private struct NetPBMHeader {
        let width: Int
        let height: Int
        let maxVal: Int
        let components: Int
        let pixelData: Data
    }

    private func parseNetPBMHeader(data: Data, magicNumber: String) throws -> NetPBMHeader {
        // Binary formats: P4 (PBM), P5 (PGM), P6 (PPM)
        let components: Int
        let hasMaxVal: Bool

        switch magicNumber {
        case "P4":
            components = 1; hasMaxVal = false
        case "P5":
            components = 1; hasMaxVal = true
        case "P6":
            components = 3; hasMaxVal = true
        default:
            throw ImageConversionError.unsupportedFormat("NetPBM \(magicNumber)")
        }

        guard let headerString = String(data: data.prefix(min(data.count, 256)), encoding: .ascii) else {
            throw ImageConversionError.failedToReadImage
        }

        // Skip magic number and parse width, height, maxval
        var tokens: [Int] = []
        var offset = 0
        var inComment = false
        var currentToken = ""
        let chars = Array(headerString)
        var headerByteCount = 0
        let neededTokens = hasMaxVal ? 3 : 2

        // Skip magic number
        offset = 2

        while offset < chars.count && tokens.count < neededTokens {
            let ch = chars[offset]
            if ch == "#" {
                inComment = true
            } else if ch == "\n" || ch == "\r" {
                inComment = false
                if !currentToken.isEmpty {
                    if let val = Int(currentToken) { tokens.append(val) }
                    currentToken = ""
                }
            } else if !inComment && (ch == " " || ch == "\t") {
                if !currentToken.isEmpty {
                    if let val = Int(currentToken) { tokens.append(val) }
                    currentToken = ""
                }
            } else if !inComment {
                currentToken.append(ch)
            }
            offset += 1
        }

        if !currentToken.isEmpty && tokens.count < neededTokens {
            if let val = Int(currentToken) { tokens.append(val) }
        }

        // The header ends after the final whitespace following the last token
        headerByteCount = offset + 1 // +1 for the whitespace after the last token

        guard tokens.count >= 2 else {
            throw ImageConversionError.failedToReadImage
        }

        let width = tokens[0]
        let height = tokens[1]
        let maxVal = hasMaxVal && tokens.count >= 3 ? tokens[2] : 1

        let pixelData = data.dropFirst(min(headerByteCount, data.count))
        return NetPBMHeader(
            width: width,
            height: height,
            maxVal: maxVal,
            components: components,
            pixelData: Data(pixelData)
        )
    }

    private func createCGImageFromNetPBM(
        pixelData: Data,
        width: Int,
        height: Int,
        components: Int,
        maxVal: Int
    ) throws -> CGImage {
        // Normalize to 8-bit RGBA
        var rgbaData = Data(capacity: width * height * 4)
        let bytes = Array(pixelData)
        var idx = 0

        for _ in 0..<(width * height) {
            let r: UInt8
            let g: UInt8
            let b: UInt8

            if components == 3 {
                guard idx + 2 < bytes.count else { break }
                r = UInt8(min(Int(bytes[idx]) * 255 / max(maxVal, 1), 255))
                g = UInt8(min(Int(bytes[idx + 1]) * 255 / max(maxVal, 1), 255))
                b = UInt8(min(Int(bytes[idx + 2]) * 255 / max(maxVal, 1), 255))
                idx += 3
            } else {
                guard idx < bytes.count else { break }
                let val = UInt8(min(Int(bytes[idx]) * 255 / max(maxVal, 1), 255))
                r = val; g = val; b = val
                idx += 1
            }

            rgbaData.append(r)
            rgbaData.append(g)
            rgbaData.append(b)
            rgbaData.append(255) // alpha
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider = CGDataProvider(data: rgbaData as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw ImageConversionError.failedToReadImage
        }

        return cgImage
    }
}
