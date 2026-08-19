# Chat Notes sync in the registry doc, as one indivisible field

A Chat Note is a short user-authored label with a colour. It reads like a personal, per-device
annotation, so a reader may expect it to live in local device state. It does not. It is stored
on the Chat row in the registry Loro doc, beside `title` and `archived`, and it syncs to every
device.

We chose synced storage because a note describes the Chat, not one device's view of it. The
user who labels a Chat on the desktop means that label to be true of the Chat everywhere. The
same choice keeps an iOS rendering possible later without a migration, which matters because
iOS writes registry rows directly rather than through the engine's Mutate RPC. That makes the
registry field encoding the cross-platform contract; the `setChatNote` Mutate op is
desktop-local plumbing on top of it.

We store the note as **one nested field**, `note: { text, color }`, not as two flat fields.
Registry writes are per-field last-writer-wins on a hybrid logical clock. Flat `noteText` and
`noteColor` would carry independent clocks, so two devices editing the same note concurrently
would merge into one device's text beside the other's colour - a note neither user authored.
Two flat fields would also admit a colour with no text. One field gives whole-note LWW: the
newer clock wins outright and the note is never merged.

## Consequences

- Concurrent edits **lose** one user's note rather than blending both. This is deliberate and
  the spec states it in those words.
- The colour is stored as a neutral palette **slot id**, not an index and not hex, so
  reordering or re-tuning the palette does not repaint existing notes.
- The engine cannot enforce the 280 character authoring cap as a storage invariant, because
  iOS bypasses the Mutate RPC. Renderers must tolerate any length.
