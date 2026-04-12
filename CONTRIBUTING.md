# Contributing to MediaGate

Thanks for your interest in contributing to MediaGate!

## Getting Started

1. Fork the repository
2. Clone your fork
3. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
4. Run `xcodegen generate` to create the Xcode project
5. Open `MediaGate.xcodeproj` in Xcode
6. Set your signing team for all targets

## Development

- **Swift 6.0** with strict concurrency enabled
- **Minimum iOS 16.0**
- All public types and methods must have DocC comments (`///`)
- All Swift files must include the GPLv3 license header
- Run tests before submitting a PR

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `MediaGateApp/` | Main iOS application (SwiftUI) |
| `MediaGateExtension/` | Share Extension (UIKit) |
| `MediaGateAction/` | Action Extension (UIKit) |
| `MediaGateKit/` | Shared framework (format detection, image conversion, models) |

## Adding a New Format

1. Add the format info to `MediaGateKit/Sources/SupportedFormats.swift`
2. Add magic bytes (if applicable) to `MediaGateKit/Sources/MagicBytes.swift`
3. Implement conversion in the appropriate converter
4. Add tests

## Localization

The app supports 36 languages via `Localizable.xcstrings`. When adding new user-facing strings:

1. Use `String(localized:)` in SwiftUI or `NSLocalizedString()` in UIKit
2. Add translations for all supported languages in `Localizable.xcstrings`
3. Run `LocalizationTests` to verify completeness

## Pull Request Process

1. Create a feature branch from `main`
2. Make your changes
3. Ensure the project builds and tests pass
4. Submit a PR using the provided template

## Code of Conduct

Please read and follow our [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing to MediaGate, you agree that your contributions will be licensed under the GNU General Public License v3.0.
