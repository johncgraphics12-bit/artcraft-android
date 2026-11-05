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
#
# 9. THE ICON RAIL REPLACES THE DOCK, AND OPENS ITS PANELS OVER THE CANVAS (PhotoCraft).
#
#    On a desktop the dock is a column beside the canvas, and the icon rail shows, expands or
#    collapses groups inside it. On a 10-inch tablet that column takes a third of the screen
#    whatever it holds, and a group left collapsed in it is invisible until you find its
#    chevron -- so the image is small and the panels are hard to reach at the same time.
#
#    Affinity and Photoshop on iPad both answer this the same way: one rail of icons, and a
#    panel that opens *over* the image and closes again, so the canvas keeps the whole window
#    whenever a panel is not being read.
#
#    That is what this does on Android, and only on Android:
#
#      * the dock column is not drawn at all; the rail takes its place;
#      * the rail lists every group, not the dock rail's six -- Character (the type panel) is
#        left out of the desktop default workspace, and a tablet has no other way to reach it --
#        and it scrolls, so more groups can be added without running off the screen;
#      * a tap opens a group over the canvas, a second tap on the same icon closes it. One
#        state per group, open or closed, shown by the icon: nothing can be left half-hidden;
#      * the panel is the docked group, tabs and all. It reuses dock_body, so Layers, Channels
#        and Paths, Color and Swatches, History and Actions behave exactly as on the desktop,
#        bounded and scrolled the way the dock bounds them;
#      * Studio's floating Properties card is suppressed, since Properties is now a rail entry
#        like every other group and the card would be a second copy of the same panel.
#
#    A custom workspace (Window > Workspace) draws its own destinations through panel_docking
#    and is left alone.
#
#
# 10. A SELECTION MODE THE QUICK SELECTION TOOL CAN REACH (PhotoCraft).
#
#    Every selection tool in PhotoCraft has four modes -- New, Add to, Subtract from, Intersect
#    with the selection -- and every one of them except Quick Selection already shows them as
#    buttons on its options bar. Quick Selection has only Alt, and it says so on the bar:
#    "Alt to subtract".
#
#    A tablet has no Alt. So on the tool most used for cutting a subject out of a photograph,
#    exactly half of what the tool does was out of reach -- and a clean cut-out needs both
#    adding and taking away, which means it could not be finished at all.
#
#    Three buttons now sit at the head of its options bar, where Photoshop puts them, in place
#    of the hint asking for a key that is not there. Three and not four because the engine's
#    select.quick has no intersect mode; intersect left over from the lasso reads as Add, which
#    is what the stroke already does with it. The state is the same selection_mode the lasso and
#    the wand use, so the mode follows you from tool to tool, and Alt still wins when it is held,
#    so nothing changes for a mouse and a keyboard.
#
#
# 11. CHOOSE THE SAVE FORMAT INSIDE THE APP (PhotoCraft).
#
#    PhotoCraft writes PSD, and PSD is even its default: the exporter puts out layers, groups,
#    layer and clipping masks, smart objects, editable text, blend modes, adjustment layers and
#    an embedded preview, and switches to PSB by itself when the document outgrows a PSD. A save
#    to PSD becomes the document's own file, not a flattened copy -- the code recognises only
#    three formats as holding a whole document, and PSD is one of them.
#
#    But the *choice* of format is not drawn by PhotoCraft. It is the "Save as type" list at the
#    bottom of the platform's save dialog, which PhotoCraft fills and Windows or macOS draws.
#    Android's picker has no such list: it gives a folder and a name, and that is all. So on the
#    tablet every save silently took whichever extension had been suggested, and PSD, PDF, JPEG,
#    PNG, TIFF and WebP could not be asked for at all.
#
#    The list now lives in the app. File > Save As on Android first shows a short modal -- PSD,
#    PhotoCraft, PDF, PNG, JPEG, TIFF, WebP, one finger-sized button each, PSD highlighted as the
#    default -- and the folder picker opens after, with the extension already on the name.
#
#    The tail of the save that asks where to put the file became save_pick, so the chooser goes
#    on through exactly the same path as a desktop save: the replace prompt, the TIFF, JPEG,
#    Targa and DDS option prompts, the disk-change check and the action journal are all unchanged.
#
#
# 12. SHIFT, ALT AND CTRL AS BUTTONS (PhotoCraft).
#
#    339 behaviours in PhotoCraft are reached only by holding a modifier key: 124 behind Alt,
#    114 behind Shift, 101 behind Ctrl. Subtracting from a selection, constraining proportions,
#    scaling from the centre, duplicating by dragging, stepping a caret word by word. A tablet
#    has none of those keys, so half of nearly every tool was out of reach -- and a clean cut-out,
#    which needs both adding and taking away, could not be finished at all.
#
#    Affinity answers this by putting a tool's modes in its context bar. Adobe, on iPad, adds a
#    floating button tied to the active tool. This takes Adobe's shape, because it is the one
#    that covers everything at once instead of one tool at a time: three buttons floating over
#    the canvas, dragged by a grip to wherever they are not in the way.
#
#    One tap arms a modifier for the next gesture and it releases itself when that gesture ends;
#    a second tap locks it until it is tapped off; a third clears it. So one finger can subtract
#    from a selection, and a long piece of work needing the same modifier throughout locks it once.
#
#    What makes it general is where it is applied: the block's state is folded into the frame's
#    input in raw_input_hook, before any widget reads it -- into the frame's modifier state and
#    into every event that carries modifiers. So all 339 work unchanged, and so do the keyboard
#    shortcuts; not one of those 339 places had to learn that buttons exist. A release that ends
#    a gesture on the canvas is what disarms an armed modifier; a release on the block itself is
#    ignored, or tapping a button would disarm what the tap had just armed.
#
#
# 13. A MEMORY BUDGET A TABLET ACTUALLY HAS (PhotoCraft).
#
#    PhotoCraft ships believing it may use 8 GB of memory, and keeps fifty undo steps inside that
#    budget. Those are a workstation's numbers, and they are not a cap the app approaches
#    carefully: the budget is what decides when the oldest history states are dropped, so at 8 GB
#    on a tablet they are never dropped at all.
#
#    Android shares one pool of memory between the system, the screen and every running app, and
#    kills whichever one grows too far. The app was not crashing; it was being killed -- and it
#    was being killed during a save, which is where the most memory is wanted at once, because a
#    layer's interleaved samples and the channel planes made from them are alive together.
#
#    1 GB and twenty steps. The document's pixels are untouched, at full resolution, on screen and
#    on export: the budget drops old history states and nothing else. Both remain on Preferences >
#    Performance for a tablet with room to spare.
#
#
# 14. DIALOGS THAT FIT THE SCREEN THEY OPEN ON (PhotoCraft).
#
#    Two faults, both of them the same mistake: a window's size written for a monitor.
#
#    A resizable dialog opens at 620 x 480 points. A tablet held upright gives the app about 533
#    points across, so New Document opened wider than the screen, and its right-hand column -- the
#    one holding Width, Height and the Create button -- was not on the screen at all, with nothing
#    to show there was more. Held flat there are 853 points and it fits, which is why this looked
#    like a portrait-only fault. Section 5 bounded the dialog's height and section 7 lowered the
#    size it can be dragged down to; neither touched the size it OPENS at, which is the one that
#    mattered. It is now clamped to what the window can hold.
#
#    And on Android the window runs under the system navigation bar. A centred dialog as tall as
#    the screen allowed put its bottom row -- Create again -- on top of the back and home buttons.
#    Dialogs now leave room for those.
#
#
# 15. MENUS THAT OPEN ON A TAP, NOT ON A HELD FINGER (PhotoCraft).
#
#    The Layers panel's footer menus -- fx (layer styles) and the adjustment-layer list -- and
#    every drop-down list open on the PRESS, so that one gesture can press the button, slide onto
#    an item and release on it. That is Photoshop's own behaviour, and with a mouse it is right.
#
#    With a finger it falls apart. A finger that moves three points between the press and the
#    release is a drag, not a click, so the release that ended the opening press counted as a
#    click OUTSIDE the menu and closed it again. The menu stayed up only while the finger stayed
#    down, and choosing an entry meant pressing, sliding onto it and letting go without a wobble.
#
#    On Android they now open on the release and wait: tap to open, tap an entry to choose it,
#    tap outside to close. The drop-down lists keep egui's own behaviour, which is already that.
#
#
# 16. QUICK SELECTION GROWS AGAIN AFTER ITS FIRST STROKE (PhotoCraft).
#
#    A regression this script introduced, and the reason the tool felt worse than before.
#
#    Section 10 gave Quick Selection the options bar's New / Add / Subtract buttons and made the
#    stroke read the mode. But the shared selection mode starts at New -- and before section 10
#    the stroke was hardcoded to add. So every stroke began wiping the one before it, and a
#    cut-out, which is built stroke by stroke, could not be built at all.
#
#    New now applies to the first stroke only; the tool switches to Add after it, which is what
#    Photoshop's Quick Selection does. The buttons keep their three meanings.
#
#
# 17. A SHORT TOOL COLUMN, AND EVERY TOOL ONE TAP AWAY (PhotoCraft).
#
#    The tool column carries twenty-one slots. On a 10-inch screen that is the whole height of the
#    window spent on tools, with the image squeezed into what is left -- and it still scrolls.
#
#    On Android the column now keeps eight: Move, the lasso, the selection family, Crop, Brush,
#    Eraser, Type and Zoom. Each keeps its flyout, so the variants are still a long press away.
#
#    The rest live behind the "..." button that was already at the foot of the column. On a
#    desktop it opens Edit > Toolbar, a dialog written for a mouse; on Android it now opens every
#    tool at once, over the canvas, four to a row with its name under each icon -- because a column
#    has no room for names and an icon you cannot read is not a tool you can find. Tapping one
#    selects it and closes the grid; tapping "..." again closes it too. Tools hidden in
#    Edit > Toolbar stay hidden there as well.
#
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

# --------------------------- 9. the touch rail and its panel over the canvas (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# ---- The rail and the panel it opens, defined just above the dock they replace.

PANEL_ANCHOR = """// ----------------------------------------------------------------------------- dock"""

PANEL = r"""// ---------------------------------------------------------------------- touch panels

/// Width of the icon rail on a touch screen, and the side of one of its buttons.
pub const TOUCH_RAIL_W: f32 = 56.0;
const TOUCH_RAIL_BTN: f32 = 44.0;
/// How wide the panel opened over the canvas is, and the most of the canvas it may cover.
const TOUCH_PANEL_W: f32 = 340.0;
const TOUCH_PANEL_SHARE: f32 = 0.64;
/// Height of the panel's header: its tab strip and its close box.
const TOUCH_HEAD_H: f32 = 36.0;

fn touch_open_id() -> egui::Id {
    egui::Id::new("touch-open-group")
}

/// The panel group open over the canvas, if any.
pub(crate) fn touch_open(ctx: &egui::Context) -> Option<crate::dock::Group> {
    ctx.data(|d| d.get_temp::<Option<crate::dock::Group>>(touch_open_id())).flatten()
}

fn set_touch_open(ctx: &egui::Context, g: Option<crate::dock::Group>) {
    ctx.data_mut(|d| d.insert_temp(touch_open_id(), g));
}

/// The icon rail on a touch screen: every panel group, scrollable, and nothing docked beside the
/// canvas. A tap opens a group over the image (`touch_panel`), a second tap on the same icon
/// closes it, so the whole window is the image the rest of the time.
///
/// The dock's own rail toggles a column that eats a third of a tablet screen, and a group left
/// collapsed there is invisible until you find its chevron (#129). Here there is one state per
/// group, open or closed, and the icon shows which.
pub fn touch_rail(app: &mut PhotocraftApp, ui: &mut egui::Ui) {
    let t = Tokens::get(ui.ctx());
    let open = touch_open(ui.ctx());
    crate::direction::end_panel("rail")
        .resizable(false)
        .exact_size(TOUCH_RAIL_W)
        .frame(egui::Frame::NONE.fill(t.chrome).inner_margin(egui::Margin::symmetric(6, 8)))
        .show(ui, |ui| {
            // The separator is on the canvas side.
            let r = ui.max_rect();
            let x = if crate::direction::is_rtl() { r.right() + 6.0 } else { r.left() - 6.0 };
            ui.painter().line_segment([pos2(x, r.top() - 8.0), pos2(x, r.bottom() + 8.0)], Stroke::new(1.0, t.separator));
            ui.spacing_mut().item_spacing.y = 6.0;
            use crate::dock::Group;
            // Every group, not the dock rail's six: Character is the type panel, which the dock
            // leaves out of the default workspace and a tablet has no other way of reaching.
            let entries: [(&str, &str, Group); 7] = [
                ("layers", tl!("Layers"), Group::Layers),
                ("sliders-horizontal", tl!("Properties"), Group::Properties),
                ("palette", tl!("Color & Swatches"), Group::Color),
                ("type", tl!("Character"), Group::Character),
                ("clock", tl!("History"), Group::History),
                ("navigation", tl!("Navigator"), Group::Navigator),
                ("brush", tl!("Brushes"), Group::Brushes),
            ];
            egui::ScrollArea::vertical().id_salt("touch-rail").auto_shrink([false, false]).show(ui, |ui| {
                for (icon, name, g) in entries {
                    if icons::rail_button(ui, icon, TOUCH_RAIL_BTN, open == Some(g), name).clicked() {
                        if open == Some(g) {
                            set_touch_open(ui.ctx(), None);
                        } else {
                            // `reveal` un-hides the group's selected tab, so a group whose tabs
                            // were closed on a desktop still has something to show here.
                            crate::dock::reveal(app, g);
                            set_touch_open(ui.ctx(), Some(g));
                        }
                    }
                }
            });
        });
}

/// The group opened from the touch rail, drawn over the canvas instead of beside it, so the image
/// keeps the whole window. Its tab strip and its body are the docked group's (`dock_body`),
/// bounded and scrolled the way `dock::show` bounds a docked group's.
pub fn touch_panel(app: &mut PhotocraftApp, ctx: &egui::Context) {
    let Some(group) = touch_open(ctx) else { return };
    if app.ui.docking.is_some() {
        return;
    }
    let t = Tokens::get(ctx);
    // The canvas, or the whole window before a document has been laid out in it.
    let canvas = if app.last_canvas_rect.is_positive() { app.last_canvas_rect } else { ctx.content_rect() };
    if !canvas.is_positive() {
        return;
    }
    let width = TOUCH_PANEL_W.min(canvas.width() * TOUCH_PANEL_SHARE).max(200.0);
    let height = (canvas.height() - 20.0).max(160.0);
    let x = if crate::direction::is_rtl() { canvas.left() + 10.0 } else { canvas.right() - width - 10.0 };
    let frame = egui::Frame::NONE
        .fill(t.card)
        .stroke(Stroke::new(1.0, t.card_border))
        .corner_radius(CornerRadius::same(t.radius_lg as u8))
        .shadow(egui::Shadow { offset: [0, 12], blur: 36, spread: 0, color: t.shadow })
        .inner_margin(egui::Margin::same(12));
    // A touch on the canvas beside the panel closes it and does nothing else: the sheet takes it
    // away from the canvas, and the panel goes when the finger comes up. The rail is left alone.
    if app.last_canvas_rect.is_positive() {
        let outside = egui::Area::new(egui::Id::new("touch-panel-outside"))
            .order(egui::Order::Middle)
            .fixed_pos(canvas.min)
            .show(ctx, |ui| ui.allocate_response(canvas.size(), Sense::click_and_drag()))
            .inner;
        if (outside.clicked() || outside.drag_stopped()) && !egui::Popup::is_any_open(ctx) {
            set_touch_open(ctx, None);
        }
        // Whichever was first seen first, the sheet must stay under the panel.
        ctx.move_to_top(egui::LayerId::new(egui::Order::Middle, egui::Id::new("touch-panel")));
    }
    // Order::Middle, like the other floating panels, so menus, popups and dialogs stay above it.
    egui::Area::new(egui::Id::new("touch-panel")).order(egui::Order::Middle).fixed_pos(pos2(x, canvas.top() + 10.0)).show(ctx, |ui| {
        frame.show(ui, |ui| {
            ui.set_width(width - 24.0);
            ui.set_height(height - 24.0);
            let visible = app.ui.dock.visible_tabs(group, t.pro);
            if visible.is_empty() {
                return;
            }
            let indices: Vec<usize> = visible.iter().map(|(i, _)| *i).collect();
            let tabs: Vec<&str> = visible.iter().map(|(_, name)| *name).collect();
            let before = *group.tab_mut(&mut app.ui.dock_tabs);
            let mut sel = indices.iter().position(|i| *i == before).unwrap_or(0);
            // A close box a finger can hit, and the tab strip beside it.
            let (row, _) = ui.allocate_exact_size(vec2(ui.available_width(), TOUCH_HEAD_H), Sense::hover());
            let shut = Rect::from_min_max(pos2(row.right() - TOUCH_HEAD_H, row.top()), row.max);
            if icons::button(&mut ui.new_child(egui::UiBuilder::new().max_rect(shut)), "x", TOUCH_HEAD_H, false, tl!("Close")).clicked() {
                set_touch_open(ui.ctx(), None);
            }
            let bar = Rect::from_min_max(row.min, pos2((shut.left() - 6.0).max(row.left()), row.bottom()));
            let strip = crate::tab_strip::pill_tabs(ui, egui::Id::new("touch-panel-tabs"), bar, &tabs, &mut sel, false);
            if let Some(&picked) = indices.get(sel) {
                *group.tab_mut(&mut app.ui.dock_tabs) = picked;
            }
            if matches!(strip.context, Some(crate::tab_strip::TabContextAction::CloseGroup)) {
                set_touch_open(ui.ctx(), None);
            }
            ui.add_space(6.0);
            widgets::hairline(ui);
            ui.add_space(8.0);
            let Some(&tab) = indices.get(sel) else { return };
            // Bounded and scrolled exactly as `dock::show` bounds a docked group's body: the
            // tabs that lay out their own list and footer must not be nested in a scroll area.
            let inner = ui.available_height().max(0.0);
            if group.scrolls_itself(tab) {
                ui.set_min_height(inner);
                dock_body(app, ui, group, tab);
            } else {
                offer_color_field_fill(ui, t.pro, group, tab);
                ui.spacing_mut().scroll.fade.strength = 0.0;
                egui::ScrollArea::vertical()
                    .id_salt(("touch-scroll", group.key(), tab))
                    .max_height(inner)
                    .auto_shrink([false, false])
                    .show(ui, |ui| dock_body(app, ui, group, tab));
            }
        });
    });
}

"""

fix_source("crates/ui-egui/src/panels.rs", PANEL_ANCHOR, PANEL + PANEL_ANCHOR, "the touch rail and its panel")

# ---- The rail replaces the dock on Android. A custom workspace (panel_docking) draws its own
# destinations and is left alone.

DOCK_ANCHOR = """pub fn right_dock(app: &mut PhotocraftApp, ui: &mut egui::Ui) {
    // Even legacy destinations must discard gestures captured by an earlier workspace.
    let customized = crate::panel_docking::show(app, ui);"""

DOCK = """
    // On a touch screen nothing docks beside the canvas: the rail holds every group and opens
    // one over the image instead (`touch_rail`, `touch_panel`).
    if cfg!(target_os = "android") && !customized {
        touch_rail(app, ui);
        crate::dock::persist(app, ui.ctx());
        return;
    }"""

fix_source("crates/ui-egui/src/panels.rs", DOCK_ANCHOR, DOCK_ANCHOR + DOCK, "the dock replaced by the rail")

# ---- Studio's floating Properties card would double the rail's Properties entry.

CARD_ANCHOR = """    // Pro (Photoshop) docks Properties; Studio floats it over the canvas.
    if !app.ui.panels.properties || Tokens::get(ctx).pro {
        return;
    }"""

CARD = """    // On a touch screen Properties is a rail entry like every other group, so the floating
    // card would be a second copy of the same panel.
    if cfg!(target_os = "android") {
        return;
    }
"""

fix_source("crates/ui-egui/src/panels.rs", CARD_ANCHOR, CARD + CARD_ANCHOR, "the floating Properties card")

# ---- The panel is drawn after the canvas, over it, where the other floating panels are drawn.

CALL_ANCHOR = """        panels::properties_window(self, &ctx);"""

CALL = """
        // The panel opened from the touch rail, over the canvas (Android).
        panels::touch_panel(self, &ctx);"""

fix_source("crates/ui-egui/src/lib.rs", CALL_ANCHOR, CALL_ANCHOR + CALL, "the call drawing the panel over the canvas")

if missing:
    print(f"  Could not patch the touch rail for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the touch rail for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 10. a selection mode the Quick Selection tool can reach (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# ---- The buttons. Three, not the lasso's four: `select.quick` takes new, add and subtract, and
# has no mode for intersect.

HELPER_ANCHOR = """fn pattern_stamp_options(app: &mut PhotocraftApp, ui: &mut egui::Ui) {"""

HELPER = r"""/// New / Add / Subtract for the Quick Selection tool's options bar.
///
/// Every other selection tool already shows these (`panels::selection_mode_buttons`); this one
/// only had Alt, which a tablet has no key for -- so half the tool was out of reach, and a
/// cut-out, which needs both adding and taking away, could not be finished at all. The state is
/// `selection_mode`, shared with the lasso and the wand, so switching tools keeps the mode.
///
/// Three buttons, because `select.quick` has no intersect mode. Intersect left over from the
/// lasso therefore reads as Add here, which is what the stroke does with it.
fn quick_selection_mode_buttons(app: &mut PhotocraftApp, ui: &mut egui::Ui) {
    ui.spacing_mut().item_spacing.x = 2.0;
    for (mode, icon, tip) in [(0u8, "square", tl!("New selection")), (1, "plus", tl!("Add to selection")), (2, "minus", tl!("Subtract from selection"))] {
        let on = app.ui.selection_mode == mode || (mode == 1 && app.ui.selection_mode == 3);
        if crate::icons::button(ui, icon, 28.0, on, tip).clicked() {
            app.ui.selection_mode = mode;
        }
    }
    ui.spacing_mut().item_spacing.x = 8.0;
}

"""

fix_source("crates/ui-egui/src/retouch_ui.rs", HELPER_ANCHOR, HELPER + HELPER_ANCHOR, "the New/Add/Subtract buttons")

# ---- They go first on the bar, where Photoshop puts them, and replace the "Alt to subtract"
# hint that asked for a key the tablet does not have. `o` is re-borrowed after the call: the
# outer borrow is dead on this arm once nothing below uses it.

BAR_ANCHOR = """        Tool::QuickSelection => {
            crate::widgets::checkbox(ui, &mut o.sample_all.quick_selection, tl!("Sample All Layers"));
            crate::widgets::checkbox(ui, &mut o.enhance_edge, tl!("Enhance Edge"));
            opt(ui, &crate::i18n::fmt(tl!("{key} to subtract"), &[("key", &crate::shortcuts::pretty("Alt"))]));
            crate::widgets::vline(ui, 22.0);"""

BAR = """        Tool::QuickSelection => {
            quick_selection_mode_buttons(app, ui);
            crate::widgets::vline(ui, 22.0);
            let o = &mut app.ui.tool_options;
            crate::widgets::checkbox(ui, &mut o.sample_all.quick_selection, tl!("Sample All Layers"));
            crate::widgets::checkbox(ui, &mut o.enhance_edge, tl!("Enhance Edge"));
            crate::widgets::vline(ui, 22.0);"""

fix_source("crates/ui-egui/src/retouch_ui.rs", BAR_ANCHOR, BAR, "the buttons on the options bar")

# ---- And the stroke honours them. Alt still wins, so the desktop gesture is unchanged.

MODE_ANCHOR = """            let mode = if mods.alt { "subtract" } else { "add" };"""

MODE = """            let mode = if mods.alt {
                "subtract"
            } else {
                match app.ui.selection_mode {
                    0 => "new",
                    2 => "subtract",
                    // Intersect has no mode in `select.quick`; it behaves as Add.
                    _ => "add",
                }
            };"""

fix_source("crates/ui-egui/src/retouch_ui.rs", MODE_ANCHOR, MODE, "the stroke reading the mode")

if missing:
    print(f"  Could not patch the Quick Selection mode for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the Quick Selection mode for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 11. choose the save format inside the app (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# ---- The parked save and the chooser, beside the dialog machinery they belong to.

ASK_ANCHOR = """use crate::PhotocraftApp;
use crate::file_open::display_name;
"""

ASK = r"""
/// A Save As waiting for its format, because the platform save dialog has no file type list.
///
/// On a desktop the format comes from the save dialog's list of file types, which PhotoCraft
/// fills (`SAVE_FILTERS` in the shell) and the system draws. Android's picker has no such list:
/// it gives a folder and a name and nothing else. So every save took whichever extension was
/// suggested, and PSD, PDF, JPEG and the rest could not be chosen at all. The format is picked
/// in the app instead (`save_format_window`), and the folder picker opens after, with the
/// extension already on the name.
pub struct SaveFormatAsk {
    pub suggested: String,
    pub doc: DocId,
    pub plain_save: bool,
    pub choices: crate::FormatChoices,
}

/// The formats offered, in the order they are listed. PSD first: it is PhotoCraft's own default
/// save format, and of these it is what Photoshop reopens with the layers intact.
const SAVE_FORMATS: [(&str, &str, &str); 7] = [
    ("psd", "PSD", "Photoshop: layers, masks, text and smart objects kept"),
    ("pcraft", "PhotoCraft", "Everything PSD keeps, and what PSD has no room for"),
    ("pdf", "PDF", "A document to send or to print"),
    ("png", "PNG", "Flat, lossless, transparency kept"),
    ("jpg", "JPEG", "Flat, small, no transparency"),
    ("tif", "TIFF", "For print; keeps layers when asked"),
    ("webp", "WebP", "Flat and small, for the web"),
];

/// The format chooser for a parked Save As: one finger-sized button per format. Picking one puts
/// its extension on the suggested name and goes on to the folder picker.
pub(crate) fn save_format_window(app: &mut PhotocraftApp, ctx: &egui::Context) {
    if app.save_format.is_none() {
        return;
    }
    let mut picked: Option<&'static str> = None;
    let mut cancel = false;
    let modal = egui::Modal::new(egui::Id::new("save-format")).show(ctx, |ui| {
        ui.set_max_width(420.0);
        ui.label(egui::RichText::new(tl!("Save As")).font(crate::theme::semibold(15.0)));
        ui.add_space(4.0);
        crate::widgets::hairline(ui);
        ui.add_space(8.0);
        ui.label(tl!("Choose a format. The next screen asks where to put the file."));
        ui.add_space(10.0);
        let width = ui.available_width();
        for (ext, name, about) in SAVE_FORMATS {
            let hit = if ext == "psd" { crate::widgets::primary_button(ui, name, width) } else { crate::widgets::secondary_button(ui, name, width) };
            if hit.on_hover_text(tl!(about)).clicked() {
                picked = Some(ext);
            }
            ui.add_space(5.0);
        }
        ui.add_space(6.0);
        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            cancel = crate::widgets::secondary_button(ui, tl!("Cancel"), 84.0).clicked();
        });
    });
    cancel |= modal.should_close();
    if let Some(ext) = picked {
        let Some(ask) = app.save_format.take() else { return };
        let suggested = Path::new(&ask.suggested).with_extension(ext).to_string_lossy().into_owned();
        if let Err(e) = app.save_pick(suggested, ask.doc, ask.plain_save, ask.choices) {
            app.ui.status = crate::i18n::fmt(tl!("Save failed: {error}"), &[("error", &e)]);
            app.ui.status_error = true;
        }
    } else if cancel {
        app.save_format = None;
    }
}
"""

fix_source("crates/ui-egui/src/file_dialog.rs", ASK_ANCHOR, ASK_ANCHOR + ASK, "the format chooser")

# ---- Where the parked save is held.

FIELD_ANCHOR = """    /// A Save As to a layered TIFF parked behind the TIFF Options prompt (see `tiff_options_ui`).
    pub(crate) tiff_options: Option<tiff_options_ui::Prompt>,"""

FIELD = """
    /// A Save As waiting for its format to be chosen in the app, because the platform save
    /// dialog has no file type list (see `file_dialog::SaveFormatAsk`).
    pub(crate) save_format: Option<file_dialog::SaveFormatAsk>,"""

fix_source("crates/ui-egui/src/lib.rs", FIELD_ANCHOR, FIELD_ANCHOR + FIELD, "the field holding it")

INIT_ANCHOR = """            tiff_options: None,
            save_dirs: HashMap::new(),"""

INIT = """            tiff_options: None,
            save_format: None,
            save_dirs: HashMap::new(),"""

fix_source("crates/ui-egui/src/lib.rs", INIT_ANCHOR, INIT, "its initial value")

# ---- Save As parks on a touch screen instead of going straight to the picker. The tail that
# asks where to put the file becomes `save_pick`, so the chooser reuses it unchanged.

FLOW_ANCHOR = """        let doc = st.doc.id;
        self.pick_save(&suggested, move |app, path| {
            app.with_document(doc, |app| {"""

FLOW = """        let doc = st.doc.id;
        // The save dialog's file type list is what chooses the format, and Android's picker has
        // none: it gives a folder and a name. So on a touch screen the format is chosen in the
        // app first (`file_dialog::save_format_window`), which then calls `save_pick` below.
        if cfg!(target_os = "android") {
            if self.save_format.is_none() {
                self.save_format = Some(file_dialog::SaveFormatAsk { suggested, doc, plain_save, choices });
            }
            return Ok(serde_json::json!({"saveFormat": "asking"}));
        }
        self.save_pick(suggested, doc, plain_save, choices)
    }

    /// [`Self::save_dialog_flow`] once the format is settled: ask where to put the file, then
    /// write it there.
    pub(crate) fn save_pick(&mut self, suggested: String, doc: DocId, plain_save: bool, choices: FormatChoices) -> Result<Value, String> {
        self.pick_save(&suggested, move |app, path| {
            app.with_document(doc, |app| {"""

fix_source("crates/ui-egui/src/lib.rs", FLOW_ANCHOR, FLOW, "Save As parked for the format")

# ---- Drawn with the other parked save prompts.

CALL_ANCHOR = """        tiff_options_ui::show(self, &ctx);"""

CALL = """        file_dialog::save_format_window(self, &ctx);
        tiff_options_ui::show(self, &ctx);"""

fix_source("crates/ui-egui/src/lib.rs", CALL_ANCHOR, CALL, "the chooser drawn each frame")

if missing:
    print(f"  Could not patch the save format chooser for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the save format chooser for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 12. Shift, Alt and Ctrl as buttons (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# ---- The block, and the function that folds its state into the frame's input.

BLOCK_ANCHOR = """// ----------------------------------------------------------------------------- properties"""

BLOCK = r"""// ------------------------------------------------------------------ touch modifiers

/// What one of the touch modifier buttons is doing.
#[derive(Clone, Copy, Default, PartialEq, Eq, Debug)]
pub enum Sticky {
    /// Not held.
    #[default]
    Off,
    /// Held for the next gesture, then released by itself.
    Armed,
    /// Held until it is tapped off.
    Locked,
}

/// Height of the block, the side of one of its buttons, and the width of a button and the grip.
const TOUCH_MOD_H: f32 = 56.0;
const TOUCH_MOD_BTN: f32 = 44.0;
const TOUCH_MOD_W: f32 = 54.0;
const TOUCH_MOD_GRIP: f32 = 18.0;

fn touch_mods_id() -> egui::Id {
    egui::Id::new("touch-modifiers")
}

fn touch_mods_rect_id() -> egui::Id {
    egui::Id::new("touch-modifiers-rect")
}

fn touch_mods_offset_id() -> egui::Id {
    egui::Id::new("touch-modifiers-offset")
}

/// Shift, Alt and Ctrl as the block has them: `[shift, alt, ctrl]`.
pub(crate) fn touch_mods(ctx: &egui::Context) -> [Sticky; 3] {
    ctx.data(|d| d.get_temp::<[Sticky; 3]>(touch_mods_id())).unwrap_or_default()
}

fn set_touch_mods(ctx: &egui::Context, state: [Sticky; 3]) {
    ctx.data_mut(|d| d.insert_temp(touch_mods_id(), state));
}

/// The modifiers `state` stands for. Ctrl is also the command modifier: the platform that tells
/// them apart is macOS, which is not where a touch screen runs this.
fn touch_modifiers_of(state: [Sticky; 3]) -> egui::Modifiers {
    let mut m = egui::Modifiers::default();
    m.shift = state[0] != Sticky::Off;
    m.alt = state[1] != Sticky::Off;
    m.ctrl = state[2] != Sticky::Off;
    m.command = state[2] != Sticky::Off;
    m
}

/// `base` with everything `extra` holds added. Only the four fields the block drives are touched,
/// so a modifier the window reported stays as it was.
fn with_modifiers(base: egui::Modifiers, extra: egui::Modifiers) -> egui::Modifiers {
    let mut out = base;
    out.shift |= extra.shift;
    out.alt |= extra.alt;
    out.ctrl |= extra.ctrl;
    out.command |= extra.command;
    out
}

/// Fold the touch modifier block into this frame's input, before any widget reads it.
///
/// A tablet has no Shift, Alt or Ctrl, and 339 behaviours in PhotoCraft are reached only by
/// holding one: subtracting from a selection, constraining proportions, scaling from the centre,
/// duplicating by dragging, stepping a caret word by word. Rather than teach each of those about
/// buttons, the block's state is written into the frame's modifier state and into every event
/// that carries modifiers, so all 339 work unchanged -- and so do the keyboard shortcuts.
///
/// An armed modifier lasts one gesture: the pointer release that ends a gesture on the canvas
/// clears it. A release on the block itself is ignored, or tapping a button would disarm what
/// the tap just armed. A locked modifier stays until it is tapped off.
pub fn apply_touch_modifiers(app: &mut PhotocraftApp, ctx: &egui::Context, raw: &mut egui::RawInput) {
    let state = touch_mods(ctx);
    if state == [Sticky::Off; 3] {
        return;
    }
    let m = touch_modifiers_of(state);
    for e in raw.events.iter_mut() {
        match e {
            egui::Event::PointerButton { modifiers, .. } | egui::Event::Key { modifiers, .. } | egui::Event::MouseWheel { modifiers, .. } => {
                *modifiers = with_modifiers(*modifiers, m);
            }
            egui::Event::ModifiersChanged(k) => *k = with_modifiers(*k, m),
            _ => {}
        }
    }
    raw.events.insert(0, egui::Event::ModifiersChanged(m));
    let canvas = app.last_canvas_rect;
    let block = ctx.data(|d| d.get_temp::<Rect>(touch_mods_rect_id()));
    let ended = raw.events.iter().any(|e| match e {
        egui::Event::PointerButton { pos, pressed: false, .. } => canvas.contains(*pos) && !block.is_some_and(|b| b.contains(*pos)),
        _ => false,
    });
    if ended {
        let mut next = state;
        for s in next.iter_mut() {
            if *s == Sticky::Armed {
                *s = Sticky::Off;
            }
        }
        if next != state {
            set_touch_mods(ctx, next);
        }
    }
}

/// One of the block's buttons: plain when off, outlined in the accent when armed for the next
/// gesture, filled when locked.
fn touch_mods_open_id() -> egui::Id {
    egui::Id::new("touch-mods-open")
}

fn touch_mod_button(ui: &mut egui::Ui, label: &str, state: Sticky) -> egui::Response {
    let t = Tokens::get(ui.ctx());
    let (rect, resp) = ui.allocate_exact_size(vec2(TOUCH_MOD_W, TOUCH_MOD_BTN), Sense::click());
    let (fill, fg) = match state {
        Sticky::Off => (t.field, t.text),
        Sticky::Armed => (t.card, t.accent),
        Sticky::Locked => (t.accent, t.primary_text),
    };
    ui.painter().rect_filled(rect, t.radius_sm, fill);
    if state == Sticky::Armed {
        ui.painter().rect_stroke(rect, t.radius_sm, Stroke::new(1.5, t.accent), StrokeKind::Inside);
    }
    ui.painter().text(rect.center(), Align2::CENTER_CENTER, label, theme::medium(13.0), fg);
    resp
}

/// Shift and Alt floating over the canvas, for a screen with no keyboard (Android). Folded to one
/// small button until asked for, and open by itself on the two tools that cannot work without Alt.
///
/// One tap arms a modifier for the next gesture, a second locks it, a third clears it -- so a
/// single finger can subtract from a selection, and a long piece of work that needs the same
/// modifier throughout can lock it once. Drag the grip to move the block off what is being
/// worked on. `apply_touch_modifiers` is what makes the state real.
pub fn touch_modifiers(app: &mut PhotocraftApp, ctx: &egui::Context) {
    if !cfg!(target_os = "android") || app.ui.docking.is_some() {
        return;
    }
    let canvas = if app.last_canvas_rect.is_positive() { app.last_canvas_rect } else { ctx.content_rect() };
    if !canvas.is_positive() {
        return;
    }
    let t = Tokens::get(ctx);
    let state = touch_mods(ctx);
    let offset: egui::Vec2 = ctx.data(|d| d.get_temp(touch_mods_offset_id())).unwrap_or_default();
    // Above the cutout bar while that is up, so neither covers the other.
    let lift = ctx.data(|d| d.get_temp::<f32>(touch_cutout_lift_id())).unwrap_or(0.0);
    let pos = pos2(canvas.left() + 12.0, canvas.bottom() - TOUCH_MOD_H - 12.0 - lift) + offset;
    let frame = egui::Frame::NONE
        .fill(t.dock)
        .stroke(Stroke::new(1.0, t.card_border))
        .corner_radius(CornerRadius::same(t.radius_lg as u8))
        .shadow(egui::Shadow { offset: [0, 8], blur: 24, spread: 0, color: t.shadow })
        .inner_margin(egui::Margin::same(6));
    let labels = [crate::shortcuts::pretty("Shift"), crate::shortcuts::pretty("Alt")];
    // The Clone Stamp and the Healing Brush take their source from an Alt-tap.
    let needs_alt = matches!(app.ui.tool, Tool::CloneStamp | Tool::Healing);
    let wanted = ctx.data(|d| d.get_temp::<bool>(touch_mods_open_id())).unwrap_or(false);
    let open = wanted || needs_alt;
    let mut wanted_next = wanted;
    let mut next = state;
    let mut drag = egui::Vec2::ZERO;
    // Order::Middle, like the other floating panels, so menus and dialogs stay above it.
    let shown = egui::Area::new(egui::Id::new("touch-mods-area")).order(egui::Order::Middle).fixed_pos(pos).show(ctx, |ui| {
        frame.show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 4.0;
                let (grip, _) = ui.allocate_exact_size(vec2(TOUCH_MOD_GRIP, TOUCH_MOD_BTN), Sense::hover());
                let hold = ui.interact(grip, egui::Id::new("touch-mods-grip"), Sense::drag());
                if hold.hovered() || hold.dragged() {
                    ui.ctx().set_cursor_icon(egui::CursorIcon::Grab);
                }
                drag = hold.drag_delta();
                let c = grip.center();
                for x in [c.x - 3.0, c.x + 3.0] {
                    for y in [c.y - 6.0, c.y, c.y + 6.0] {
                        ui.painter().circle_filled(pos2(x, y), 1.4, t.text_faint);
                    }
                }
                if open {
                    for (i, label) in labels.iter().enumerate() {
                        if touch_mod_button(ui, label, state[i]).clicked() {
                            next[i] = match state[i] {
                                Sticky::Off => Sticky::Armed,
                                Sticky::Armed => Sticky::Locked,
                                Sticky::Locked => Sticky::Off,
                            };
                        }
                    }
                    if !needs_alt && icons::button(ui, "x", TOUCH_MOD_BTN, false, "").clicked() {
                        wanted_next = false;
                    }
                } else if touch_mod_button(ui, "Maj/Alt", Sticky::Off).clicked() {
                    wanted_next = true;
                }
            });
        });
    });
    let rect = shown.response.rect;
    ctx.data_mut(|d| d.insert_temp(touch_mods_rect_id(), rect));
    if drag != egui::Vec2::ZERO {
        // Keep the block inside the canvas, as the Properties card keeps its title bar inside it.
        let r = rect.translate(drag);
        let dx = (canvas.left() - r.left()).max(0.0) - (r.right() - canvas.right()).max(0.0);
        let dy = (canvas.top() - r.top()).max(0.0) - (r.bottom() - canvas.bottom()).max(0.0);
        ctx.data_mut(|d| d.insert_temp(touch_mods_offset_id(), offset + drag + vec2(dx, dy)));
    }
    if wanted_next != wanted {
        ctx.data_mut(|d| d.insert_temp(touch_mods_open_id(), wanted_next));
    }
    // A folded block holds nothing: no modifier stays on with no button to show it.
    if !(wanted_next || needs_alt) {
        next = [Sticky::Off; 3];
    }
    if next != state {
        set_touch_mods(ctx, next);
    }
}

"""

fix_source("crates/ui-egui/src/panels.rs", BLOCK_ANCHOR, BLOCK + BLOCK_ANCHOR, "the modifier block")

# ---- Folded into the input before any widget reads it, beside the other input fix-ups.

HOOK_ANCHOR = """        // A pen held still is no touch screen's press-and-hold right click (stylus.rs).
        let pen_down = self.stylus.pen_contacts.observe(&raw_input.events);"""

HOOK = """        // Shift, Alt and Ctrl tapped on the touch modifier block stand in for the keys a tablet
        // has not got: they join this frame's modifiers and every event that carries them.
        panels::apply_touch_modifiers(self, ctx, raw_input);
"""

fix_source("crates/ui-egui/src/lib.rs", HOOK_ANCHOR, HOOK + HOOK_ANCHOR, "the modifiers folded into the input")

# ---- Drawn over the canvas, with the other floating panels.

CALL_ANCHOR = """        brush_panel::window(self, &ctx);"""

CALL = """        panels::touch_modifiers(self, &ctx);
        brush_panel::window(self, &ctx);"""

fix_source("crates/ui-egui/src/lib.rs", CALL_ANCHOR, CALL, "the block drawn over the canvas")

if missing:
    print(f"  Could not patch the touch modifiers for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the touch modifiers for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 13. a memory budget a tablet actually has (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


OLD = """            memory_usage_mb: DEFAULT_MEMORY_USAGE_MB,
            history_states: 50,"""

NEW = """            // 8 GB and fifty undo steps are a workstation's numbers. Android shares one pool of
            // memory between the system, the screen and every app, and kills the one that grows:
            // a save, which gathers a layer's pixels and the channel planes made from them at the
            // same time, is where it was being killed. 1 GB and twenty steps leave the document's
            // pixels untouched -- the budget drops the oldest history states, nothing else -- and
            // both stay on Preferences > Performance for a tablet that can afford more.
            memory_usage_mb: if cfg!(target_os = "android") { 1024 } else { DEFAULT_MEMORY_USAGE_MB },
            history_states: if cfg!(target_os = "android") { 20 } else { 50 },"""

fix_source("crates/engine/src/prefs.rs", OLD, NEW, "the memory budget and the history depth")

if missing:
    print(f"  Could not patch the memory budget for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the memory budget for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 14. dialogs that fit the screen they open on (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

D = "crates/ui-egui/src/dialogs.rs"
fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# ---- The size a dialog opens at has to fit the window it opens in.

OPEN_OLD = """        let resize = resizable.map(|size| {
            let min = resizable_min(&fields);
            (remembered.unwrap_or(size), min, resizable_max(ctx, &fields, min))
        });"""

OPEN_NEW = """        let resize = resizable.map(|size| {
            let min = resizable_min(&fields);
            let max = resizable_max(ctx, &fields, min);
            // The size a dialog OPENS at has to fit the window it opens in, not only the size it
            // can be dragged to. 620 x 480 is written for a monitor. A tablet held upright gives
            // about 533 points across, so New Document opened wider than the screen and its
            // right-hand column -- the one holding Create -- was not on the screen at all, with
            // nothing to show there was more. Clamping here keeps the roomy layout everywhere it
            // fits and trims it only where it does not.
            let fit = |v: egui::Vec2| egui::vec2(v.x.clamp(min.x, max.x), v.y.clamp(min.y, max.y));
            (fit(remembered.unwrap_or(size)), min, max)
        });"""

fix_source(D, OPEN_OLD, OPEN_NEW, "dialogs opening no wider than the screen")

# ---- And room for the system bars underneath.

ROOM_OLD = """    let mut max = (ctx.content_rect().size() - egui::vec2(40.0, 40.0)).max(min);"""

ROOM_NEW = """    // 40 points of breathing room on a desktop. On Android the window runs under the system
    // navigation bar, so a centred dialog as tall as the screen allows had its bottom row -- the
    // one with Create -- sitting on top of the back and home buttons. Leaving more pulls it clear.
    let room = if cfg!(target_os = "android") { egui::vec2(40.0, 112.0) } else { egui::vec2(40.0, 40.0) };
    let mut max = (ctx.content_rect().size() - room).max(min);"""

fix_source(D, ROOM_OLD, ROOM_NEW, "room for the system bars")

if missing:
    print(f"  Could not patch the dialog sizes for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the dialog sizes for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 15. menus that open on a tap, not on a held finger (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

P = "crates/ui-egui/src/press_menu.rs"
fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# ---- The menu opens on the release, not the press.

OPEN_OLD = """    // A press this frame on the button (still down, or a whole click within one frame).
    let pressed = ctx.input(|i| i.pointer.primary_pressed()) && (button.is_pointer_button_down_on() || button.clicked());"""

OPEN_NEW = """    // A touch screen has no press-drag-release. A finger that moves three points between the
    // press and the release is a drag, not a click, so the release that ended the opening press
    // counted as a click outside the menu and shut it again: the menu stayed up only while the
    // finger stayed down, and choosing an item meant pressing, sliding onto it and letting go.
    // So on Android the menu opens on the release and waits there: tap to open, tap to choose.
    if cfg!(target_os = "android") {
        if !button.clicked() {
            return None;
        }
        return Some(SetOpenCommand::Bool(!Popup::is_id_open(ctx, popup)));
    }
    // A press this frame on the button (still down, or a whole click within one frame).
    let pressed = ctx.input(|i| i.pointer.primary_pressed()) && (button.is_pointer_button_down_on() || button.clicked());"""

fix_source(P, OPEN_OLD, OPEN_NEW, "menus opening on the tap")

# ---- And nothing but a tap outside closes it. An item still closes it itself (`item_response`).

CLOSE_OLD = """    let close = if button.clicked() && menu.owns_gesture(&ctx) { PopupCloseBehavior::IgnoreClicks } else { PopupCloseBehavior::CloseOnClick };"""

CLOSE_NEW = """    let close = if cfg!(target_os = "android") {
        // The tap that opened it must not shut it, and a tap inside is the item's own business.
        PopupCloseBehavior::CloseOnClickOutside
    } else if button.clicked() && menu.owns_gesture(&ctx) {
        PopupCloseBehavior::IgnoreClicks
    } else {
        PopupCloseBehavior::CloseOnClick
    };"""

fix_source(P, CLOSE_OLD, CLOSE_NEW, "menus staying open until a tap outside")

# ---- The same for the drop-down lists (blend mode, and every other combo box).

COMBO_OLD = """        if combo.owns_gesture(ctx) && ctx.input(|i| i.pointer.primary_clicked()) {
            Popup::close_id(ctx, combo.popup);
            return (combo, PopupCloseBehavior::IgnoreClicks);
        }
        (combo, PopupCloseBehavior::CloseOnClick)"""

COMBO_NEW = """        // On a touch screen the box keeps egui's own behaviour: a tap opens the list, a tap on
        // an option chooses it, a tap outside closes it. Nothing is opened on the press.
        if cfg!(target_os = "android") {
            return (combo, PopupCloseBehavior::CloseOnClickOutside);
        }
        if combo.owns_gesture(ctx) && ctx.input(|i| i.pointer.primary_clicked()) {
            Popup::close_id(ctx, combo.popup);
            return (combo, PopupCloseBehavior::IgnoreClicks);
        }
        (combo, PopupCloseBehavior::CloseOnClick)"""

fix_source(P, COMBO_OLD, COMBO_NEW, "drop-down lists opening on the tap")

AFTER_OLD = """        let pressed = ctx.input(|i| i.pointer.primary_pressed()) && button.is_pointer_button_down_on();
        if pressed && !Popup::is_id_open(ctx, self.popup) {"""

AFTER_NEW = """        let pressed = !cfg!(target_os = "android") && ctx.input(|i| i.pointer.primary_pressed()) && button.is_pointer_button_down_on();
        if pressed && !Popup::is_id_open(ctx, self.popup) {"""

fix_source(P, AFTER_OLD, AFTER_NEW, "no press-open on the lists")

if missing:
    print(f"  Could not patch the tap menus for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the tap menus for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 16. Quick Selection grows again after its first stroke (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


OLD = """            let r = app.run("select.quick", json!({"points": xy, "size": size, "mode": mode, "enhanceEdge": enhance, "sampleAllLayers": sample_all}));
            report_smart_result(app, r, tl!("Quick Selection found nothing there"));"""

NEW = """            let r = app.run("select.quick", json!({"points": xy, "size": size, "mode": mode, "enhanceEdge": enhance, "sampleAllLayers": sample_all}));
            // Quick Selection is built stroke by stroke, so New applies to the first stroke only
            // and the tool then switches to Add, as Photoshop's does. Before section 10 the stroke
            // was always an add; reading the options bar's mode made New the default and every
            // stroke wiped the one before it, which is no way to cut anything out.
            if mode == "new" {
                app.ui.selection_mode = 1;
            }
            report_smart_result(app, r, tl!("Quick Selection found nothing there"));"""

fix_source("crates/ui-egui/src/retouch_ui.rs", OLD, NEW, "New applying to the first stroke only")

if missing:
    print(f"  Could not patch the Quick Selection mode switch for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the Quick Selection mode switch for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 17. a short tool column, and every tool one tap away (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)


# ---- The slots the column keeps, and the grid that holds the rest.

GRID_ANCHOR = """/// A primary-button gesture started on this tool; open only after it leaves its hit area."""

GRID = r"""/// The slots the tool column keeps on a touch screen, by their index in [`TOOL_SECTIONS`]: Move,
/// the lasso, the selection family, Crop, Brush, Eraser, Type and Zoom. Twenty-one slots of
/// 40-point buttons do not fit a 10-inch screen and leave nothing for the image; the rest are one
/// tap away under the column's own "..." button (`tool_grid`), as Photoshop is on a tablet.
const TOUCH_SLOTS: [usize; 8] = [0, 2, 3, 4, 8, 11, 16, 20];

fn tool_grid_id() -> egui::Id {
    egui::Id::new("tool-grid-open")
}

pub(crate) fn tool_grid_open(ctx: &egui::Context) -> bool {
    ctx.data(|d| d.get_temp::<bool>(tool_grid_id())).unwrap_or(false)
}

pub(crate) fn set_tool_grid_open(ctx: &egui::Context, open: bool) {
    ctx.data_mut(|d| d.insert_temp(tool_grid_id(), open));
}

/// Every tool at once, over the canvas: what the column's "..." button opens on a touch screen.
///
/// Four to a row, each with its name under its icon -- a tool is no use if you cannot tell which
/// it is, and the column has no room for names. Tapping one selects it and closes the grid. The
/// tools hidden in Edit > Toolbar stay hidden here too.
pub fn tool_grid(app: &mut PhotocraftApp, ctx: &egui::Context) {
    if !tool_grid_open(ctx) {
        return;
    }
    let t = Tokens::get(ctx);
    let canvas = if app.last_canvas_rect.is_positive() { app.last_canvas_rect } else { ctx.content_rect() };
    if !canvas.is_positive() {
        set_tool_grid_open(ctx, false);
        return;
    }
    let cell = vec2(74.0, 62.0);
    let width = cell.x * 4.0 + 6.0 * 3.0 + 24.0;
    let height = (canvas.height() - 24.0).min(430.0).max(180.0);
    let x = if crate::direction::is_rtl() { canvas.right() - width - 12.0 } else { canvas.left() + 12.0 };
    let frame = egui::Frame::NONE
        .fill(t.card)
        .stroke(Stroke::new(1.0, t.card_border))
        .corner_radius(CornerRadius::same(t.radius_lg as u8))
        .shadow(egui::Shadow { offset: [0, 12], blur: 36, spread: 0, color: t.shadow })
        .inner_margin(egui::Margin::same(12));
    let shown = visible_sections(&app.session.prefs().toolbar.hidden);
    let tools: Vec<Tool> = shown.into_iter().flatten().flat_map(|(_, slot)| slot).collect();
    let mut chosen = None;
    let mut shut = false;
    egui::Area::new(egui::Id::new("tool-grid-area")).order(egui::Order::Middle).fixed_pos(pos2(x, canvas.top() + 12.0)).show(ctx, |ui| {
        frame.show(ui, |ui| {
            ui.set_width(width - 24.0);
            ui.set_height(height - 24.0);
            ui.horizontal(|ui| {
                ui.label(egui::RichText::new(tl!("Tools")).font(theme::semibold(14.0)));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    if icons::button(ui, "x", 30.0, false, tl!("Close")).clicked() {
                        shut = true;
                    }
                });
            });
            ui.add_space(4.0);
            widgets::hairline(ui);
            ui.add_space(8.0);
            let room = ui.available_height().max(0.0);
            egui::ScrollArea::vertical().id_salt("tool-grid-scroll").max_height(room).auto_shrink([false, false]).show(ui, |ui| {
                ui.spacing_mut().item_spacing = vec2(6.0, 6.0);
                for row in tools.chunks(4) {
                    ui.horizontal(|ui| {
                        for &tool in row {
                            let (r, resp) = ui.allocate_exact_size(cell, Sense::click());
                            let on = app.ui.tool == tool;
                            if on || resp.hovered() {
                                ui.painter().rect_filled(r, t.radius_sm, if on { t.accent } else { t.hover });
                            }
                            let fg = if on { t.primary_text } else { t.text };
                            icons::paint(ui, Rect::from_center_size(pos2(r.center().x, r.top() + 22.0), vec2(22.0, 22.0)), icons::tool_icon(tool), 22.0, fg);
                            let galley = ui.painter().layout(tl!(tool.label()).to_string(), theme::medium(9.5), fg, cell.x - 6.0);
                            ui.painter().galley(pos2(r.center().x - galley.size().x / 2.0, r.top() + 38.0), galley, fg);
                            if resp.clicked() {
                                chosen = Some(tool);
                            }
                        }
                    });
                }
            });
        });
    });
    if let Some(tool) = chosen {
        crate::tool_memory::select(app, tool);
        set_tool_grid_open(ctx, false);
    } else if shut {
        set_tool_grid_open(ctx, false);
    }
}

/// A primary-button gesture started on this tool; open only after it leaves its hit area."""

fix_source("crates/ui-egui/src/panels.rs", GRID_ANCHOR, GRID, "the full tool grid")

# ---- The column keeps the basics.

COL_ANCHOR = """    let sections = visible_sections(&app.session.prefs().toolbar.hidden);"""

COL = """    let sections = visible_sections(&app.session.prefs().toolbar.hidden);
    // On a touch screen the column keeps the eight slots a tablet needs at hand, in one group, and
    // its "..." button below opens the rest (`tool_grid`).
    let sections: Vec<Vec<(usize, Vec<Tool>)>> =
        if cfg!(target_os = "android") { vec![sections.into_iter().flatten().filter(|(i, _)| TOUCH_SLOTS.contains(i)).collect()] } else { sections };"""

fix_source("crates/ui-egui/src/panels.rs", COL_ANCHOR, COL, "the column keeping the basics")

# ---- And its "..." button opens them, instead of a dialog written for a mouse.

ELL = chr(0x2026)

DOTS_ANCHOR = (
    '                    if icons::button(ui, "ellipsis", bx, false, tl!("Edit Toolbar' + ELL + '")).clicked() {\n'
    '                        let _ = crate::menus::invoke(app, &ctx, "edit.toolbar", json!({}));\n'
    '                    }'
)

DOTS = (
    '                    let dots_tip = if cfg!(target_os = "android") { tl!("All Tools") } else { tl!("Edit Toolbar' + ELL + '") };\n'
    '                    if icons::button(ui, "ellipsis", bx, tool_grid_open(&ctx), dots_tip).clicked() {\n'
    '                        if cfg!(target_os = "android") {\n'
    '                            // A second tap closes it, like every other panel on a touch screen.\n'
    '                            set_tool_grid_open(&ctx, !tool_grid_open(&ctx));\n'
    '                        } else {\n'
    '                            let _ = crate::menus::invoke(app, &ctx, "edit.toolbar", json!({}));\n'
    '                        }\n'
    '                    }'
)

fix_source("crates/ui-egui/src/panels.rs", DOTS_ANCHOR, DOTS, "the ... button opening the grid")

# ---- Drawn over the canvas, with the other floating panels.

# Anchored on its own line, away from the other floating panels this script inserts, so each
# section's guard keeps matching when the next one runs (the script must be replayable).
CALL_ANCHOR = """        preset_panels::windows(self, &ctx);"""

CALL = """        preset_panels::windows(self, &ctx);
        panels::tool_grid(self, &ctx);"""

fix_source("crates/ui-egui/src/lib.rs", CALL_ANCHOR, CALL, "the grid drawn over the canvas")

if missing:
    print(f"  Could not patch the tool grid for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the tool grid for {app}: {', '.join(fixed)}")
PY
fi


# --------------------------- 18. installing fonts from inside the app (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)

ELL = chr(0x2026)
E = chr(0xE9)

# Nothing in PhotoCraft installs a font: on Android the only way in was a Fonts folder at the root
# of the storage plus "all files access" plus a restart, and nothing in the app says so. This adds
# Type > Installer des polices... : the chosen files are registered at once (the font menus follow
# the shared generation) and copied to the app's own storage, which needs no permission. The copy
# sits in a subfolder of $HOME/.fonts because system_font_dirs() walks subfolders and the launcher's
# link_fonts() replaces same-named entries of that folder itself: a font named like a system font
# would otherwise be lost at the next start.

ANCHOR = "/// Does the layer use one of `families`, by name or through the PostScript name a PSD gave?"

INSTALL = """/// Type > install fonts: ask for font files, whatever their type (a font's MIME type is unreliable
/// on Android, so the files themselves are the test).
pub(crate) fn ask_and_install(app: &mut PhotocraftApp) -> Result<serde_json::Value, String> {
    use crate::file_dialog::{FileDialogAnswer, FileDialogRequest};
    let request = FileDialogRequest::Open { multiple: true, initial_dir: None, extensions: None };
    app.ask_file(request, |app, answer| {
        let files: Vec<(String, Vec<u8>)> = match answer {
            FileDialogAnswer::Contents(name, bytes) => vec![(name, bytes)],
            FileDialogAnswer::ContentsMany(files) => files,
            FileDialogAnswer::Paths(paths) => paths
                .into_iter()
                .filter_map(|path| {
                    let bytes = photocraft_format::read_file(std::path::Path::new(&path)).ok()?;
                    Some((path, bytes))
                })
                .collect(),
            _ => Vec::new(),
        };
        install_user_fonts(app, files.into_iter().flat_map(|(name, bytes)| fonts_of_file(name, bytes)).collect())
    })
}

/// Type > install a folder of fonts. The Activity sees this mark in place of a list of extensions,
/// asks for a folder instead of files, and answers with every font file under it, staged as files:
/// the adapter's Open path carries that answer unchanged, so no new request type is needed.
pub(crate) fn ask_and_install_folder(app: &mut PhotocraftApp) -> Result<serde_json::Value, String> {
    use crate::file_dialog::{FileDialogAnswer, FileDialogRequest};
    let request = FileDialogRequest::Open { multiple: true, initial_dir: None, extensions: Some(vec!["__fontfolder__".to_string()]) };
    app.ask_file(request, |app, answer| {
        let FileDialogAnswer::Paths(paths) = answer else { return install_user_fonts(app, Vec::new()) };
        let files: Vec<(String, Vec<u8>)> = paths
            .into_iter()
            .filter_map(|path| {
                let bytes = photocraft_format::read_file(std::path::Path::new(&path)).ok()?;
                Some((path, bytes))
            })
            .flat_map(|(name, bytes)| fonts_of_file(name, bytes))
            .collect();
        install_user_fonts(app, files)
    })
}

/// The fonts a picked file holds: itself, or what a zip archive carries (most fonts are downloaded
/// as a zip). An archive with none stays as it is, to be counted as refused.
fn fonts_of_file(name: String, bytes: Vec<u8>) -> Vec<(String, Vec<u8>)> {
    if bytes.starts_with(&[0x50, 0x4b, 3, 4]) {
        let inner = fonts_in_zip(&bytes);
        if !inner.is_empty() {
            return inner;
        }
    }
    vec![(name, bytes)]
}

/// Reads a zip's central directory by hand: flate2 is already linked, and only two storage methods
/// exist in practice. A damaged entry is skipped, not an error.
fn fonts_in_zip(zip: &[u8]) -> Vec<(String, Vec<u8>)> {
    use std::io::Read;
    const MAX_FONT_BYTES: u64 = 64 * 1024 * 1024;
    let u16_at = |at: usize| zip.get(at..at + 2).map(|b| usize::from(u16::from_le_bytes([b[0], b[1]])));
    let u32_at = |at: usize| zip.get(at..at + 4).map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize);
    let mut fonts = Vec::new();
    let Some(end) = zip.windows(4).rposition(|w| w == [0x50, 0x4b, 5, 6]) else { return fonts };
    let (Some(count), Some(mut at)) = (u16_at(end + 10), u32_at(end + 16)) else { return fonts };
    for _ in 0..count {
        if zip.get(at..at + 4) != Some(&[0x50, 0x4b, 1, 2][..]) {
            break;
        }
        let (Some(method), Some(packed), Some(name_len), Some(extra), Some(comment), Some(local)) =
            (u16_at(at + 10), u32_at(at + 20), u16_at(at + 28), u16_at(at + 30), u16_at(at + 32), u32_at(at + 42))
        else {
            break;
        };
        let name = zip.get(at + 46..at + 46 + name_len).map(|b| String::from_utf8_lossy(b).into_owned()).unwrap_or_default();
        at += 46 + name_len + extra + comment;
        let lower = name.to_lowercase();
        if lower.contains("__macosx") || ![".ttf", ".otf", ".ttc", ".otc"].iter().any(|e| lower.ends_with(e)) {
            continue;
        }
        let (Some(local_name), Some(local_extra)) = (u16_at(local + 26), u16_at(local + 28)) else { continue };
        let start = local + 30 + local_name + local_extra;
        let Some(data) = zip.get(start..start.saturating_add(packed)) else { continue };
        let mut out = Vec::new();
        let read = match method {
            0 => data.take(MAX_FONT_BYTES).read_to_end(&mut out).is_ok(),
            8 => flate2::read::DeflateDecoder::new(data).take(MAX_FONT_BYTES).read_to_end(&mut out).is_ok(),
            _ => false,
        };
        if read {
            fonts.push((name, out));
        }
    }
    fonts
}

/// Keep a font for the next start, in a folder the font scan walks.
fn keep_font_file(dir: &std::path::Path, name: &str, bytes: &[u8]) -> std::io::Result<()> {
    std::fs::create_dir_all(dir)?;
    let stem: String = std::path::Path::new(name)
        .file_stem()
        .map(|s| s.to_string_lossy().chars().filter(|c| c.is_alphanumeric() || matches!(*c, '-' | '_' | ' ')).collect())
        .unwrap_or_default();
    let stem = if stem.is_empty() { format!("font-{}", bytes.len()) } else { stem };
    // The scan goes by extension, and a picked file does not always keep its own.
    let ext = match bytes.get(..4) {
        Some(b"OTTO") => "otf",
        Some(b"ttcf") => "ttc",
        _ => "ttf",
    };
    std::fs::write(dir.join(format!("{stem}.{ext}")), bytes)
}

fn install_user_fonts(app: &mut PhotocraftApp, files: Vec<(String, Vec<u8>)>) -> Result<serde_json::Value, String> {
    let dir = std::env::var_os("HOME").map(|home| std::path::PathBuf::from(home).join(".fonts").join("installed"));
    let mut families: Vec<String> = Vec::new();
    let mut refused = 0usize;
    let mut unsaved = dir.is_none();
    {
        let mut eng = photocraft_text::shared().lock().unwrap_or_else(PoisonError::into_inner);
        for (name, bytes) in files {
            let added = eng.fonts.register_font_data(bytes.clone());
            if added.is_empty() {
                refused += 1;
                continue;
            }
            if let Some(dir) = &dir
                && let Err(e) = keep_font_file(dir, &name, &bytes)
            {
                log::warn!("could not keep the font {name}: {e}");
                unsaved = true;
            }
            for family in added {
                if !families.contains(&family) {
                    families.push(family);
                }
            }
        }
    }
    if families.is_empty() {
        return Err("Aucune police install@E@e : choisis des polices .ttf, .otf, .ttc ou .otc, ou un .zip qui en contient".into());
    }
    // Text already waiting for one of these families is drawn again, as when a served font arrives.
    let mut layers: Vec<(DocId, LayerId)> = Vec::new();
    for st in app.session.documents() {
        for (_, _, l) in st.doc.walk() {
            if let LayerContent::Text(t) = &l.content
                && uses_family(t, &families)
                && crate::type_tool::shows_own_layout(&st.doc, t)
                && !layers.contains(&(st.doc.id, l.id))
            {
                layers.push((st.doc.id, l.id));
            }
        }
    }
    if !layers.is_empty() {
        let busy = app.session.refresh_type_layers(&layers);
        PENDING.lock().unwrap_or_else(PoisonError::into_inner).extend(busy);
    }
    let mut status = format!("Install@E@e : {}", families.join(", "));
    if refused > 0 {
        status.push_str(&format!(" ({refused} fichier(s) refus@E@(s), ce ne sont pas des polices)"));
    }
    if unsaved {
        status.push_str(" (pour cette session seulement : copie impossible)");
    }
    app.ui.status = status;
    app.ui.status_error = refused > 0 || unsaved;
    Ok(serde_json::json!({ "families": families, "refused": refused }))
}

""".replace("@E@", E)

fix_source("crates/ui-egui/src/served_fonts.rs", ANCHOR, INSTALL + ANCHOR, "the font installer")

ROW_ANCHOR = '    (&["Type"], "Resolve Missing Fonts' + ELL + '", None, "type.resolveMissingFonts"),'
ROW = ROW_ANCHOR + '\n    (&["Type"], "Installer des polices' + ELL + '", None, "type.installFonts"),\n    (&["Type"], "Installer un dossier de polices' + ELL + '", None, "type.installFontFolder"),'
fix_source("crates/ui-egui/src/menu_catalog.rs", ROW_ANCHOR, ROW, "the Type menu entry")

RUN_ANCHOR = """        "select.selectAndMask" => Ok(json!({"dialog": crate::filter_dialog::open(app, "select.refineEdge")})),"""
RUN = """        "type.installFonts" => crate::served_fonts::ask_and_install(app),\n        "type.installFontFolder" => crate::served_fonts::ask_and_install_folder(app),\n""" + RUN_ANCHOR
fix_source("crates/ui-egui/src/menus.rs", RUN_ANCHOR, RUN, "the menu entry's action")

ON_ANCHOR = """        "select.selectAndMask" => app.session.is_enabled("select.refineEdge"),"""
ON = """        "type.installFonts" => true,\n        "type.installFontFolder" => true,\n""" + ON_ANCHOR
fix_source("crates/ui-egui/src/menus.rs", ON_ANCHOR, ON, "the menu entry enabled")

# A menu row only goes live once the shell declares its command.
SHELL_ANCHOR = """    ("type.editText", "Edit Type", &[], None),"""
SHELL = """    ("type.installFonts", "Installer des polices""" + ELL + """", &["Type"], None),
    ("type.installFontFolder", "Installer un dossier de polices""" + ELL + """", &["Type"], None),
""" + SHELL_ANCHOR
fix_source("crates/engine/src/shell_commands.rs", SHELL_ANCHOR, SHELL, "the command declared to the shell")

# The same action where a font is chosen: the Character panel, under the rail on a tablet.
PANEL_ANCHOR = """        let mut fam = c.font_family.clone();
        let mut ready = true;
        row(ui, &mut |ui| {
            ready = fonts_ready(ui, full);"""
PANEL = """        if cfg!(target_os = "android") && crate::widgets::secondary_button(ui, "Installer des polices""" + ELL + """", full).clicked() {
            let _ = crate::menus::invoke(app, ui.ctx(), "type.installFonts", json!({}));
        }
        if cfg!(target_os = "android") && crate::widgets::secondary_button(ui, "Installer un dossier de polices""" + ELL + """", full).clicked() {
            let _ = crate::menus::invoke(app, ui.ctx(), "type.installFontFolder", json!({}));
        }
""" + PANEL_ANCHOR
fix_source("crates/ui-egui/src/type_tool.rs", PANEL_ANCHOR, PANEL, "the button in the Character panel")

if missing:
    print(f"  Could not patch the font installer for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the font installer for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 19. a cutout bar a finger can reach (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)

ELL = chr(0x2026)
E = chr(0xE9)

# Subject, Select and Mask and the output to a mask all exist, spread over menus and an options bar
# written for a mouse. While a selection tool is active this bar puts them in one row above the
# thumb, as Affinity's context toolbar and Photoshop on iPad's do. It calls the commands the menus
# call; no selection code changes.

ANCHOR = "/// New / add / subtract / intersect selection buttons (shared by selection tools)."

BAR = """fn touch_cutout_lift_id() -> egui::Id {
    egui::Id::new("touch-cutout-lift")
}

fn touch_cutout_text_button(ui: &mut egui::Ui, label: &str, enabled: bool) -> bool {
    let t = Tokens::get(ui.ctx());
    let fg = if enabled { t.text } else { t.text_faint };
    let width = ui.painter().layout_no_wrap(label.to_string(), theme::medium(13.0), fg).size().x + 20.0;
    let (rect, resp) = ui.allocate_exact_size(vec2(width.max(44.0), 44.0), Sense::click());
    ui.painter().rect_filled(rect, t.radius_sm, t.field);
    ui.painter().text(rect.center(), Align2::CENTER_CENTER, label, theme::medium(13.0), fg);
    enabled && resp.clicked()
}

/// The cutout controls over the canvas while a selection tool is active (Android).
pub fn touch_cutout_bar(app: &mut PhotocraftApp, ctx: &egui::Context) {
    let tool = app.ui.tool;
    let canvas = app.last_canvas_rect;
    let shown = cfg!(target_os = "android")
        && app.ui.docking.is_none()
        && app.ui.dialogs.is_empty()
        && app.ui.transform.is_none()
        && canvas.is_positive()
        && app.session.active().is_some()
        && matches!(
            tool,
            Tool::RectMarquee
                | Tool::EllipseMarquee
                | Tool::Lasso
                | Tool::PolygonLasso
                | Tool::MagneticLasso
                | Tool::MagicWand
                | Tool::QuickSelection
                | Tool::ObjectSelection
        );
    if !shown {
        ctx.data_mut(|d| d.insert_temp(touch_cutout_lift_id(), 0.0f32));
        return;
    }
    let t = Tokens::get(ctx);
    let mode = app.ui.selection_mode;
    let has_selection = app.session.active().is_some_and(|d| d.doc.selection.is_some());
    let can_refine = crate::menus::is_enabled(app, "select.selectAndMask");
    let size = app.session.tools.brush.size;
    let frame = egui::Frame::NONE
        .fill(t.dock)
        .stroke(Stroke::new(1.0, t.card_border))
        .corner_radius(CornerRadius::same(t.radius_lg as u8))
        .shadow(egui::Shadow { offset: [0, 8], blur: 24, spread: 0, color: t.shadow })
        .inner_margin(egui::Margin::same(6));
    let mut action: Option<&'static str> = None;
    let width = (canvas.width() - 24.0).max(200.0);
    let area = egui::Area::new(egui::Id::new("touch-cutout-area"))
        .order(egui::Order::Middle)
        .pivot(Align2::CENTER_BOTTOM)
        .fixed_pos(pos2(canvas.center().x, canvas.bottom() - 12.0))
        .show(ctx, |ui| {
            frame.show(ui, |ui| {
                ui.set_max_width(width);
                ui.spacing_mut().item_spacing = vec2(4.0, 4.0);
                ui.horizontal_wrapped(|ui| {
                    if touch_cutout_text_button(ui, "Sujet", true) {
                        action = Some("subject");
                    }
                    for (icon, on, id) in [("square", mode == 0, "new"), ("plus", mode == 1 || mode == 3, "add"), ("minus", mode == 2, "subtract")] {
                        if icons::button_with_icon_size(ui, icon, 44.0, 20.0, on, "").clicked() {
                            action = Some(id);
                        }
                    }
                    if tool == Tool::QuickSelection {
                        if icons::button_with_icon_size(ui, "chevron-down", 44.0, 20.0, false, "").clicked() {
                            action = Some("smaller");
                        }
                        let (value, _) = ui.allocate_exact_size(vec2(36.0, 44.0), Sense::hover());
                        ui.painter().text(value.center(), Align2::CENTER_CENTER, format!("{size:.0}"), theme::medium(13.0), t.text);
                        if icons::button_with_icon_size(ui, "chevron-up", 44.0, 20.0, false, "").clicked() {
                            action = Some("larger");
                        }
                    }
                    if touch_cutout_text_button(ui, "Am@E@liorer le contour", can_refine) {
                        action = Some("refine");
                    }
                    if touch_cutout_text_button(ui, "Masque", has_selection) {
                        action = Some("mask");
                    }
                });
            });
        });
    let lift = area.response.rect.height() + 8.0;
    ctx.data_mut(|d| d.insert_temp(touch_cutout_lift_id(), lift));
    match action {
        Some("subject") => {
            let result = app.run("select.subject", json!({}));
            let found = result.is_ok();
            crate::retouch_ui::report_smart_result(app, result, "Aucun sujet trouv@E@ : essaie la S@E@lection rapide ou le Lasso");
            // A cutout goes on from the subject: the next stroke corrects it instead of replacing it.
            if found {
                app.ui.selection_mode = 1;
            }
        }
        Some("new") => app.ui.selection_mode = 0,
        Some("add") => app.ui.selection_mode = 1,
        Some("subtract") => app.ui.selection_mode = 2,
        Some(step @ ("smaller" | "larger")) => {
            let before = app.session.tools.brush.clone();
            let mut brush = before.clone();
            brush.size = if step == "larger" { (size * 1.25).max(size + 1.0).min(5000.0) } else { (size * 0.8).max(1.0) };
            crate::brush_panel::commit_gesture(app, ctx, &before, &brush);
        }
        Some("refine") => {
            if let Err(e) = crate::menus::invoke(app, ctx, "select.selectAndMask", json!({})) {
                app.ui.status = e;
                app.ui.status_error = true;
            }
        }
        Some("mask") => {
            if let Err(e) = app.run("select.refineEdge", json!({"output": "layerMask"})) {
                app.ui.status = e;
                app.ui.status_error = true;
            }
        }
        _ => {}
    }
}

""".replace("@E@", E)

fix_source("crates/ui-egui/src/panels.rs", ANCHOR, BAR + ANCHOR, "the cutout bar")

CALL_ANCHOR = """        dialogs::show(self, &ctx);"""
CALL = """        panels::touch_cutout_bar(self, &ctx);\n""" + CALL_ANCHOR
fix_source("crates/ui-egui/src/lib.rs", CALL_ANCHOR, CALL, "the bar drawn over the canvas")

if missing:
    print(f"  Could not patch the cutout bar for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the cutout bar for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 20. Quick Selection growing while the stroke is drawn (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)

# The whole stroke used to be cut once, at the release: nothing showed while drawing. Now each new
# stretch of the stroke is cut as it comes and added to the selection, in one history step. The next
# cut waits for twice what the last one took, so a heavy image updates less often instead of
# freezing the finger.

R = "crates/ui-egui/src/retouch_ui.rs"
FINISH_OLD = """/// Finish a stroke with a retouching tool. Returns false if `tool` isn't one.
pub fn finish_stroke(app: &mut PhotocraftApp, tool: Tool, points: &[[f64; 3]], mods: egui::Modifiers) -> bool {
"""
FINISH_NEW = """/// A Quick Selection stroke being cut while it is drawn.
struct QuickLive {
    first: [f64; 2],
    /// How many of the stroke's points have been cut.
    done: usize,
    /// The mode of the next cut: after New, the stroke adds to its own first cut.
    mode: &'static str,
    /// One history step for the whole stroke.
    key: String,
    /// Not before this: the time the last cut took, twice over, is left to the finger.
    next: std::time::Instant,
}

thread_local! {
    static QUICK_LIVE: std::cell::RefCell<Option<QuickLive>> = const { std::cell::RefCell::new(None) };
    static QUICK_STROKES: std::cell::Cell<u64> = const { std::cell::Cell::new(0) };
}

fn quick_cut(app: &mut PhotocraftApp, points: &[[f64; 3]], mode: &str, key: &str, enhance: bool) -> Result<Value, String> {
    let xy: Vec<[f64; 2]> = points.iter().map(|q| [q[0], q[1]]).collect();
    let size = app.session.tools.brush.size;
    let sample_all = app.ui.tool_options.sample_all.quick_selection;
    app.run("select.quick", json!({"points": xy, "size": size, "mode": mode, "enhanceEdge": enhance, "sampleAllLayers": sample_all, "coalesce": key}))
}

/// Called on every move of a stroke: cuts the stretch drawn since the last cut when it is long enough.
pub fn quick_live_step(app: &mut PhotocraftApp) {
    let Some(d) = app.drag.as_ref().filter(|d| d.tool == Tool::QuickSelection && d.points.len() >= 2) else { return };
    let first = [d.points[0][0], d.points[0][1]];
    let total = d.points.len();
    let alt = d.modifiers.alt;
    let state = QUICK_LIVE.with(|s| s.borrow_mut().take()).filter(|s| s.first == first && s.done <= total);
    let done = state.as_ref().map_or(0, |s| s.done);
    let tail: Vec<[f64; 3]> = d.points[done.saturating_sub(1)..].to_vec();
    let walked: f64 = tail.windows(2).map(|w| (w[1][0] - w[0][0]).hypot(w[1][1] - w[0][1])).sum();
    let size = f64::from(app.session.tools.brush.size);
    let began = std::time::Instant::now();
    if walked < (size * 0.25).max(4.0) || state.as_ref().is_some_and(|s| began < s.next) {
        QUICK_LIVE.with(|s| *s.borrow_mut() = state);
        return;
    }
    let (mode, key) = match state {
        Some(s) => (s.mode, s.key),
        None => {
            let mode = if alt {
                "subtract"
            } else {
                match app.ui.selection_mode {
                    0 => "new",
                    2 => "subtract",
                    _ => "add",
                }
            };
            let stroke = QUICK_STROKES.with(|c| {
                c.set(c.get() + 1);
                c.get()
            });
            (mode, format!("quick-live-{stroke}"))
        }
    };
    // Auto-Enhance is too slow for this; it runs once, at the release.
    let _ = quick_cut(app, &tail, mode, &key, false);
    if mode == "new" {
        app.ui.selection_mode = 1;
    }
    let later = if mode == "subtract" { "subtract" } else { "add" };
    let rest = (began.elapsed() * 2).max(std::time::Duration::from_millis(60));
    let next = std::time::Instant::now() + rest;
    QUICK_LIVE.with(|s| *s.borrow_mut() = Some(QuickLive { first, done: total, mode: later, key, next }));
}

/// The release of a stroke already being cut: only what is left is cut. False: no cut was made yet,
/// and the stroke is cut whole, as a tap is.
fn quick_live_finish(app: &mut PhotocraftApp, points: &[[f64; 3]]) -> bool {
    let Some(first) = points.first().map(|p| [p[0], p[1]]) else { return false };
    let Some(s) = QUICK_LIVE.with(|c| c.borrow_mut().take()).filter(|s| s.first == first && s.done <= points.len()) else { return false };
    let enhance = app.ui.tool_options.enhance_edge;
    let rest = &points[s.done.saturating_sub(1)..];
    if enhance {
        let _ = quick_cut(app, points, s.mode, &s.key, true);
    } else if rest.len() >= 2 {
        let _ = quick_cut(app, rest, s.mode, &s.key, false);
    }
    true
}

/// Finish a stroke with a retouching tool. Returns false if `tool` isn't one.
pub fn finish_stroke(app: &mut PhotocraftApp, tool: Tool, points: &[[f64; 3]], mods: egui::Modifiers) -> bool {
    if tool == Tool::QuickSelection && quick_live_finish(app, points) {
        return true;
    }
"""
fix_source(R, FINISH_OLD, FINISH_NEW, "the stroke cut as it is drawn")

MOVE_OLD = """        if moved || held {
            d.points.push([x, y, pressure as f64]);
            app.stylus.record_point();
        }
    }
}

/// Tool state machine. Shared by mouse input and automation.
"""
MOVE_NEW = """        if moved || held {
            d.points.push([x, y, pressure as f64]);
            app.stylus.record_point();
        }
    }
    crate::retouch_ui::quick_live_step(app);
}

/// Tool state machine. Shared by mouse input and automation.
"""
fix_source("crates/ui-egui/src/canvas.rs", MOVE_OLD, MOVE_NEW, "the cut called on each move")

if missing:
    print(f"  Could not patch the live Quick Selection for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the live Quick Selection for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 22. the Activity answering a request for a folder of fonts (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)

# Android gives a folder as a tree of documents, not a path. The Activity walks the tree and copies
# each font to a staging folder, then answers like a multiple Open. Stops the build if an anchor has
# moved: a menu entry that silently does nothing is worse than a failed build.

android_dir = src / "apps" / f"{app}-android"
activity = None
for candidate in sorted((android_dir / "java").rglob("*.java")):
    if "public void pcRequestOpen(long id, boolean multiple, String extensionsStr)" in candidate.read_text(errors="replace"):
        activity = candidate
        break
if activity is None:
    print(f"  Could not find the Activity for {app}", file=sys.stderr)
    sys.exit(1)
rel = str(activity.relative_to(src))

fix_source(rel, """    private static final int REQ_PERMISSIONS = 0x5045;
""", """    private static final int REQ_PERMISSIONS = 0x5045;
    private static final int REQ_FONT_TREE = 0x5047;
""", "the request code")

fix_source(rel, """    public void pcRequestOpen(long id, boolean multiple, String extensionsStr) {
        runOnUiThread(() -> {
            try {
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
""", """    public void pcRequestOpen(long id, boolean multiple, String extensionsStr) {
        runOnUiThread(() -> {
            try {
                if ("__fontfolder__".equals(extensionsStr)) {
                    pcFontTree(id);
                    return;
                }
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
""", "the folder request")

fix_source(rel, """        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_OPEN && requestCode != REQ_SAVE) return;
""", """        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_FONT_TREE) {
            pcFontTreeResult(resultCode, data);
            return;
        }
        if (requestCode != REQ_OPEN && requestCode != REQ_SAVE) return;
""", "the folder result")

ANCHOR = """    /** Commit an app-private staged file to its remembered SAF URI; used by Rust after every save. */
"""
fix_source(rel, ANCHOR, """    private void pcFontTree(long id) {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        requestIds.put(REQ_FONT_TREE, id);
        startActivityForResult(intent, REQ_FONT_TREE);
    }

    private void pcFontTreeResult(int resultCode, Intent data) {
        Long boxedId = requestIds.remove(REQ_FONT_TREE);
        if (boxedId == null) return;
        final long id = boxedId;
        final Uri tree = data == null ? null : data.getData();
        if (resultCode != RESULT_OK || tree == null) {
            enqueueCancel(id, "open");
            return;
        }
        io.execute(() -> {
            try {
                File stage = new File(getCacheDir(), "font-folder");
                pcDeleteTree(stage);
                JSONArray paths = new JSONArray();
                String root = android.provider.DocumentsContract.getTreeDocumentId(tree);
                pcCollectFonts(tree, root, stage, paths, 0);
                if (paths.length() == 0) {
                    enqueueError(id, "open", "Aucune police dans ce dossier.");
                    return;
                }
                JSONObject result = base(id, "open", "ok");
                result.put("paths", paths);
                results.offer(result.toString());
            } catch (Exception e) {
                enqueueError(id, "open", e.toString());
            }
        });
    }

    private void pcDeleteTree(File file) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) pcDeleteTree(child);
        }
        file.delete();
    }

    /** Every font file and zip under a folder of the document tree, sub-folders included. */
    private void pcCollectFonts(Uri tree, String parent, File stage, JSONArray paths, int depth) throws Exception {
        if (depth > 8 || paths.length() >= 5000) return;
        Uri children = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent);
        String[] columns = {
            android.provider.DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            android.provider.DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            android.provider.DocumentsContract.Document.COLUMN_MIME_TYPE
        };
        List<String[]> entries = new ArrayList<>();
        try (Cursor cursor = getContentResolver().query(children, columns, null, null, null)) {
            while (cursor != null && cursor.moveToNext()) {
                entries.add(new String[] { cursor.getString(0), cursor.getString(1), cursor.getString(2) });
            }
        }
        for (String[] entry : entries) {
            if (android.provider.DocumentsContract.Document.MIME_TYPE_DIR.equals(entry[2])) {
                pcCollectFonts(tree, entry[0], stage, paths, depth + 1);
                continue;
            }
            String name = entry[1];
            if (name == null || name.startsWith("._")) continue;
            String lower = name.toLowerCase(java.util.Locale.ROOT);
            if (!lower.endsWith(".ttf") && !lower.endsWith(".otf") && !lower.endsWith(".ttc") && !lower.endsWith(".otc") && !lower.endsWith(".zip")) continue;
            try {
                File slot = new File(stage, String.valueOf(paths.length()));
                if (!slot.mkdirs() && !slot.isDirectory()) continue;
                File out = new File(slot, safeName(name));
                copyUriToFile(android.provider.DocumentsContract.buildDocumentUriUsingTree(tree, entry[0]), out);
                paths.put(out.getAbsolutePath());
            } catch (Exception e) {
                Log.w(TAG, "Could not read the font " + name, e);
            }
        }
    }

""" + ANCHOR, "the walk of the folder")

if missing:
    print(f"  Could not patch the font folder for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the font folder for {app}: {', '.join(fixed)}")
PY
fi

# --------------------------- 23. a tablet held upright, and no empty settings pages (PhotoCraft)
if [[ "$APP" == "photocraft" ]]; then
python3 - "$SRC" "$APP" <<'PY'
from pathlib import Path
import sys

src, app = Path(sys.argv[1]), sys.argv[2]

fixed = []
missing = []


def fix_source(rel: str, old: str, new: str, tag: str) -> None:
    """Replace the single `old` in `rel` with `new`, unless it is already gone or already fixed."""
    path = src / rel
    try:
        text = path.read_text()
    except OSError:
        missing.append(f"{rel} (unreadable)")
        return
    if new in text:
        return
    if text.count(old) != 1:
        missing.append(f"{rel}: {tag}")
        return
    path.write_text(text.replace(old, new, 1))
    fixed.append(tag)

# Upright the screen is about 533 points across. Preferences asked for 170 + 340 and more: its body
# ran past the dialog and pushed the button row off the screen, while the close box, placed before
# the body, stayed on. Its columns now fit. Any other dialog wider than the screen scrolls sideways,
# upright only, so its buttons can always be reached. Lying flat, nothing changes.

D = "crates/ui-egui/src/dialogs.rs"
fix_source(D, """            ui.disable();
        }
        if let Some((size, min, max)) = resizable {
""", """            ui.disable();
        }
        let screen = ctx.content_rect();
        let upright = cfg!(target_os = "android") && screen.width() < screen.height();
        let contents = |ui: &mut egui::Ui| -> T {
            if upright {
                let room = ui.available_width().min(screen.width() - 72.0);
                egui::ScrollArea::horizontal().id_salt(id.with("upright")).max_width(room).auto_shrink([resizable.is_none(); 2]).show(ui, contents).inner
            } else {
                contents(ui)
            }
        };
        if let Some((size, min, max)) = resizable {
""", "dialogs scrolling sideways when upright")

P = "crates/ui-egui/src/prefs_ui.rs"
fix_source(P, """    ui.add_space(6.0);
    ui.horizontal_top(|ui| {
        // Section list.
        ui.vertical(|ui| {
            ui.set_width(170.0);
""", """    ui.add_space(6.0);
    let nav_w = if cfg!(target_os = "android") && ui.available_width() < 560.0 { 124.0 } else { 170.0 };
    ui.horizontal_top(|ui| {
        // Section list.
        ui.vertical(|ui| {
            ui.set_width(nav_w);
""", "the section list narrower")
fix_source(P, "let (rect, resp) = ui.allocate_exact_size(vec2(170.0, 22.0), Sense::click());",
           "let (rect, resp) = ui.allocate_exact_size(vec2(nav_w, 22.0), Sense::click());", "the section rows")
fix_source(P, "ui.set_width((ui.available_width() - 12.0).max(340.0));",
           "ui.set_width((ui.available_width() - 12.0).max(if nav_w < 170.0 { 180.0 } else { 340.0 }));", "the settings column")
fix_source(P, """egui::ScrollArea::vertical().max_height(content_height - 30.0).id_salt("prefs-scroll")""",
           """let scroll = if nav_w < 170.0 { egui::ScrollArea::both() } else { egui::ScrollArea::vertical() };
            scroll.max_height(content_height - 30.0).id_salt("prefs-scroll")""", "the settings scrolling both ways")

# A page saying only that its settings are not available: Scratch Disks, AI Integrations.
fix_source(P, """    SECTIONS
        .iter()
        .copied()
        .filter(|(id, title)| {
            query.is_empty()
""", """    SECTIONS
        .iter()
        .copied()
        .filter(|(id, _)| !cfg!(target_os = "android") || has_visible_fields(values, id))
        .filter(|(id, title)| {
            query.is_empty()
""", "no empty settings pages")
fix_source("crates/ui-egui/src/menus.rs", """    let mut items: Vec<MenuItem> = crate::menu_catalog::CATALOG
        .iter()
        .map(|&(path, label, sc, id)| MenuItem {
""", """    let mut items: Vec<MenuItem> = crate::menu_catalog::CATALOG
        .iter()
        .filter(|(_, _, _, id)| !(cfg!(target_os = "android") && matches!(*id, "edit.preferences.scratchDisks" | "edit.preferences.integrations")))
        .map(|&(path, label, sc, id)| MenuItem {
""", "no menu lines to empty pages")

# The last menu title was cut. Upright the mark goes, and the titles sit closer.
fix_source("crates/ui-egui/src/panels.rs", """                if !system {
                    let side = if t.pro { 18.0 } else { 20.0 };
""", """                let upright = cfg!(target_os = "android") && full.width() < ui.ctx().content_rect().height();
                if !system && !upright {
                    let side = if t.pro { 18.0 } else { 20.0 };
""", "no mark in the bar when upright")
fix_source("crates/ui-egui/src/menus.rs", """            ui.spacing_mut().button_padding = egui::vec2(6.0, 3.0);
            nav.bar_bottom = Some(ui.max_rect().bottom());
""", """            let screen = ui.ctx().content_rect();
            let side = if cfg!(target_os = "android") && screen.width() < screen.height() { 3.0 } else { 6.0 };
            ui.spacing_mut().button_padding = egui::vec2(side, 3.0);
            nav.bar_bottom = Some(ui.max_rect().bottom());
""", "menu titles closer when upright")

if missing:
    print(f"  Could not patch the upright layout for {app}: {'; '.join(missing)}", file=sys.stderr)
    sys.exit(1)
if fixed:
    print(f"  Patched the upright layout for {app}: {', '.join(fixed)}")
PY
fi
