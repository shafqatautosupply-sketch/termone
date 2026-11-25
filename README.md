# Term6 - a terminal for jailbroken iOS 6

* Real pty (no SSH, no localhost round trip)
* libvterm (xterm-256color, alt screen, UTF-8, scrollback, resize)
* Key bar = a standard black UIToolbar with bordered bar buttons (Ctrl / Alt light up blue). Scrolling = a UIScrollView
  overlay (native momentum, snaps to whole lines, scroll indicator). The grid itself is drawn with Core Graphics.
* iOS 6 black-toolbar key bar: Esc, Ctrl, Alt (sticky), Tab, | ~ / -, and the **gear key on the right**
  - tap the gear = Settings
  - press and hold the gear = pop-up box with **session tabs** (1, 2, ... / + adds / x closes)
    and your **saved commands** (tap one to type it into the terminal)
  - drag a finger across the bar to move the cursor; the first movement picks left/right or up/down
    and the other axis is ignored until you lift your finger
* **Tap the terminal** to slide the keyboard away / back (native animation). The key bar is part of the app view,
  so it stays visible, and slides together with the keyboard.
* Long press a word = select it. Drag the two blue handles to extend; Copy / Paste / Select All menu.
  (Custom-drawn iOS-style selection, not UIKit's loupe.)
* Backspace auto-repeats while held (0.45 s delay, then speeds up).
* Drag = scrollback with momentum (arrow keys inside vim / less), pinch = font size.
* Settings: Persistent Sessions on/off, run shell as root (works with or without the daemon), shell path,
  **text encoding** (UTF-8, Latin 1/2, Windows-1251/1252, KOI8-R, Mac Roman, Shift JIS, EUC-JP, GB18030, Big5, EUC-KR, ASCII), Saved Commands (add / edit / delete /
  reorder), "Press Return After Inserting", font size, 4 themes, New Session.
* Persistent Sessions = `term6d`, a root LaunchDaemon that owns the shells. Close or kill Term6, come back
  later, and every tab is re-attached with its recent output replayed. Off = shells live inside the app.

## Build (on the phone or from a PC)

    export THEOS=/var/theos        # wherever yours lives
    cd Term6
    make package install

If Theos rejects `TARGET = iphone:clang:6.1:5.0`, change it in both Makefiles to `iphone:6.1:5.0`.
If the linker cannot find `forkpty`, add `-lutil` to `Term6_LDFLAGS` and `term6d_LDFLAGS`.
The package depends on `bash` (Cydia). The postinst loads the daemon; check with:

    launchctl list | grep term6

## Layout

    Makefile, control, Resources/    app bundle (Theos application)
    *.m / *.h                        app: session, view, key bar, settings
    vterm/                           libvterm 0.3.3 (MIT), vendored
    term6d/                          the root session daemon (Theos tool)
    term6root/                       setuid-root launcher: root shell when the daemon is off
    common/                          wire protocol + pty spawn helper shared by both
    layout/                          LaunchDaemon plist + DEBIAN postinst/prerm

## Security note

`term6root` (installed setuid by the postinst) lets any process running as `mobile` start a root shell,
like `su` without a password. `term6d` listens on `/var/tmp/term6d.sock` (mode 0600, owner mobile) and only accepts
connections from uid mobile or root. With "Run Shell as Root" on, any process running as mobile
can get a root shell through it - fine on a personal phone, but know it is there.
