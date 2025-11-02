# Space Drawing Module

This module powers the collaborative 3D sketching experience that appears inside the Space Immersion environment. It captures hand or pointer input, converts it into world-space points, and streams the resulting strokes through Firebase so every participant shares the same drawing.

## How It Works

- **SpaceDrawingViewModel** owns the drawing session. It normalizes pointer locations, samples 3D points inside the drawing volume, and builds `SpaceStroke` models. While a stroke is in progress it produces a live preview so creators get immediate feedback.
- **SpaceDrawingService** syncs strokes with Firestore. Each finished stroke is written once and listener updates keep the local cache fresh across participants.
- **SpaceDrawingRenderer** turns stroke data into RealityKit entities that live under a dedicated anchor inside the scene graph.

## Real-Time Stroke Rendering

Strokes now render incrementally as samples arrive instead of rebuilding the entire drawing set on every gesture:

1. The view model calls `displayCurrentStrokes(includePreview:)` with a draft stroke that shares its final `strokeId`.
2. The renderer caches a lightweight signature for each stroke and only rebuilds geometry when that specific stroke changes (for example, new points are appended while the user continues a pinch).
3. Previously rendered strokes remain attached to the scene, so nothing disappears when a new stroke begins.

This approach eliminates the flicker where the whole drawing vanished at the start of every pinch gesture and keeps latency low enough that hand-drawn lines feel continuous.

## Brush Aesthetics

- `SpaceDrawingBrushOption` carries a `style` flag so the renderer can swap between multiple geometries without changing the networking schema.
- Tubular brushes are still the workhorse: a 14-sided tube is generated from a smoothed, densified path, giving a cohesive “paint rope” with minimal seams.
- The **Flat Marker** style renders a ribbon that hugs the drawing plane, ideal for broad strokes and calligraphy.
- The **Oil Ribbon** styles use width/twist modulation driven by a deterministic noise hash of the stroke ID, so every ribbon feels organic but remains replicated for peers.
- The **Classic Cylinder** style keeps the legacy segmented cylinders but with auto caps and overlap, reducing visible gaps at joints.
- The new **Neon Spray** preset is a narrow tubular brush tinted with a high-metallic purple so you have a quick “glow pen” ready for highlights.
- The **Block Stroke** style extrudes a rectangular beam with subtle depth so you can sketch architectural edges or callouts with planar faces.
- Incoming strokes animate from tail to tip so remote collaborators' drawings gracefully trace into view rather than popping in.
- A `ColorPicker` sits beside the presets, letting artists override the stroke hue/alpha at any time; the renderer stores the exact color in each `SpaceStroke`, so custom choices still replicate for collaborators.
- Metallic, roughness, and the new emission slider let you dial in sheen vs. glow—emission feeds RealityKit’s `PhysicallyBasedMaterial.emission`, so higher values make the stroke appear self-lit without affecting teammates’ presets.
- The drawing window now surfaces these presets as labeled cards, so creators can switch style/texture combos directly from the UI while still adjusting thickness, metallic, and roughness afterwards.
- Eraser mode now shows a pink square cursor that matches the actual erase footprint, making it obvious what will disappear before you commit.
- The thickness control now includes a continuous slider (with preset chips) so you can fine-tune beam width before drawing or while tweaking the eraser radius.
- Single-point taps automatically produce either disks or spheres sized to the active brush width, so dots stay consistent across styles.
- Because every mesh carries UVs, you can layer custom materials (textures, fresnel effects, etc.) without touching the geometry code.

## Finger-Based Drawing

- `SpaceDrawingHandPoseProvider` now analyzes the index finger joints for each tracked hand. When the finger is straight (joint alignment above 0.82) and separated from the thumb, the sample is marked as `isIndexExtended`.
- `SpaceDrawingViewModel` starts a stroke the moment an extended index finger sample arrives, appending new points as long as the same hand remains extended. Relaxing the finger automatically ends the stroke.
- `SpaceDrawingRenderer` maintains a lightweight preview sphere that sits exactly at the finger tip; it matches the active brush color and diameter so creators always know what will be drawn before committing, and it only appears (and moves) while the index finger is extended.
- The preview follows either hand—right is preferred when both are tracked—and turns off automatically when the brush tool is not active or the overlay is hidden.

## Tips for Future Changes

- Reuse the existing draft-stroke path when adding new preview behaviour. As long as the draft keeps the same `strokeId`, the renderer can update it in place.
- If you introduce new stroke metadata (e.g., texture variants), extend the renderer's signature check so updates propagate without reinstantiating all geometry.
- When debugging missing strokes, confirm:
  - `SpaceDrawingViewModel.currentSpaceId` is set before sampling points.
  - The renderer is attached to the `drawingAnchor` (`configureSceneRoot` must run).
  - Firebase security rules permit reads and writes for the active space.
