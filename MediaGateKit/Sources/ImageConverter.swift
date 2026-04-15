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
    /// Falls back to CIImage/UIImage when ImageIO cannot decode or write the format.
    private func convertWithImageIO(input: URL, outputDir: URL) throws -> [URL] {
        let ext = input.pathExtension.lowercased()
        let isRAW = Self.rawExtensions.contains(ext)

        // RAW photos: use CoreImage pipeline
        if isRAW {
            return try [processRAW(input: input, outputDir: outputDir)]
        }

        // PCX: not supported by CGImageSource, use custom decoder
        if ext == "pcx" {
            return try [convertPCX(input: input, outputDir: outputDir)]
        }

        let format = SupportedFormats.formatInfo(forExtension: ext)
        let outputExt = format?.outputExtension ?? "png"
        let baseName = input.deletingPathExtension().lastPathComponent

        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            // Fallback: try CIImage for formats CGImageSource can't open
            return try [convertWithCIImageFallback(input: input, outputDir: outputDir, outputExt: outputExt)]
        }

        let outputType = outputExt == "jpeg" ? UTType.jpeg : UTType.png
        let pageCount = CGImageSourceGetCount(source)

        // If CGImageSource reports 0 pages, fall back to CIImage
        if pageCount == 0 {
            return try [convertWithCIImageFallback(input: input, outputDir: outputDir, outputExt: outputExt)]
        }

        var outputURLs: [URL] = []

        for i in 0..<pageCount {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else {
                // Fallback: try CIImage when CGImageSource can read the container but not the image
                if i == 0 {
                    return try [convertWithCIImageFallback(input: input, outputDir: outputDir, outputExt: outputExt)]
                }
                continue
            }

            let suffix = pageCount > 1 ? "_\(i + 1)" : ""
            let outputURL = outputDir.appendingPathComponent("\(baseName)\(suffix).\(outputExt)")

            // Try CGImageDestination first, fall back to UIImage if it fails
            if writeImageWithImageIO(image, to: outputURL, type: outputType) {
                outputURLs.append(outputURL)
            } else if let data = outputExt == "jpeg"
                ? UIImage(cgImage: image).jpegData(compressionQuality: 0.9)
                : UIImage(cgImage: image).pngData() {
                try data.write(to: outputURL, options: .atomic)
                outputURLs.append(outputURL)
            } else {
                throw ImageConversionError.failedToWriteImage
            }
        }

        return outputURLs
    }

    private func writeImageWithImageIO(_ image: CGImage, to url: URL, type: UTType) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// Fallback converter using CIImage for formats that CGImageSource cannot handle.
    private func convertWithCIImageFallback(input: URL, outputDir: URL, outputExt: String) throws -> URL {
        let baseName = input.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName).\(outputExt)")

        guard let ciImage = CIImage(contentsOf: input) else {
            throw ImageConversionError.failedToReadImage
        }

        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            throw ImageConversionError.failedToReadImage
        }

        let uiImage = UIImage(cgImage: cgImage)
        let data: Data?
        if outputExt == "jpeg" {
            data = uiImage.jpegData(compressionQuality: 0.9)
        } else {
            data = uiImage.pngData()
        }

        guard let imageData = data, imageData.count > 100 else {
            throw ImageConversionError.failedToWriteImage
        }

        try imageData.write(to: outputURL, options: .atomic)
        return outputURL
    }

    /// Processes a RAW photo file.
    ///
    /// Strategy (in order of reliability):
    /// 1. ImageIO direct read — iOS 16+ can natively decode many RAW formats
    /// 2. CIRAWFilter → UIImage.jpegData pipeline
    /// 3. CIImage direct load as last resort
    private func processRAW(input: URL, outputDir: URL) throws -> URL {
        let baseName = input.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName).jpeg")
        let quality = ConversionSettings.shared.compressionQuality

        // Strategy 1: ImageIO direct read (most reliable for iOS-supported RAW)
        if let source = CGImageSourceCreateWithURL(input as CFURL, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let uiImage = UIImage(cgImage: cgImage)
            if let data = uiImage.jpegData(compressionQuality: quality), data.count > 1000 {
                try data.write(to: outputURL, options: .atomic)
                return outputURL
            }
        }

        // Strategy 2: CIRAWFilter (best quality for RAW development)
        if let rawFilter = CIRAWFilter(imageURL: input) {
            rawFilter.isGamutMappingEnabled = true
            if let ciOutput = rawFilter.outputImage {
                let context = CIContext()
                let extent = ciOutput.extent
                if let cgImage = context.createCGImage(ciOutput, from: extent) {
                    let uiImage = UIImage(cgImage: cgImage)
                    if let data = uiImage.jpegData(compressionQuality: quality), data.count > 1000 {
                        try data.write(to: outputURL, options: .atomic)
                        return outputURL
                    }
                }
            }
        }

        // Strategy 3: CIFilter with imageURL
        if let filter = CIFilter(imageURL: input, options: [:]),
           let ciOutput = filter.outputImage {
            let context = CIContext()
            if let cgImage = context.createCGImage(ciOutput, from: ciOutput.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                if let data = uiImage.jpegData(compressionQuality: quality), data.count > 1000 {
                    try data.write(to: outputURL, options: .atomic)
                    return outputURL
                }
            }
        }

        // Strategy 4: CIImage direct
        if let ciImage = CIImage(contentsOf: input) {
            let context = CIContext()
            if let cgImage = context.createCGImage(ciImage, from: ciImage.extent) {
                let uiImage = UIImage(cgImage: cgImage)
                if let data = uiImage.jpegData(compressionQuality: quality), data.count > 1000 {
                    try data.write(to: outputURL, options: .atomic)
                    return outputURL
                }
            }
        }

        throw ImageConversionError.failedToReadImage
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

        // Parse header byte-by-byte to avoid ASCII encoding issues with pixel data
        let bytes = Array(data)
        var tokens: [Int] = []
        var offset = 2  // Skip magic number
        var inComment = false
        var currentToken = ""
        let neededTokens = hasMaxVal ? 3 : 2

        while offset < bytes.count && tokens.count < neededTokens {
            let byte = bytes[offset]
            if byte == 0x23 { // '#'
                inComment = true
            } else if byte == 0x0A || byte == 0x0D { // '\n' or '\r'
                inComment = false
                if !currentToken.isEmpty {
                    if let val = Int(currentToken) { tokens.append(val) }
                    currentToken = ""
                }
            } else if !inComment && (byte == 0x20 || byte == 0x09) { // space or tab
                if !currentToken.isEmpty {
                    if let val = Int(currentToken) { tokens.append(val) }
                    currentToken = ""
                }
            } else if !inComment, byte >= 0x30, byte <= 0x39 { // '0'-'9'
                currentToken.append(Character(UnicodeScalar(byte)))
            }
            offset += 1
        }

        if !currentToken.isEmpty && tokens.count < neededTokens {
            if let val = Int(currentToken) { tokens.append(val) }
        }

        guard tokens.count >= 2 else {
            throw ImageConversionError.failedToReadImage
        }

        let width = tokens[0]
        let height = tokens[1]
        let maxVal = hasMaxVal && tokens.count >= 3 ? tokens[2] : 1

        // offset points to the first pixel byte after the header
        let pixelData = data.dropFirst(min(offset, data.count))
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

    // MARK: - PCX

    /// Decodes a PCX image file (ZSoft Paintbrush format).
    /// PCX uses a 128-byte header followed by RLE-compressed pixel data.
    private func convertPCX(input: URL, outputDir: URL) throws -> URL {
        let data = try Data(contentsOf: input)
        guard data.count > 128, data[0] == 0x0A else {
            throw ImageConversionError.failedToReadImage
        }

        let bitsPerPixel = Int(data[3])
        let xMin = Int(data[4]) | (Int(data[5]) << 8)
        let yMin = Int(data[6]) | (Int(data[7]) << 8)
        let xMax = Int(data[8]) | (Int(data[9]) << 8)
        let yMax = Int(data[10]) | (Int(data[11]) << 8)
        let width = xMax - xMin + 1
        let height = yMax - yMin + 1
        let numPlanes = Int(data[65])
        let bytesPerLine = Int(data[66]) | (Int(data[67]) << 8)

        guard width > 0, height > 0, bitsPerPixel == 8, numPlanes >= 1 else {
            throw ImageConversionError.failedToReadImage
        }

        // Decode RLE data
        let scanlineBytes = bytesPerLine * numPlanes
        var decoded = [UInt8]()
        decoded.reserveCapacity(scanlineBytes * height)
        var idx = 128

        while decoded.count < scanlineBytes * height && idx < data.count {
            let byte = data[idx]
            idx += 1
            if byte >= 0xC0 {
                let count = Int(byte & 0x3F)
                guard idx < data.count else { break }
                let value = data[idx]
                idx += 1
                for _ in 0..<count {
                    decoded.append(value)
                }
            } else {
                decoded.append(byte)
            }
        }

        // Convert to RGBA
        var rgbaData = Data(capacity: width * height * 4)

        for y in 0..<height {
            let lineOffset = y * scanlineBytes
            for x in 0..<width {
                let r: UInt8, g: UInt8, b: UInt8
                if numPlanes == 3 {
                    r = (lineOffset + x < decoded.count) ? decoded[lineOffset + x] : 0
                    g = (lineOffset + bytesPerLine + x < decoded.count) ? decoded[lineOffset + bytesPerLine + x] : 0
                    b = (lineOffset + 2 * bytesPerLine + x < decoded.count) ? decoded[lineOffset + 2 * bytesPerLine + x] : 0
                } else {
                    let val = (lineOffset + x < decoded.count) ? decoded[lineOffset + x] : 0
                    r = val; g = val; b = val
                }
                rgbaData.append(r)
                rgbaData.append(g)
                rgbaData.append(b)
                rgbaData.append(255)
            }
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

        let baseName = input.deletingPathExtension().lastPathComponent
        let outputURL = outputDir.appendingPathComponent("\(baseName).png")

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

        return outputURL
    }
}
