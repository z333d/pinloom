# Cursor behavior on the Pinloom line

The line uses a nonactivating panel so the user's working app retains focus.
Receiving hover events in that panel does not grant the owning background app
permission to change the displayed system cursor. Comparing `NSCursor.current`
or a cursor's image in a test only checks the local cursor object.

`BackgroundCursor.enable()` opts this process's WindowServer connection into
`SetsCursorInBackground`. It dynamically resolves the private connection APIs,
checks their return value, and reads the property back. Missing symbols or a
rejected property leave the panel usable, with the visible resize handle.
No application activation, global event tap, or Accessibility permission is
required by this implementation.

This property is also used by [Ice](https://github.com/jordanbaird/Ice/blob/main/Ice/Main/AppState.swift).
It is an undocumented macOS interface and must be revisited for Mac App Store
distribution or a macOS version that stops supporting it.

Automated tests verify the connection property is enabled while the current
foreground application remains unchanged. Manual validation must also check
the displayed pointer over the bottom-right corner while another app is active,
after a resize, after moving a card, and in another app's full-screen Space.
The resize handle should remain visible independently of cursor support.
