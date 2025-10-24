# Repository Guidelines

## Project Structure & Module Organization
- The visionOS app lives in `Movie Theater Experience/`; feature folders (`Chat`, `Calendar`, `Immersive`, `Hosted Events`, `Movie Picker`, `Sign Up`, etc.) own their SwiftUI views, models, and services.
- Shared infrastructure (`Core`, `Utilities`, `Model`, `Config`, `Assets.xcassets`) stores reusable types, environment data, and textures; USDZ assets stay at the repo root (e.g., `Scene.usdz`, `intro.usdz`).
- Tests live in `Movie Theater ExperienceTests/`, mirroring feature folders and using `assetsForTests` fixtures.
- CocoaPods output is tracked under `Pods/`, while SPM content lives in `Packages/`; update them only when bumping dependencies.

## Build, Test, and Development Commands
- `xcodebuild -project "Movie Theater Experience.xcodeproj" -scheme "Movie Theater Experience" -destination 'platform=visionOS Simulator,name=Apple Vision Pro' build` compiles the app for local verification.
- `xcodebuild -project "Movie Theater Experience.xcodeproj" -scheme "Movie Theater Experience" -destination 'platform=visionOS Simulator,name=Apple Vision Pro' test` runs the XCTest suite in `Movie Theater ExperienceTests/`.
- Run `pod install` only after touching the `Podfile`; otherwise rely on the committed Pods.
- Refresh Xcode previews when you edit `Preview Content/` sample data.

## Coding Style & Naming Conventions
- Follow Swift API Design Guidelines: types in UpperCamelCase, properties/functions in lowerCamelCase, and SwiftUI view files named after the primary view.
- Indent with 4 spaces, prefer `guard` for early exits, and reserve `// MARK:` markers for major boundaries.
- Use `Task {}` for async work (see `Movie Theater Experience/Movie_Theater_ExperienceApp.swift`) and keep shared singletons in `Core/` or `Utilities/`.
- Run `swiftlint` (if configured locally) before pushing; match the surrounding formatting instead of reflowing entire files.

## Testing Guidelines
- Write XCTest cases next to the feature directory (e.g., `ChatViewModelTests.swift` mirrors `Chat/`).
- Name tests `test_<Scenario>_<ExpectedResult>` and pull fixtures from `assetsForTests` when exercising multimedia flows.
- Keep coverage strong on new services and view models; add regression tests for bugs before delivering the fix.
- Document non-automatable validation (e.g., headset-only flows) in the PR checklist.

## Commit & Pull Request Guidelines
- Keep commits focused, imperative, and under ~60 characters (`chat: add message retention`); split mechanical refactors from feature work.
- Each PR needs a change summary, linked issue, target simulator/device, and a `Test Plan` showing commands run (e.g., `xcodebuild … test`) plus UI captures when relevant.
- Call out asset or config file changes (`*.usdz`, `GoogleService-Info.plist`) so reviewers can confirm signing and bundle impacts.
