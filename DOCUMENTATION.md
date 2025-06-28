

---

## `Movie Theater Experience/Chat/Message/MessagePreferenceKey.swift`

### Goal of this Struct
A SwiftUI `PreferenceKey` designed to collect the positions of multiple chat messages within a `ScrollView`. This allows a parent view to observe and react to the layout of its child message views, enabling features like visibility-based fading or automatic scrolling.

### Properties

-   `static var defaultValue: [MessagePosition]`
    -   **Goal:** The default value for the preference key, an empty array of `MessagePosition`.

### Functions

#### `static func reduce(value: inout [MessagePosition], nextValue: () -> [MessagePosition])`
-   **Goal:** Combines multiple `MessagePosition` arrays reported by child views into a single array. This is crucial for collecting all message positions from a `LazyVStack` or similar layout.
-   **Inputs:**
    -   `value`: The current accumulated array of `MessagePosition`.
    -   `nextValue`: A closure that provides the next array of `MessagePosition` to incorporate.
-   **Outputs:** None (modifies `value` in place).

