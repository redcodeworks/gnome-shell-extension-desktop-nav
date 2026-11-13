### Manual steps (nothing here uploads anything)
- [ ] Create an account at https://extensions.gnome.org (once).
- [ ] Download the `ego-zip` artifact of this run and check the sha256 above.
- [ ] Upload the zip at https://extensions.gnome.org/upload/.
- [ ] Wait for the review and answer the reviewer; fix and re-run this workflow for each new version.
- [ ] Be ready to justify and explain every part of the code. The review guidelines (https://gjs.guide/extensions/review-guidelines/review-guidelines.html) say: "While it is not prohibited to use AI as a learning aid or a development tool (i.e. code completions), extension developers should be able to justify and explain the code they submit, within reason." Read the whole of `extension.js` before uploading.
- [ ] Bump `version-name` for every new upload.

### Reviewer notes (paste into the upload form or answer questions with these)
1. **Why a stage `captured-event` handler.** The extension reacts to the global mouse back/forward buttons and to the wheel with modifier keys when the pointer is over the empty desktop, the overview or the app grid. An event controller on one actor cannot see presses that land on other actors, so the handler is connected to `global.stage`. Research done for this project (not run by the author on a live Shell): GNOME 51 documents connecting event signals directly as deprecated, but it still works and "will be removed in future GNOME Shell releases", while mutter's documentation shows no deprecation of the stage `captured-event` signal or of the Clutter event accessors used here. Plan: re-evaluate with Clutter controllers (`ClickGesture`, `ScrollController`) on the stage in a later release. The handler is connected in `enable()` and disconnected in `disable()`; it does no work for presses of buttons no rule uses.
2. **Private Shell members used**, each read defensively (optional chaining or a `typeof` check, so a missing member means the press is passed on and nothing throws):
   - `Main.layoutManager._backgroundGroup`: tells the empty desktop (background actors) from windows; guard: `Meta.BackgroundActor` is also accepted, so a missing group only loses the second test.
   - `Main.overview._overview?.controls`: fallback for `Main.overview.controls`, which is undefined on 51.1; reaches the app display; guard: `?.`, result may be null and the action then does nothing.
   - `controls._stateAdjustment`: tells whether the overview shows the app grid; guard: `?.` and a fallback to the dash Show Apps button state.
   - `appDisplay._grid`: current page and page count for the app grid page actions; guard: missing grid or `goToPage` means the press passes on.
3. **What is unverified.** Everything about runtime behavior was written without a live GNOME Shell; CLAUDE.md lists it ("Unverified" section). CI checks packaging, install mechanics, the rule logic (node) and the pre-flight, never the Shell.
