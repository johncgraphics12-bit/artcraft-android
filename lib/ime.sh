#!/usr/bin/env bash
# Android touch and soft-keyboard patches, applied to the source at build time.
#
# Two fixes live here because this script is already called from lib/build-common.sh, so
# adding them needs no new call: replacing this one file is the whole change.
#
# 1. THE SOFT KEYBOARD'S RETURN (WordCraft and PhotoCraft).
#
#    Android takes the back key as "hide the keyboard" and tells the app nothing about it: the
#    app goes on believing the keyboard is up, so it never asks for it again, and the keyboard
#    stays down through the rest of the session -- the next edit (a tap in the text, a caret
#    moved by key) goes unseen by it. The keyboard only came back with a restart.
#
#    Two things are needed for it to come back, and neither is in the app's own code:
#
#      * the Activity has to *know* the keyboard was dismissed. It watches the keyboard's own
#        window insets: a keyboard that was on and then went away while the app still wanted it
#        was dismissed by the user;
#      * the shell has to *report* that the document is being worked on again. It sees the edits
#        (a pointer press, a key that is not the back key) and tells the Activity, which then
#        asks for the keyboard again.
#
#    PhotoCraft was added because its Type tool is unusable without it: a caption cannot be
#    typed, corrected or retyped once the keyboard has gone down. Every piece is shared between
#    the apps -- the Activity is generated for all of them from templates/android/SafActivity.java,
#    and the bridge and the shell's raw_input_hook from lib/build-common.sh -- so nothing here is
#    WordCraft-specific except the Backspace fix, which goes through fix_wordcraft().
#
# 2. THE TACTILE ACTION BAR (PhotoCraft).
#
#    A horizontal bar along the bottom edge carrying the six actions a finger needs most:
#    place an image, the Type tool, Undo, Redo, Clear, Delete Layer.
#
#    None of them could be reached on a tablet. Place Embedded sits four levels down a File
#    menu whose rows are a stylus width apart; the rest are bound to keys (Ctrl+Z,
#    Ctrl+Shift+Z, Delete) that a tablet has not got, and the Type tool had to be hunted in
#    the rail.
#
#    The bar is along the bottom because that is where a thumb already is: on a 10-inch tablet
#    held in two hands the bottom edge is about 13 mm away, the top centre about 160 mm. Its
#    buttons are 60-point squares where the toolbar's are 36, which clears the 48 dp (about
#    9 mm) Android asks for a fingertip.
#
#    An earlier revision of this script stacked the same buttons at the top of the vertical
#    toolbar. That put them in the rail the bar is meant to replace, and out of thumb reach;
#    this revision removes them from there.
#
# Every edit is guarded and idempotent: it applies only while the original text is still
# present, so it no-ops once the code is there, and it is re-applied on a fresh checkout.
#
# To build WITHOUT all of this, comment out the call to this script in lib/build-common.sh.
#
#
# 3. THE TACTILE THEME AND THE TOUCH SCALE (PhotoCraft).
#
#    A bar sized for a fingertip inside a shell sized for a mouse does not make a tablet app.
#    The tool rail is 40 points wide with 30-point buttons, the status bar 24: a few millimetres
#    each on a 204 ppi screen. This section resizes and repaints the whole shell.
#
#    The scale is the larger half of it. `sync_display_scale` already drives egui's global zoom
#    from one function, so one number there resizes everything at once -- rails, bars, menus,
#    dialogs, text -- instead of widget by widget. The desktop reads the preference as absolute
#    pixels-per-point, which is wrong on a phone or tablet whose system scale is already 2x or
#    3x: asking for 150% there would shrink the interface. On Android it is read as a multiple
#    of the system's own size, Auto meaning 1.5x, and it stays adjustable in Preferences.
#
#    The theme is the other half: a `Tactile` kind carrying the palette from the interface
#    mockup the designer approved -- ground #0F0F10, panels #28282B, accent #0A84FF, active
#    #30D158, destructive #FF6961 -- with corners a fingertip can see. It is built on Studio
#    rather than Pro because Studio is the non-Pro layout, which is also the app's larger size
#    set: a 50-point rail with 36-point buttons. It is a theme like any other, listed in
#    Preferences and switchable, because the accent is meant to be the user's to change.
#
#
# 4. THE SOFT KEYBOARD'S BACKSPACE IN THE TYPE TOOL (PhotoCraft).
#
#    A caption could be typed on a tablet and never taken back. Every press added a character,
#    none removed one, so the text only ever grew.
#
#    A soft keyboard has no Backspace key: it deletes through the input connection. The Activity
#    already turns both forms Android uses for that into one `ImeEvent::DeleteSurrounding` and
#    de-duplicates them; `ime_bridge.rs` hands it to egui. The Type tool read `Text` and `Commit`
#    and then swallowed the rest in `Ime(_) => {}` -- the deletion with it.
#
#    The new arm does what the Backspace key arm does a few lines below: put the ends of the run
#    on the caret and the anchor, then replace that run with nothing, so it is one history step
#    on the same path as every other edit.
#
#
# 5. DIALOGS THAT FIT A TABLET SCREEN (PhotoCraft).
#
#    New Document is the tallest dialog in the app -- a preset gallery, a saved-preset list and
#    ten fields, laid out for a desktop window. On a tablet it runs past the bottom of the screen
#    and takes the Create button with it, so no document can be made at all. The touch scale of
#    section 3 makes it worse, since every row is half again as tall.
#
#    `dialogs.rs` already solves exactly this for filter dialogs: the body goes in a scroll area
#    bounded to what the screen leaves after the dialog's title and buttons, so those stay put.
#    The bound is simply applied to New Document too.
#
#
# 6. DRAGGING A PANEL ONTO THE ICON RAIL (PhotoCraft).
#
#    The panel column never gave its width back: folding a group leaves its tab strip, and the
#    column's own minimum is 250 points whatever is inside it -- a quarter of a tablet held in
#    landscape, spent on strips.
#
#    Everything needed was already there but a destination. A group can be dragged by its tab
#    strip or by a tab pulled off it, both end in a drop resolved against a point on screen, and
#    `Action::Close` already takes a group out of the column -- after which `dock_panels` skips
#    it and draws no column at all once none is left. The icon rail becomes a place to drop on:
#    release a panel over it and it leaves the column, the rail icon standing in for it, and
#    tapping that icon brings it back.
#
#    The rail's own tap is deliberately left alone, so a shown group still folds to its strip and
#    a stray tap still cannot make a panel vanish (#129). Character gains the rail button it
#    never had, without which it could be dropped on the rail and never recovered.
#
#
# 7. RESIZABLE WINDOWS, AND THE DOUBLE TAP THAT DESELECTS (PhotoCraft).
#
#    `show_modal` already knew how to make a dialog resizable -- an opening size, a smallest and
#    a largest, and egui puts a grip on it -- but only three dialogs ever asked: Preferences,
#    Curves and the web dialog. Every other one was sized by its contents and could not be
#    touched, New Document worst of all: the tallest dialog in the app, with its Create button
#    below the bottom of a tablet screen. Now all of them have the grip, except the ones marked
#    compact, which already fit anywhere. The smallest size drops from 560 x 400 -- a monitor's
#    floor -- to something a 10-inch screen can actually reach.
#
#    Deselecting is Ctrl+D, and a tablet has no Ctrl key, so a selection could be made and never
#    undone. The canvas already dispatches double taps per tool (the polygonal and magnetic
#    lassos close their path on one), so the selection tools get an arm below those two.
#
#
# 8. GPU TILES SIZED FOR A PHONE, NOT A WORKSTATION (PhotoCraft).
#
#    The canvas lives on the GPU in square tiles, 8192 points a side by default -- a 256 MB RGBA
#    texture each. That number is written for a card with its own memory. A phone or tablet GPU
#    has none; it shares the system's.
#
#    On the device this was measured on (Mali-G52 MC2) a whole 3543 x 3543 document fits inside
#    one tile, so every layer move and every filter rewrites 256 MB through shared memory, while
#    the interface -- which never touches the canvas texture -- stays perfectly smooth. Exactly
#    the shape of the complaint: "it lags when I move a layer or apply an effect".
#
#    1024 a side is 4 MB a tile: sixty-four times less to move, and still four times the longest
#    edge most phone screens have. It remains a preference (Performance > Cache Tile Size).
#
# Usage: ime.sh <source-dir> <app> <title>
set -euo pipefail

SRC="${1:?source dir}"
APP="${2:?app}"
TITLE="${3:?title}"

# ------------------------------------------------------------- 1. the soft keyboard
if [[ "$APP" == "wordcraft" || "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import os
import sys

src, app = Path(sys.argv[1]), Path(sys.argv[2])
android_dir = src / "apps" / f"{app}-android"

fixed = []


def fix(rel: str, old: str, new: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = android_dir / rel
    try:
        text = path.read_text()
    except OSError:
        return
    if old not in text or new in text or text.count(old) != 1:
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(rel)


def fix_source(rel: str, old: str, new: str) -> None:
    """Like `fix`, for a file relative to the source checkout rather than the Android app."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        return
    if old not in text or new in text or text.count(old) != 1:
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(rel)


def fix_wordcraft(rel: str, old: str, new: str) -> None:
    """Like `fix_source`, but only for WordCraft: `crates/ui-egui/src/keys.rs` is its own text
    engine, which no other app has. Guarded by name rather than left to miss its anchor, so it
    can never half-apply to an app that happens to grow a file of the same name."""
    if app.name != "wordcraft":
        return
    fix_source(rel, old, new)


# Instrumentation for work on the keyboard: every event the shell drains is logged, so a
# device's logcat shows whether one press queued two events. Off unless ARTCRAFT_IME_TRACE=1.
def trace(path_rel: str) -> None:
    path = android_dir / path_rel
    try:
        text = path.read_text()
    except OSError:
        return
    marker = "    public String imePoll() {\n        return imeEvents.poll();\n    }"
    traced = (
        "    public String imePoll() {\n"
        "        String event = imeEvents.poll();\n"
        "        if (event != null) Log.i(TAG, \"imePoll -> \" + event);\n"
        "        return event;\n"
        "    }"
    )
    if marker in text and "imePoll ->" not in text:
        path.write_text(text.replace(marker, traced, 1))
        fixed.append(path_rel)
        text = path.read_text()
    # Every queued event, at the source.
    marker = "    private void queueImeEvent(String event) {\n        imeEvents.offer(event);"
    traced = "    private void queueImeEvent(String event) {\n        Log.i(TAG, \"queueImeEvent \" + event);\n        imeEvents.offer(event);"
    if marker in text and "queueImeEvent \" + event" not in text:
        path.write_text(text.replace(marker, traced, 1))
        fixed.append(path_rel + " (queue)")
        text = path.read_text()
    # Whether the shell ever asks for the keyboard, and what the Activity does about it.
    for signature in ("public void imeShow() {", "public void imeHide() {", "public void imeInteraction() {"):
        if signature in text:
            traced = signature + "\n        Log.i(TAG, \"" + signature.split()[2] + "\");"
            if traced not in text:
                path.write_text(text.replace(signature, traced, 1))
                fixed.append(path_rel + " (" + signature.split()[2] + ")")
                text = path.read_text()


# --- The Activity: notice the dismissal, and bring the keyboard back on the next edit. ---

# The Activity's own file name is not known here (the class is the app's), so it is found by
# the one thing every one of them has: the soft-keyboard host.
activity = None
for candidate in sorted((android_dir / "java").rglob("*.java")):
    if "public void imeShow()" in candidate.read_text(errors="replace"):
        activity = candidate
        break
if activity is None:
    raise SystemExit("Could not find the launcher Activity with the soft-keyboard host")

rel = str(activity.relative_to(android_dir))

fix(
    rel,
    """    // True between imeShow() and imeHide(); suppresses a deferred show that a quick hide overtook.
    private volatile boolean imeWanted = false;
""",
    """    // True between imeShow() and imeHide(); suppresses a deferred show that a quick hide overtook.
    private volatile boolean imeWanted = false;
    // The keyboard was on and then went away while the app still wanted it: the user dismissed
    // it with the back key. It comes back the next time the user works on the document.
    private volatile boolean imeDismissed = false;
    // Whether the keyboard was on at the last window-insets change, so a dismissal (the keyboard
    // going away) can be told apart from a keyboard that was never shown.
    private volatile boolean imeWasVisible = false;
""",
)

# Watching the keyboard's insets takes one of two shapes, because the two launcher Activities
# are not the same file. An app WITHOUT a complete adapter (WordCraft) gets the generated
# templates/android/SafActivity.java, which already installs a decor listener of its own and
# offers `chainWindowInsetsListener` to share it. An app WITH a complete adapter (PhotoCraft)
# ships its own Activity from adapters/<app>/java/, which has no such helper and installs no
# decor listener at all, so the listener goes on the decor view directly and forwards to the
# default implementation. Choosing on what the file actually contains, rather than on the app
# name, keeps this right if either Activity grows or loses the helper.
BODY = """                    boolean visible = insets.isVisible(WindowInsets.Type.ime());
                    if (visible) {
                        imeDismissed = false;
                    } else if (imeWasVisible && imeWanted) {
                        imeDismissed = true;
                        Log.i(TAG, "the keyboard was dismissed; it returns with the next edit");
                    }
                    imeWasVisible = visible;"""

if "chainWindowInsetsListener" in activity.read_text(errors="replace"):
    WATCH = (
        "            // The Activity installs the real decor listener and forwards every dispatch\n"
        "            // here, so the two observers share one listener rather than overwriting each other.\n"
        "            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {\n"
        "                chainWindowInsetsListener((v, insets) -> {\n" + BODY + "\n"
        "                    return insets;\n"
        "                });\n"
        "            }\n"
    )
else:
    WATCH = (
        "            // This Activity installs no decor listener of its own, so the observer goes on\n"
        "            // the decor view directly and hands the insets to the default implementation,\n"
        "            // which dispatches them to the child views as it would have anyway.\n"
        "            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {\n"
        "                window.getDecorView().setOnApplyWindowInsetsListener((v, insets) -> {\n" + BODY + "\n"
        "                    return v.onApplyWindowInsets(insets);\n"
        "                });\n"
        "            }\n"
    )

fix(
    rel,
    """        Window window = getWindow();
        if (window != null) {
            window.getDecorView().post(this::applyImmersiveFullscreen);
        }
""",
    """        Window window = getWindow();
        if (window != null) {
            window.getDecorView().post(this::applyImmersiveFullscreen);
            // Watch the keyboard's own insets: when it goes away while the app still wants it,
            // the user dismissed it with the back key, and the next work on the document brings
            // it back (see imeInteraction()).
"""
    + WATCH
    + """        }
""",
)

fix(
    rel,
    """    /**
     * Hand the Rust shell at most one queued keyboard event per call.""",
    """    /**
     * The user worked on the document again — a tap, a caret moved by key, anything the shell
     * sees as an edit. When the keyboard was dismissed with the back key while the app still
     * wanted it, bring it back: the document is being edited, so the keyboard belongs on screen.
     *
     * Called by the Rust shell over JNI, only when something happened.
     */
    public void imeInteraction() {
        if (!imeWanted || !imeDismissed) {
            return;
        }
        imeDismissed = false;
        final EditText view = imeView;
        if (view == null) {
            return;
        }
        runOnUiThread(() -> {
            try {
                view.setFocusable(true);
                view.setFocusableInTouchMode(true);
                view.requestFocus();
                InputMethodManager imm =
                        (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
                if (imm != null) {
                    boolean shown = imm.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT);
                    Log.i(TAG, "the keyboard was dismissed; asked for it again (shown=" + shown + ")");
                }
            } catch (Throwable error) {
                Log.w(TAG, "Could not show the soft keyboard again", error);
            }
        });
    }

    /**
     * Hand the Rust shell at most one queued keyboard event per call.""",
)

# --- The shared bridge: report the edits to the Activity. ---

fix(
    "src/ime_bridge.rs",
    """        fn next_event(&self) -> Result<Option<String>, String> {""",
    """        /// Tell the Activity that the user worked on the document again.
        ///
        /// Android takes the back key as "hide the keyboard" and the app hears nothing of it, so
        /// the app keeps believing the keyboard is up while it is not — and the next edit (a tap,
        /// a caret moved by key) would go unseen by the keyboard. The Activity watches the
        /// keyboard's own insets and knows when it was dismissed; this call tells it that the
        /// document is being worked on again, so it can bring the keyboard back.
        ///
        /// Only edits count: a pointer press, or a key that is not the back key (which the app
        /// receives as Escape, and which must not count as an edit — it is what dismissed the
        /// keyboard in the first place).
        pub fn interaction(&mut self, raw: &egui::RawInput) {
            let edited = raw.events.iter().any(|event| match event {
                egui::Event::PointerButton { .. } => true,
                egui::Event::Key { key, .. } => *key != egui::Key::Escape,
                _ => false,
            });
            if !edited {
                return;
            }
            if let Err(error) = self.request_interaction() {
                log::warn!("Android soft-keyboard bridge cannot report an edit: {error}");
            }
        }

        /// Ask the Activity to bring the keyboard back after the user dismissed it.
        fn request_interaction(&self) -> Result<(), String> {
            self.vm
                .attach_current_thread(|env| -> jni::errors::Result<()> {
                    let activity_raw = self.app.activity_as_ptr() as jni::sys::jobject;
                    // SAFETY: AndroidApp retains this global Activity reference; as_cast_raw borrows
                    // it without taking ownership or attempting to delete the reference.
                    let activity = unsafe { env.as_cast_raw::<JObject>(&activity_raw)? };
                    match env.call_method(
                        &*activity,
                        jni_str!("imeInteraction"),
                        jni_sig!("()V"),
                        &[],
                    ) {
                        Ok(_) => Ok(()),
                        Err(error) => {
                            env.exception_clear();
                            Err(error)
                        }
                    }
                })
                .map_err(|error| error.to_string())
        }

        fn next_event(&self) -> Result<Option<String>, String> {""",
)

# --- The shell: report the edits it sees. ---

fix(
    "src/lib.rs",
    """        self.probe.observe(raw);
        self.ime.poll(raw);
""",
    """        self.probe.observe(raw);
        self.ime.poll(raw);
        self.ime.interaction(raw);
""",
)

# --- Backspace at the start of a paragraph: join it with the one above. ---
#
# The soft keyboard never sends a Backspace *key*: Android delivers one press as
# `DeleteSurrounding(1, 0)` (see the Activity's InputConnection), which the app erases with
# `keys::delete_surrounding`. That function only erases characters *inside* a paragraph: its counts
# stop at the paragraph's ends, and when there is nothing to the left it returns without touching the
# document. At the start of a paragraph the one character before the caret is the paragraph mark,
# which has no characters of its own — so Backspace did nothing there, and two paragraphs could never
# be joined: on a phone, once Enter was pressed there was no way to take the line break back.
#
# On a desktop the same key arrives as `Key::Backspace` and the `text.backspace` command joins the
# paragraphs (and, at the start of a list item, removes the number or the indent first, as Word does).
# So when the input method asks to erase exactly one character before a caret that is already at the
# start of the paragraph, run that same command. Only that case: a larger count means a correction
# whose text really does start at the paragraph start, and must not join paragraphs.
fix_wordcraft(
    "crates/ui-egui/src/keys.rs",
    """    if start == end {
        return;
    }""",
    """    if start == end {
        // The one character before the caret is the paragraph mark, which the paragraph's text does
        // not contain. Backspace there joins with the paragraph above, exactly as the key does on a
        // desktop; a list item loses its number or indent first. A bigger count is a correction at
        // the paragraph start, not a Backspace over the mark, so it still erases nothing.
        if before == 1 && after == 0 && f.off == 0 {
            if app.session.typing_open() {
                app.session.join_next_undo();
            }
            let _ = app.run("text.backspace", json!({}));
        }
        return;
    }""",
)

# Its regression test: the Backspace-at-the-start-of-a-paragraph case above, and the two cases that
# must keep their old behaviour (the start of the story, and a correction that really starts at the
# paragraph start).
fix_wordcraft(
    "crates/ui-egui/src/keys.rs",
    """        alt_frame(&ctx, &mut a, vec![surround(5, 5), egui::Event::Text("2".into())]);
        assert_eq!(a.session.doc.plain_text(wordcraft_doc::StoryRef::Body).trim_end(), "one\\n2\\nthree");
    }""",
    """        alt_frame(&ctx, &mut a, vec![surround(5, 5), egui::Event::Text("2".into())]);
        assert_eq!(a.session.doc.plain_text(wordcraft_doc::StoryRef::Body).trim_end(), "one\\n2\\nthree");
    }

    /// A phone's Backspace at the start of a paragraph arrives as `DeleteSurrounding(1, 0)`, not as
    /// a `Key::Backspace`. The character it means is the paragraph mark, which is not part of the
    /// paragraph's text, so the paragraphs have to be joined explicitly — otherwise Enter could never
    /// be taken back on a phone.
    #[test]
    fn delete_surrounding_at_a_paragraph_start_joins_it_with_the_one_above() {
        let (ctx, mut a) = alt_frame_app();
        a.run("document.setText", json!({"text": "one\\ntwo"})).unwrap();
        // The caret at the start of `two` (after `one` and its paragraph mark).
        a.run("caret.docStart", json!({})).unwrap();
        for _ in 0..4 {
            a.run("caret.right", json!({})).unwrap();
        }
        alt_frame(&ctx, &mut a, vec![surround(1, 0)]);
        assert_eq!(body(&a), "onetwo");
        // At the very start of the story there is no paragraph above: it still erases nothing.
        a.run("caret.docStart", json!({})).unwrap();
        alt_frame(&ctx, &mut a, vec![surround(1, 0)]);
        assert_eq!(body(&a), "onetwo");
        // A correction erasing several characters from the paragraph start is not a Backspace over
        // the mark, so it must not join the paragraphs.
        a.run("document.setText", json!({"text": "one\\ntwo"})).unwrap();
        a.run("caret.docStart", json!({})).unwrap();
        for _ in 0..4 {
            a.run("caret.right", json!({})).unwrap();
        }
        alt_frame(&ctx, &mut a, vec![surround(2, 0), egui::Event::Text("X".into())]);
        assert_eq!(body(&a), "one\\nXtwo");
    }""",
)

if os.environ.get("ARTCRAFT_IME_TRACE") == "1":
    trace(rel)

if fixed:
    print(f"  Patched the soft keyboard for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 2. the tactile action bar (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []


def fix_source(rel: str, old: str, new: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        return
    if old not in text or new in text or text.count(old) != 1:
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(rel)


# The bar is written against the v0.16.0 layout, which is what BUILD_SOURCE pins: one
# panels.rs, and the shell composing its panels in lib.rs. v0.17.0 moved the status bar into
# panels/status_bar.rs and the composition out of lib.rs, so neither anchor below matches
# there. `fix_source` returns without doing anything when an anchor has moved, so a later
# source simply builds without the bar instead of failing to build.

# ---- the panel itself, defined just above the status bar it sits under.

PANEL_ANCHOR = """// ----------------------------------------------------------------------------- status bar"""

PANEL = r"""// ------------------------------------------------------------------------ tactile action bar

/// Height of the tactile action bar along the bottom edge.
pub const TOUCH_BAR_H: f32 = 56.0;

/// The actions a finger needs most, on one horizontal bar along the bottom edge.
///
/// A tablet driven by a stylus has no Ctrl key and no Delete key, so Undo, Redo and Clear
/// cannot be typed at all, and Place Embedded sits four levels down a File menu whose rows are
/// a stylus width apart. None of them could be reached.
///
/// The bar is along the bottom because that is where a thumb already is. Measured on a 10-inch
/// tablet held in two hands: the bottom edge is about 13 mm from the thumb's rest position and
/// the top centre of the screen is about 160 mm, well outside a 100 mm reach.
///
/// 44-point squares, where the toolbar's own buttons are 36. They are read through the touch
/// scale, which is 1.5x on Android: on screen that is a 66 dp target, comfortably past the
/// 48 dp (about 9 mm) Android asks for a fingertip, without eating into the canvas.
pub fn touch_bar(app: &mut PhotocraftApp, ui: &mut egui::Ui) {
    let t = Tokens::get(ui.ctx());
    let frame = egui::Frame::NONE.fill(t.dock).inner_margin(egui::Margin::symmetric(8, 0));
    egui::Panel::bottom("touch_bar").exact_size(TOUCH_BAR_H).frame(frame).show(ui, |ui| {
        // Cloned before the closures below borrow `app` to run a command.
        let act_ctx = ui.ctx().clone();
        let (can_u, can_r) = app.session.active().map_or((false, false), |d| (d.history.can_undo(), d.history.can_redo()));
        let live = app.session.active().is_some();
        ui.spacing_mut().item_spacing = vec2(6.0, 0.0);
        // `icons::button_with_icon_size` is the app's own square icon button: house hover
        // chrome, the accent treatment when selected, the translated tooltip and the
        // accessibility label all come with it, so the bar adds no widget code of its own.
        crate::direction::horizontal_centered(ui, |ui| {
            // What a design starts with: an image, or a caption.
            //
            // One button for the image, because the right command depends on what is open:
            // Place Embedded puts an image *into* a document, so with nothing open it would
            // do nothing at all. With nothing open the button opens an image as its own
            // document instead, which is the half that was being asked for.
            let (pick, cmd, tip) = if live { ("image", "file.placeEmbedded", "Place Embedded\u{2026}") } else { ("folder-open", "file.open", "Open\u{2026}") };
            if icons::button_with_icon_size(ui, pick, 44.0, 20.0, false, tip).clicked() {
                let _ = crate::menus::invoke(app, &act_ctx, cmd, json!({}));
            }
            // Selecting the Type tool, not a command: the tool is what opens the keyboard.
            if icons::button_with_icon_size(ui, "type", 44.0, 20.0, app.ui.tool == Tool::Type, "Horizontal Type Tool").clicked() {
                crate::tool_memory::select(app, Tool::Type);
            }
            // The two the designer asked for by name: selecting something, and resizing it.
            if icons::button_with_icon_size(ui, "quick-selection", 44.0, 20.0, app.ui.tool == Tool::QuickSelection, "Quick Selection Tool").clicked() {
                crate::tool_memory::select(app, Tool::QuickSelection);
            }
            if icons::button_with_icon_size(ui, "scaling", 44.0, 20.0, false, "Free Transform").clicked() && live {
                let _ = crate::menus::invoke(app, &act_ctx, "edit.freeTransform", json!({}));
            }
            widgets::vline(ui, 28.0);
            // History, then the two ways to take something away. A button that does not apply
            // is drawn but does nothing, as in the rail it replaces.
            for (icon, cmd, on, tip) in [
                ("undo-2", "edit.undo", can_u, "Undo"),
                ("redo-2", "edit.redo", can_r, "Redo"),
                ("eraser", "edit.clear", live, "Clear"),
                ("trash", "layer.delete", live, "Delete Layer"),
            ] {
                if icons::button_with_icon_size(ui, icon, 44.0, 20.0, false, tip).clicked() && on {
                    let _ = crate::menus::invoke(app, &act_ctx, cmd, json!({}));
                }
            }
            widgets::vline(ui, 28.0);
            // Saving. On a desktop it is Ctrl+S, which a tablet has no way to press, so the work
            // could be done and never kept.
            if icons::button_with_icon_size(ui, "file", 44.0, 20.0, false, "Save").clicked() && live {
                let _ = crate::menus::invoke(app, &act_ctx, "file.save", json!({}));
            }
        });
    });
}

"""

fix_source("crates/ui-egui/src/panels.rs", PANEL_ANCHOR, PANEL + PANEL_ANCHOR)

# ---- the call. Bottom panels take the outermost edge in declaration order, so the bar is
# declared before the status bar to sit under it, against the screen edge.

CALL_ANCHOR = """        if chrome && self.ui.panels.status_bar {
            panels::status_bar(self, ui);
        }"""

CALL = """        // The tactile action bar, under the status bar and against the bottom edge.
        if chrome {
            panels::touch_bar(self, ui);
        }
"""

fix_source("crates/ui-egui/src/lib.rs", CALL_ANCHOR, CALL + CALL_ANCHOR)

if fixed:
    print(f"  Patched the tactile action bar (place image, text, undo/redo, clear, delete) for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 3. the tactile theme and the touch scale (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed, missed = [], []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missed.append(f"{tag} (no {rel})")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missed.append(f"{tag} ({text.count(old)} anchors in {rel})")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


THEME = "crates/ui-egui/src/theme.rs"
PREFS = "crates/engine/src/prefs.rs"
PREFS_UI = "crates/ui-egui/src/prefs_ui.rs"

# ---------------------------------------------------------------- 3a. the Tactile theme
#
# Colours come from the interface mockup the designer approved, not from taste: ground #0F0F10,
# panel #28282B, accent #0A84FF (his, and changeable), active #30D158, destructive #FF6961.
# The green is not decoration -- in that design it means "this is on", so it dresses the
# selected state and nothing else, while the blue accent stays the one a user can repaint.
#
# It is built on Studio rather than Pro because Studio is the non-Pro layout: rounded chips,
# cards, and -- the part that matters on a tablet -- the larger of the app's two size sets
# (a 50-point tool rail with 36-point buttons instead of 40 and 30).

fix_source(THEME, """    /// A low-contrast light theme: pale violet-grey surfaces, softened dark text and a periwinkle accent.
    SoftLight,
}""", """    /// A low-contrast light theme: pale violet-grey surfaces, softened dark text and a periwinkle accent.
    SoftLight,
    /// Built for a tablet held in two hands: near-black ground, panels that float over it,
    /// corners a fingertip can see, and green reserved for "this is active".
    Tactile,
}""", "theme: enum variant")

fix_source(THEME, "    pub const ALL: [ThemeKind; 14] = [", "    pub const ALL: [ThemeKind; 15] = [", "theme: ALL length")

fix_source(THEME, """        ThemeKind::SoftLight,
    ];""", """        ThemeKind::SoftLight,
        ThemeKind::Tactile,
    ];""", "theme: ALL entry")

fix_source(THEME, '            ThemeKind::SoftLight => "Soft Light",',
           '            ThemeKind::SoftLight => "Soft Light",\n            ThemeKind::Tactile => "Tactile",', "theme: label")

fix_source(THEME, '            ThemeKind::SoftLight => "softLight",',
           '            ThemeKind::SoftLight => "softLight",\n            ThemeKind::Tactile => "tactile",', "theme: id")

fix_source(THEME, """                | ThemeKind::SoftDark
        )""", """                | ThemeKind::SoftDark
                | ThemeKind::Tactile
        )""", "theme: is_dark")

fix_source(THEME, '            "softlight" => Some(ThemeKind::SoftLight),',
           '            "softlight" => Some(ThemeKind::SoftLight),\n            "tactile" | "touch" | "tablet" => Some(ThemeKind::Tactile),', "theme: from_name")

TOKENS = """            // Touch-first, from the approved mockup: a near-black ground with panels floating
            // over it, and corners big enough to read at arm's length. Built on Studio for its
            // non-Pro layout, which is also the app's larger size set.
            ThemeKind::Tactile => Tokens {
                kind,
                chrome: Color32::from_rgb(26, 26, 29),
                canvas: Color32::from_rgb(15, 15, 16),
                canvas_dot: Color32::from_rgb(42, 42, 46),
                dock: Color32::from_rgb(20, 20, 22),
                card: Color32::from_rgb(40, 40, 43),
                card_border: Color32::from_rgb(54, 54, 59),
                field: Color32::from_rgb(32, 32, 35),
                field_border: Color32::from_rgb(58, 58, 64),
                hover: Color32::from_rgb(50, 50, 55),
                pressed: Color32::from_rgb(62, 62, 68),
                text: Color32::from_rgb(245, 245, 247),
                text_dim: Color32::from_rgb(199, 199, 204),
                text_faint: Color32::from_rgb(152, 152, 159),
                icon: Color32::from_rgb(232, 232, 236),
                // The accent is the one the user repaints; the green says "active" and only that.
                accent: Color32::from_rgb(10, 132, 255),
                accent_soft: Color32::from_rgba_unmultiplied(48, 209, 88, 48),
                accent_border: Color32::from_rgb(48, 209, 88),
                accent_text: Color32::from_rgb(245, 245, 247),
                separator: Color32::from_rgb(44, 44, 48),
                shadow: Color32::from_black_alpha(170),
                primary_bg: Color32::from_rgb(10, 132, 255),
                primary_text: Color32::WHITE,
                danger: Color32::from_rgb(255, 105, 97),
                warning: Color32::from_rgb(255, 159, 10),
                // A 44-point target wants a corner you can see from a hand's distance.
                radius_sm: 8.0,
                radius: 10.0,
                radius_lg: 14.0,
                ..Tokens::for_kind(ThemeKind::Studio)
            },
"""

fix_source(THEME, "            ThemeKind::Studio => Tokens {", TOKENS + "            ThemeKind::Studio => Tokens {", "theme: for_kind arm")

# The theme has to be reachable from Preferences, and it is the one a tablet should start on.
fix_source(PREFS,
           'choice!(DarkTheme { Pro = "pro", ProMedium = "proMedium", Studio = "studio", SolarizedDark = "solarizedDark", AdwaitaDark = "adwaitaDark", BreezeDark = "breezeDark", SoftDark = "softDark" } default ProMedium);',
           'choice!(DarkTheme { Pro = "pro", ProMedium = "proMedium", Studio = "studio", SolarizedDark = "solarizedDark", AdwaitaDark = "adwaitaDark", BreezeDark = "breezeDark", SoftDark = "softDark", Tactile = "tactile" } default Tactile);',
           "prefs: DarkTheme")

fix_source(PREFS_UI, "            DarkTheme::SoftDark => ThemeKind::SoftDark,",
           "            DarkTheme::SoftDark => ThemeKind::SoftDark,\n            DarkTheme::Tactile => ThemeKind::Tactile,", "prefs_ui: DarkTheme map")

# ---------------------------------------------------------------- 3b. the touch scale
#
# The single biggest reason the editor does not feel like an app on a tablet: every panel is
# sized for a mouse. `sync_display_scale` already drives egui's global zoom from this one
# function, so one number here resizes the whole shell -- rails, bars, menus, dialogs, text --
# instead of widget by widget.
#
# The desktop reading of the preference is absolute pixels-per-point (125% means 1.25 px per
# point, whatever the monitor reports). That is wrong for a phone or tablet, where the system
# scale is already 2x or 3x: asking for 150% there would *shrink* the interface. On Android the
# same preference is therefore read as a multiple of the system's own size, and Auto is 1.5x --
# a 30-point button becomes about 9 mm, which is the 48 dp Android asks for a fingertip.
#
# `cfg!` rather than `#[cfg]`: it is an ordinary boolean, so both branches keep compiling and
# the desktop tests covering this function go on passing unchanged.

fix_source(PREFS_UI, """    let native = native.filter(|v| v.is_finite() && *v > 0.0).unwrap_or(1.0);
    match pref {
        // The system's scale, fractional ones included (125%, 150%, 175%: #1072), and 100% on a
        // large 4K display run unscaled (#1278); 200% there is a fixed choice.
        prefs::UiScale::Auto => native,
        fixed => fixed.name().parse::<f32>().map_or(1.0, |pct| pct / 100.0),
    }
}""", """    let native = native.filter(|v| v.is_finite() && *v > 0.0).unwrap_or(1.0);
    let fixed = match pref {
        // The system's scale, fractional ones included (125%, 150%, 175%: #1072), and 100% on a
        // large 4K display run unscaled (#1278); 200% there is a fixed choice.
        prefs::UiScale::Auto => None,
        other => Some(other.name().parse::<f32>().map_or(1.0, |pct| pct / 100.0)),
    };
    // A touch screen reads the same preference as a multiple of the system's own size, because
    // its scale is already 2x or 3x and an absolute 1.5 would shrink the interface. Auto is
    // half again as big, which turns a 30-point button into the 48 dp a fingertip needs.
    if cfg!(target_os = "android") {
        return native * fixed.unwrap_or(1.5);
    }
    fixed.unwrap_or(native)
}""", "prefs_ui: touch scale")

if fixed:
    print(f"  Patched the tactile theme and touch scale for {app}: {len(fixed)} edits")
if missed:
    print(f"  !! NOT applied: {'; '.join(missed)}")
    sys.exit(1)
PY
fi

# --------------------------- 4. the soft keyboard's Backspace in the Type tool (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed, missed = [], []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missed.append(f"{tag} (no {rel})")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missed.append(f"{tag} ({text.count(old)} anchors in {rel})")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# A soft keyboard has no Backspace *key*. It deletes through the input connection, and the
# Activity already turns both forms Android uses -- `deleteSurroundingText(n, m)` and a
# synthesised `KEYCODE_DEL` -- into one `ImeEvent::DeleteSurrounding`, de-duplicated, which
# `ime_bridge.rs` hands to egui.
#
# The Type tool answered `Text` and `Commit` and then swallowed everything else in
# `Ime(_) => {}`, deletion included. So on a tablet a caption could be typed and never taken
# back: every press added, none removed. (This is why the text in a tester's recording only ever
# grew: "Lorem Ipsum" -> "Lorem Ipsumdvdg" -> "Lorem Ipsumdvdgqahfhdgdg".)
#
# The arm below does exactly what the Backspace key arm a few lines down does: it puts the two
# ends of the range to erase on the caret and the anchor, then replaces that range with nothing,
# so the deletion is one history step and goes through the same path as every other edit. A live
# selection is erased whole, as Backspace does, since that is what a keyboard means by deleting
# while text is selected.
#
# `as usize` is deliberate: the counts come from egui and are only ever read as indices here, so
# the cast costs nothing and keeps this working whatever width egui gives them.

ANCHOR = "            egui::Event::Ime(_) => {}"

ARM = """            // Android's Backspace arrives as a deletion through the input connection, never as a
            // key: without this arm it fell into `Ime(_)` below and text could be typed but never
            // erased. Same mechanics as the Backspace key arm: select the run, then replace it.
            egui::Event::Ime(egui::ImeEvent::DeleteSurrounding { before_chars, after_chars }) => {
                if a != b {
                    insert(app, "");
                } else {
                    let from = a.saturating_sub(*before_chars as usize);
                    let to = (a + *after_chars as usize).min(n);
                    if from != to {
                        if let Some(e) = app.ui.text_edit.as_mut() {
                            e.caret = to;
                            e.anchor = from;
                        }
                        insert(app, "");
                    }
                }
            }
"""

fix_source("crates/ui-egui/src/type_tool.rs", ANCHOR, ARM + ANCHOR, "type_tool: DeleteSurrounding")

if fixed:
    print(f"  Patched the Type tool's soft-keyboard Backspace for {app}")
if missed:
    print(f"  !! NOT applied: {'; '.join(missed)}")
    sys.exit(1)
PY
fi

# --------------------------- 5. dialogs that fit a tablet screen (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed, missed = [], []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missed.append(f"{tag} (no {rel})")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missed.append(f"{tag} ({text.count(old)} anchors in {rel})")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# New Document is the tallest dialog in the app: a preset gallery, a saved-preset list and ten
# fields, laid out for a desktop window. On a tablet -- more so with the touch scale, which
# makes every row half again as tall -- it runs past the bottom of the screen and takes the
# Create button with it, so a new document cannot be made at all.
#
# `dialogs.rs` already solves this for filter dialogs, whose parameter lists are just as long:
# the body goes in a scroll area bounded to what the screen leaves after the dialog's own title
# and buttons, so those stay put and the content scrolls. The same bound is applied here.
# `DIALOG_CHROME` and `ctx.content_rect()` are the file's own, already used a few arms below.

ANCHOR = """                DialogKind::NewDocument => {
                    if crate::new_doc_ui::body(app, ui, &mut fields) {
                        outcome = Some(true);
                    }
                }"""

BOUNDED = """                DialogKind::NewDocument => {
                    // The tallest dialog in the app, on the shortest screen it runs on: without a
                    // bound it pushes Create off the bottom and a document cannot be created at
                    // all. Same treatment as the filter dialogs below, bounded to the room the
                    // window gives it -- the body scrolls, the title and the buttons stay put,
                    // and shrinking the window (section 7) scrolls the body instead of spilling.
                    let room = ui.available_height().max(120.0);
                    let created = egui::ScrollArea::vertical()
                        .id_salt(id.with("new-document-body"))
                        .max_height(room)
                        .show(ui, |ui| crate::new_doc_ui::body(app, ui, &mut fields))
                        .inner;
                    if created {
                        outcome = Some(true);
                    }
                }"""

fix_source("crates/ui-egui/src/dialogs.rs", ANCHOR, BOUNDED, "dialogs: New Document fits the screen")

if fixed:
    print(f"  Patched the New Document dialog to fit the screen for {app}")
if missed:
    print(f"  !! NOT applied: {'; '.join(missed)}")
    sys.exit(1)
PY
fi

# --------------------------- 6. drag a panel onto the icon rail to free the column (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed, missed = [], []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missed.append(f"{tag} (no {rel})")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missed.append(f"{tag} ({text.count(old)} anchors in {rel})")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


D = "crates/ui-egui/src/dock.rs"

# The panel column never gives its width back. Folding a group leaves its tab strip, and the
# column's own minimum is 250 points whatever is inside it -- a quarter of a tablet held in
# landscape, spent on strips.
#
# Everything needed was already here but one destination. A group can be dragged by its tab
# strip, or by a tab pulled off it; both end in a drop resolved against a point on screen; and
# `Action::Close` already takes a group out of the column, after which `dock_panels` skips it
# and draws no column at all once none is left. The icon rail is simply added as a place to drop
# on: release a panel over it and it leaves the column, its rail icon standing in for it. The
# rail's own tap is untouched, so a shown group still folds to its strip (and a stray tap still
# cannot make a panel vanish, #129); tapping the icon of a group that is out brings it back
# through `reveal`, as it already did.
#
# The rail's rectangle comes from egui's own panel state rather than being passed down: the rail
# is drawn by `panels.rs`, after this code runs on a tablet, and its position from the previous
# frame is exact enough for a pointer test -- it is a fixed-width panel against the screen edge.

fix_source(D, "fn drop_before(", """/// The icon rail's rectangle, while the rail is up. Taken from egui's panel state because the
/// rail is drawn by `panels::right_dock`, not here; it is a fixed-width panel pinned to the
/// screen edge, so the previous frame's rectangle is exact.
fn rail_rect(ctx: &egui::Context) -> Option<Rect> {
    egui::containers::panel::PanelState::load(ctx, egui::Id::new("rail")).map(|s| s.outer_rect)
}

/// Was a panel released over the icon rail? Dropping there sends it out of the column.
fn dropped_on_rail(ctx: &egui::Context, p: Pos2) -> bool {
    rail_rect(ctx).is_some_and(|r| r.contains(p))
}

fn drop_before(""", "dock: rail drop target")

fix_source(D, """            actions.push(Action::Move(g, drop_before(&order, &rects, g, p.y)));
        }""", """            // Released over the icon rail: out of the column rather than up or down it. The
            // width goes back to the canvas and the rail icon becomes the way back.
            if dropped_on_rail(ui.ctx(), p) {
                actions.push(Action::Close(g));
            } else {
                actions.push(Action::Move(g, drop_before(&order, &rects, g, p.y)));
            }
        }""", "dock: a strip dropped on the rail")

fix_source(D, """        } else {
            actions.push(Action::Move(from, drop_before(&order, &rects, from, position.y)));
        }""", """        } else if dropped_on_rail(ui.ctx(), position) {
            // A tab pulled off its strip and dropped on the rail takes its whole group out,
            // which is what the strip drag does: the rail stands for groups, not single tabs.
            actions.push(Action::Close(from));
        } else {
            actions.push(Action::Move(from, drop_before(&order, &rects, from, position.y)));
        }""", "dock: a tab dropped on the rail")

fix_source(D, """    // Drop indicator while a group is dragged by its tab strip.
    if let (Some(g), Some(p)) = (dragging, ui.ctx().pointer_interact_pos()) {
        let before = drop_before(&order, &rects, g, p.y);
        let line_y = match before.and_then(|b| rects.iter().find(|(x, _)| *x == b)) {
            Some((_, r)) => r.top() - GAP / 2.0,
            None => rects.last().map_or(area.top(), |(_, r)| r.bottom() + GAP / 2.0),
        };
        ui.painter().line_segment([pos2(area.left(), line_y), pos2(area.right(), line_y)], Stroke::new(3.0, t.accent));
    }""", """    // Drop indicator while a group is dragged: where it would land in the column, or the rail
    // washed in the accent when releasing there would take it out of the column instead.
    if let (Some(g), Some(p)) = (dragging, ui.ctx().pointer_interact_pos()) {
        if let Some(rail) = rail_rect(ui.ctx()).filter(|r| r.contains(p)) {
            // On a foreground layer: the rail is outside this panel's clip rectangle.
            let wash = egui::Color32::from_rgba_unmultiplied(t.accent.r(), t.accent.g(), t.accent.b(), 70);
            let layer = egui::LayerId::new(egui::Order::Foreground, egui::Id::new("pc-rail-drop"));
            ui.ctx().layer_painter(layer).rect_filled(rail, 0.0, wash);
        } else {
            let before = drop_before(&order, &rects, g, p.y);
            let line_y = match before.and_then(|b| rects.iter().find(|(x, _)| *x == b)) {
                Some((_, r)) => r.top() - GAP / 2.0,
                None => rects.last().map_or(area.top(), |(_, r)| r.bottom() + GAP / 2.0),
            };
            ui.painter().line_segment([pos2(area.left(), line_y), pos2(area.right(), line_y)], Stroke::new(3.0, t.accent));
        }
    }""", "dock: the rail lights up as a target")

# Character had no rail button, so once dropped on the rail it could never be brought back.
fix_source("crates/ui-egui/src/panels.rs", """                let entries: [(&str, &str, Group); 6] = [
                    ("sliders-horizontal", tl!("Properties"), Group::Properties),""",
           """                let entries: [(&str, &str, Group); 7] = [
                    ("sliders-horizontal", tl!("Properties"), Group::Properties),
                    ("type", tl!("Character"), Group::Character),""",
           "rail: the Character group")

if fixed:
    print(f"  Patched drag-a-panel-onto-the-rail for {app}: {len(fixed)} edits")
if missed:
    print(f"  !! NOT applied: {'; '.join(missed)}")
    sys.exit(1)
PY
fi

# --------------------------- 7. resizable windows, and the double tap that deselects (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed, missed = [], []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missed.append(f"{tag} (no {rel})")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missed.append(f"{tag} ({text.count(old)} anchors in {rel})")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


D = "crates/ui-egui/src/dialogs.rs"

# ---- 7a. every window gets a resize grip.
#
# `show_modal` already knows how: given an opening size, a smallest and a largest, it wraps the
# dialog in an `egui::Resize` with a grip. Only three dialogs ever asked for it -- Preferences,
# Curves and the web dialog -- so every other one was sized by its contents and could not be
# touched. New Document is the one that hurt: it is the tallest in the app, and on a tablet its
# Create button sat below the bottom of the screen with no way to reach it.
#
# Dialogs marked `__compact` (a few short fields) keep hugging their contents: they already fit
# anywhere, and a grip would only wrap them in empty room. Everything else opens roomy and can
# be dragged to any size between the new minimum and the screen.

fix_source(D, "const CURVES_SIZE: egui::Vec2 = egui::vec2(300.0, 420.0);",
           """const CURVES_SIZE: egui::Vec2 = egui::vec2(300.0, 420.0);
/// The size every other resizable dialog opens at, before the screen clamps it down and before
/// the size the user last gave it takes over.
const ROOMY_DIALOG: egui::Vec2 = egui::vec2(620.0, 480.0);""",
           "dialogs: a roomy default size")

fix_source(D, """    } else if is_curves(fields) {
        Some(CURVES_SIZE)
    } else {
        None
    }
}""", """    } else if is_curves(fields) {
        Some(CURVES_SIZE)
    } else if fields.contains_key("__compact") {
        // A few short fields: it fits anywhere already, and a grip would only add empty room.
        None
    } else {
        // Everything else, New Document above all, gets a grip and a size the screen can hold.
        Some(ROOMY_DIALOG)
    }
}""", "dialogs: every window resizable")

fix_source(D, "    if is_curves(fields) { egui::vec2(300.0, 420.0) } else { egui::vec2(560.0, 400.0) }",
           """    // 560 x 400 was a monitor's floor, kept so two-column layouts stayed side by side. On a
    // tablet it is most of the screen, and a window that cannot be made small is not resizable
    // in any way the user can feel. The body keeps its own 380-point minimum width.
    if is_curves(fields) { egui::vec2(300.0, 420.0) } else { egui::vec2(320.0, 240.0) }""",
           "dialogs: a floor a tablet can reach")

# ---- 7b. a double tap drops the selection.
#
# Deselecting is Ctrl+D, and a tablet has no Ctrl key, so a selection could be made and never
# undone. The canvas already dispatches double taps per tool -- the polygonal and magnetic
# lassos close their path on one -- so the selection tools get an arm of their own, below those
# two so neither loses its own meaning. `is_enabled` is the app's own test for "there is a
# selection to drop", the same one the menu entry uses.

fix_source("crates/ui-egui/src/canvas.rs", """                _ => {
                    if tool == Tool::Move && app.ui.transform.is_none() {""",
           """                // No Ctrl key on a tablet, so Ctrl+D cannot drop a selection: a double tap with a
                // selection tool does it instead. The two lassos above keep theirs, which closes
                // the path they are drawing.
                _ if response.double_clicked()
                    && matches!(
                        tool,
                        Tool::RectMarquee
                            | Tool::EllipseMarquee
                            | Tool::SingleRowMarquee
                            | Tool::SingleColumnMarquee
                            | Tool::Lasso
                            | Tool::MagicWand
                            | Tool::QuickSelection
                            | Tool::ObjectSelection
                    )
                    && app.session.is_enabled("select.deselect") =>
                {
                    if let Err(e) = app.run("select.deselect", json!({})) {
                        app.ui.status = e;
                    }
                }
                _ => {
                    if tool == Tool::Move && app.ui.transform.is_none() {""",
           "canvas: a double tap deselects")

if fixed:
    print(f"  Patched resizable windows and the deselecting double tap for {app}: {len(fixed)} edits")
if missed:
    print(f"  !! NOT applied: {'; '.join(missed)}")
    sys.exit(1)
PY
fi

# --------------------------- 8. GPU tiles sized for a phone, not a workstation (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed, missed = [], []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missed.append(f"{tag} (no {rel})")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missed.append(f"{tag} ({text.count(old)} anchors in {rel})")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# The canvas lives on the GPU in square tiles, 8192 points on a side by default. One such tile is
# a 8192 x 8192 RGBA texture: 256 MB. That is a workstation's number, and it is written for a card
# with its own memory.
#
# A phone or tablet GPU has none: it shares the system's. On the device this was measured on, a
# Mali-G52 MC2, a whole 3543 x 3543 document fits inside a single tile, so every layer move and
# every filter rewrites 256 MB through shared memory while the interface -- which never touches
# the canvas texture -- stays perfectly smooth. That is exactly the shape of the complaint.
#
# 1024 points a side is 4 MB a tile, sixty-four times less to move, and it is still four times the
# longest edge most phone screens have. It applies at the next launch, and it stays a preference:
# Preferences > Performance > Cache Tile Size, anything from 256 to 16384.

fix_source("crates/engine/src/prefs.rs", """            cache_levels: 4,
            cache_tile_size: 8192,""", """            cache_levels: 4,
            // A phone or tablet GPU shares the system's memory, so an 8192-point tile -- 256 MB
            // of RGBA -- is moved whole for every layer move and every filter. 1024 is 4 MB.
            cache_tile_size: if cfg!(target_os = "android") { 1024 } else { 8192 },""",
           "prefs: tiles a phone GPU can carry")

if fixed:
    print(f"  Patched the GPU tile size for {app}")
if missed:
    print(f"  !! NOT applied: {'; '.join(missed)}")
    sys.exit(1)
PY
fi
