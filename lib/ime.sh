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
# 2. UNDO / REDO / CLEAR / DELETE BUTTONS (PhotoCraft).
#
#    PhotoCraft binds these to keys (Ctrl+Z, Ctrl+Shift+Z, Delete) and to menus several levels
#    deep, but a tablet driven by a stylus has no Ctrl key and no Delete key, and the software
#    keyboard does not open over the canvas: the commands cannot be reached at all. Undo alone
#    is the most-used action in a retouching session.
#
#    The buttons go at the top of the toolbar, under the width chevron, where a thumb reaches
#    them without covering the canvas. They use icons the app already ships and the same
#    commands the keyboard and the menus trigger, and they dim when they do not apply. They are
#    34 points tall rather than the toolbar's usual 22: Android asks for 48dp (about 9mm) of
#    target for a fingertip, and these are the four that get pressed most.
#
# Every edit is guarded and idempotent: it applies only while the original text is still
# present, so it no-ops once the code is there, and it is re-applied on a fresh checkout.
#
# To build WITHOUT all of this, comment out the call to this script in lib/build-common.sh.
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

# ----------------------------------------- 2. the toolbar's four action buttons
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


# The toolbar is drawn top-down: the width chevron, then the tool sections. The buttons go
# straight under the chevron, where a thumb reaches them without covering the canvas.
#
# Two source layouts are covered, and only one of them is ever present:
#
#  * v0.17.0 and later: the toolbar has its own file, and egui 0.37 calls the accessibility
#    role `Role`;
#  * v0.16.0 and earlier: the whole panels module is one file, and egui 0.36 still calls it
#    `WidgetType`.
#
# `fix_source` returns without doing anything when the file is absent or the anchor has moved,
# so the pair is safe: the build gets the buttons on whichever layout it checked out, and
# silently goes without them on a layout neither anchor matches.

ANCHOR = """            ui.add_space(4.0);
            // Subtle violet wash at the bottom of the toolbar."""

BUTTONS = """            // Undo / Redo / Clear / Delete, within thumb's reach.
            // On a tablet driven by a stylus there is no Ctrl key and no Delete key, so
            // none of these four can be typed, and a software keyboard will not open over
            // the canvas. Without them the most-used actions in the editor are unreachable.
            // 34 points tall, not the toolbar's usual 22: a fingertip needs about 9 mm.
            {
                let act_ctx = ui.ctx().clone();
                let (can_u, can_r) = app.session.active().map_or((false, false), |d| (d.history.can_undo(), d.history.can_redo()));
                let live = app.session.active().is_some();
                // `tl!` borrows the translation, so each label is a `&str`, as in menu_nav.
                for row in [
                    [("undo-2", "edit.undo", can_u, tl!("Undo")), ("redo-2", "edit.redo", can_r, tl!("Redo"))],
                    [("eraser", "edit.clear", live, tl!("Clear")), ("trash", "layer.delete", live, tl!("Delete Layer"))],
                ] {
                    ui.horizontal(|ui| {
                        for (icon, cmd, on, label) in row {
                            let (r, resp) = ui.allocate_exact_size(vec2(bx / 2.0 - 1.0, 34.0), Sense::click());
                            let tint = if on && resp.hovered() { t.text } else { t.text_faint };
                            icons::paint(ui, r, icon, 18.0, tint);
                            resp.widget_info(|| egui::WidgetInfo::labeled(egui::__ROLE__::Button, on, label));
                            if on && resp.clicked() {
                                let _ = crate::menus::invoke(app, &act_ctx, cmd, json!({}));
                            }
                        }
                    });
                }
            }
"""

for rel, role in (
    ("crates/ui-egui/src/panels/toolbar.rs", "Role"),
    ("crates/ui-egui/src/panels.rs", "WidgetType"),
):
    fix_source(rel, ANCHOR, BUTTONS.replace("__ROLE__", role) + ANCHOR)

if fixed:
    print(f"  Patched the toolbar with Undo/Redo/Clear/Delete buttons for {app}: {', '.join(fixed)}")
PY
fi
