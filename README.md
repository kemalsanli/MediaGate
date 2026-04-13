# MediaGate

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform: iOS](https://img.shields.io/badge/Platform-iOS%2016%2B-orange.svg)](https://developer.apple.com/ios/)
[![Swift 6.0](https://img.shields.io/badge/Swift-6.0-FA7343.svg)](https://swift.org)

**Universal Media Converter for iOS** — Share Extension that converts unsupported media formats on-device and saves to Photos.

Share an MKV, AVI, BMP, SVG, or any other unsupported format from any app. MediaGate converts it using hardware-accelerated encoding and saves it straight to your photo library. No cloud. No subscription. No tracking.

## Features

- **Share Extension + Action Extension** — appears in both the app row and actions list
- **30+ input formats** — video, image, and RAW photo support
- **Hardware-accelerated** — H.264 encoding via VideoToolbox
- **On-device only** — no data leaves your phone
- **In-extension conversion** — small files convert instantly without opening the app
- **Crash-safe architecture** — files are queued in a shared container, never lost
- **36 languages** — with in-app language switching
- **Tip Jar** — free and open source, supported by optional tips
- **Zero tracking** — no analytics, no ads, no accounts

## Supported Formats

### Video → MP4 (H.264 + AAC)

| Format | Extensions |
|---|---|
| MPEG-1/2 | `.mpg`, `.mpeg`, `.m2v` |
| AVI | `.avi`, `.divx` |
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
| Photoshop | `.psd` |
| RAW Photos | `.cr2`, `.nef`, `.arw`, `.dng`, `.orf`, `.rw2`, `.raf`, `.pef` + more |
| PCX | `.pcx` |
| PPM/PGM/PBM | `.ppm`, `.pgm`, `.pbm` |

### Passthrough (saved directly)

`.mp4`, `.mov`, `.m4v`, `.jpg`, `.jpeg`, `.png`, `.heif`, `.heic`, `.gif`, `.avif`

## Architecture

```
MediaGateApp/            Main app (SwiftUI)
├── Views/               Home, Conversion, TipJar, Settings
├── ViewModels/          MVVM view models
└── Services/            ConversionPipeline, VideoConverter

MediaGateExtension/      Share Extension (icon row)
MediaGateAction/         Action Extension ("MediaGate ile Kaydet")
MediaGateKit/            Shared framework
└── Sources/             FormatDetector, ImageConverter, GallerySaver,
                         SupportedFormats, MagicBytes, SafetyChecks
```

- **Swift 6** with strict concurrency (`complete`)
- **SwiftUI** for all UI, **UIKit** for extensions
- **1 dependency:** [SwiftFFmpeg](https://github.com/kemalsanli/SwiftFFmpeg) (wraps ffmpeg-libav via SPM)
- **Native frameworks** for image conversion (ImageIO, CoreImage, WebKit)

## Getting Started

### Prerequisites

- Xcode 16.0+
- iOS 16.0+ device (Share Extension requires a physical device for testing)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

### Setup

```bash
git clone https://github.com/kemalsanli/MediaGate.git
cd MediaGate
xcodegen generate
open MediaGate.xcodeproj
```

SPM resolves all dependencies automatically on first build.

### Configuration

1. Set your signing team for all targets: **MediaGateApp**, **MediaGateExtension**, **MediaGateAction**
2. Enable the **App Groups** capability on all three targets: `group.com.kemalsanli.mediagate`
3. Build & Run on a physical device

## How It Works

1. **Share** a media file from any app (Files, Safari, Mail, etc.)
2. The **extension** copies the file to a shared App Group container
3. Small files are **converted in-extension** (images < 5 MB, videos < 15 MB)
4. Large files are **queued** and the main app opens to handle them
5. Video: hardware-accelerated H.264 via VideoToolbox / FFmpeg
6. Images: native conversion via ImageIO / CoreImage / WebKit
7. The converted file is **saved to Photos**

## Acknowledgments

MediaGate is built with the help of these open-source projects:

| Project | Usage | License |
|---------|-------|---------|
| [FFmpeg](https://ffmpeg.org/) via [SwiftFFmpeg](https://github.com/kemalsanli/SwiftFFmpeg) | Video/audio transcoding engine | LGPL/GPL |
| [fastlane](https://fastlane.tools/) | App Store metadata and screenshot delivery | MIT |
| [XcodeGen](https://github.com/yonaskolb/XcodeGen) | Xcode project generation from `project.yml` | MIT |

## Support

MediaGate is free, open-source, and has no ads. If you find it useful, consider supporting development:

- [GitHub Sponsors](https://github.com/sponsors/kemalsanli)
- In-app tip jar

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.
