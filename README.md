# MediaGate

**Universal Media Converter for iOS** — Share Extension that converts unsupported media formats on-device and saves to Photos.

Share an MKV, AVI, BMP, SVG, or any other unsupported format from any app. MediaGate converts it using hardware-accelerated encoding and saves it straight to your photo library. No cloud. No subscription. No tracking.

## Supported Formats

### Video → MP4 (H.264 + AAC)

| Format | Extensions |
|---|---|
| MPEG-1/2 | `.mpg`, `.mpeg`, `.m2v` |
| AVI | `.avi` |
| WMV | `.wmv`, `.asf` |
| Flash Video | `.flv`, `.f4v` |
| Matroska | `.mkv` |
| WebM | `.webm` |
| 3GPP | `.3gp`, `.3g2` |
| Transport Stream | `.ts`, `.m2ts`, `.mts` |
| DVD VOB | `.vob` |
| OGG Video | `.ogv` |
| RealMedia | `.rm`, `.rmvb` |

### Image → PNG or JPEG

| Format | Extensions |
|---|---|
| BMP | `.bmp` |
| WebP | `.webp` |
| TIFF | `.tiff`, `.tif` |
| SVG | `.svg` |
| TGA | `.tga` |
| ICO | `.ico` |
| PSD | `.psd` |
| RAW | `.cr2`, `.nef`, `.arw`, `.dng`, `.orf`, `.rw2` |
| PCX | `.pcx` |
| PPM/PGM/PBM | `.ppm`, `.pgm`, `.pbm` |

### Passthrough (saved directly)

`.mp4`, `.mov`, `.m4v`, `.jpg`, `.jpeg`, `.png`, `.heif`, `.heic`, `.gif`, `.avif`

## Architecture

```
MediaGateApp/          Main app target (SwiftUI)
├── App/               Entry point + URL scheme handling
├── Views/             SwiftUI views (Home, Conversion, TipJar, Settings)
├── ViewModels/        MVVM view models
├── Services/          Core engine (FormatDetector, VideoConverter, ImageConverter, etc.)
└── Utilities/         Magic bytes, format registry, file helpers

MediaGateExtension/    Share Extension (receives files, hands off to main app)
MediaGateKit/          Shared framework (App Group constants, models)
```

- **Clean Architecture:** MVVM + protocol-oriented services
- **Swift 6** with strict concurrency
- **SwiftUI** for all UI
- **1 dependency:** [ffmpeg-kit](https://github.com/arthenica/ffmpeg-kit) for video transcoding
- **Native frameworks** for image conversion (ImageIO, CoreImage, WebKit)

## Getting Started

### Prerequisites

- Xcode 16.0+
- iOS 16.0+ device (Share Extension requires a physical device)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Setup

```bash
# Clone the repository
git clone https://github.com/kemalsanli/MediaGate.git
cd MediaGate

# Download ffmpeg-kit framework
chmod +x scripts/setup.sh
./scripts/setup.sh

# Generate Xcode project
xcodegen generate

# Open in Xcode
open MediaGate.xcodeproj
```

### Configuration

1. Set your signing team for both targets: **MediaGateApp** and **MediaGateExtension**
2. Enable the **App Groups** capability on both targets with: `group.com.kemalsanli.mediagate`
3. Build & Run on a physical device

## How It Works

1. **Share** a media file from any app (Files, Safari, Mail, etc.)
2. The **Share Extension** copies the file to a shared container
3. The **main app** opens via URL scheme, detects the format, and converts it
4. Video: hardware-accelerated H.264 encoding via ffmpeg-kit
5. Images: native conversion via ImageIO / CoreImage / WebKit
6. The converted file is **saved to Photos**

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

MediaGate uses [ffmpeg-kit](https://github.com/arthenica/ffmpeg-kit) (Full GPL build), which is also licensed under GPL.
