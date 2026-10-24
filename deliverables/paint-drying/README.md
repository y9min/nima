# Nima paint-drying animation

This folder contains a 60-second, non-looping Lottie animation for the Nima Hard Mode challenge.

## Files

- `nima_paint_drying.json` — 1024 × 1024, 30 fps, 1,800-frame Lottie composition.
- `assets/nima_paint_reference.png` — original transparent illustration.
- `assets/nima_paint_dry_overlay_v2.png` — masked dry-green fence overlay; the bucket and brush are excluded while the fence immediately behind the bucket remains covered.
- `preview.html` — playback, pause, reset, scrubber, and countdown preview.
- `vendor/lottie.min.js` — local browser renderer used by the preview.

Keep the JSON and `assets` directory together. The JSON uses relative image paths.

## Preview locally

Browsers block local JSON/image loading from a `file://` page, so serve this folder:

```bash
cd deliverables/paint-drying
python3 -m http.server 8080
```

Then open `http://localhost:8080/preview.html`.

## SwiftUI integration

Add Airbnb Lottie through Swift Package Manager using `https://github.com/airbnb/lottie-spm.git`. Add `nima_paint_drying.json` and the complete `assets` folder to the app target with **Copy items if needed** enabled. Preserve the folder reference so the relative paths inside the JSON resolve.

```swift
import SwiftUI
import Lottie

struct PaintDryingView: View {
    /// Drive this from the challenge countdown: elapsed / 60, clamped to 0...1.
    let progress: Double

    var body: some View {
        LottieView(animation: .named("nima_paint_drying"))
            .currentProgress(max(0, min(1, progress)))
            .configure { view in
                view.loopMode = .playOnce
                view.backgroundBehavior = .pauseAndRestore
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityLabel("Paint drying progress")
            .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
```

For strict countdown synchronisation, make the timer the source of truth and update `progress`; do not call `.playing()` at the same time. Setting `currentProgress` supports seeking in either direction and displays the expected state at 0, 0.25, 0.5, 0.75, and 1.

## Implementation notes

- The reference raster remains stationary for visual fidelity.
- A transparent, masked raster overlay gradually changes only the painted fence from `#008053` toward dry `#629580`.
- The original artwork's restrained wet sheen is progressively flattened by the dry overlay; five irregular vector drops fall before 40 seconds and create tiny puddles.
- The composition has no background layer, expressions, effects, masks, text, or loop instruction. Looping is controlled by the player and must remain disabled.
