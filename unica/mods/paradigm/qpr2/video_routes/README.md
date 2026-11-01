# Session-specific audio output in Samsung Video Player

Connects a new Audio output menu action to the native player's actual
MediaSession and MediaRouter2.showSystemOutputSwitcher(MediaSession.Token).
The token overload is present in both the reviewed QPR2 framework and Samsung's
One UI 9 framework. It prevents selection of an unrelated inferred media session.
The QPR2 media dialog's MediaSessionRepository and output switcher are the local
reference; the public routing API is the bridge for this Samsung Activity.

The menu is hidden outside Samsung's normal playback mode (including Knox/DLNA)
and disabled without an active native session. The existing lock/help guards
remain before menu preparation. Releasing a session or refusing the dialog is
handled without switching to the tokenless overload or changing audio settings.
The system dialog performs route discovery and selection; this patch adds no
route scanner, volume changes, service or media session of its own.

The glass patch attaches to the successful native blur utility and clears its
material before native blur reset. The common geometry and accessibility gates
remain in place. The playback surface, DRM and decoder are unchanged.

API reference: https://developer.android.com/reference/android/media/MediaRouter2#showSystemOutputSwitcher(android.media.session.MediaSession.Token)
