# QPR2 Bluetooth microphone routing for Samsung recorders

One UI 9-only ordinary APK patches. Settings > Sounds and vibration exposes an
off-by-default, per-user switch. The original Samsung screen-recording consent,
MediaProjection path, audio source modes, permissions and save flow remain.

SystemUI ScreenMediaRecorder and SmartCapture BaseAudioRecorder use the actual
QPR2 preferred-capture-device idea, adapted for Samsung's AudioRecord and
MediaRecorder. Only a matched SCO/BLE headset input is requested. Preferred or
active selection wins; with multiple unmatched headsets the normal microphone
remains. A privileged preset read may be denied without requiring new rights.
Internal-only capture and voice-call mode are not rerouted.

The exact Samsung public AudioManager route API uses a static legacy token,
even on a new AudioManager object. Each recording instead owns a fresh Binder
token sent to the same real IAudioService with the real context attribution.
The normal service permission checks still apply. Start failures,
end/stop and SmartCapture pause release only that owner's communication route;
resume reacquires. A rejected release or RemoteException retains the owner for retry and blocks a
new acquire. Accepted Binder requests are not hardware completion. This is
policy-level lifecycle handling, not proof of Bluetooth
hardware completion, SCO timing or a native asynchronous buffer lease.

Helpers are app-owned under io.mesalabs.unica.recording. No framework stub or
signature/permission bypass is packaged. Compile against the exact Samsung
framework; the three APKs must use the same appropriate ROM platform key.

## Reviewed input refreshes

Before applying any recording patch, the root decodes all three apps and checks
the complete six-path `sources.json` contract. Unknown or missing inputs,
duplicate classes/helpers, incomplete contracts and patch sets fail closed.
All five patch files must be syntactically valid, including the unselected
version-identification alternative.
Every selected patch must pass a read-only `git apply --check` before Settings
or either recorder is modified. Explicit failures also propagate when the root
is sourced conditionally. SDK36 does not read this contract or run these patches.

The original SystemUI `qb/115226349` and current `qb/116136971` recorder, internal
audio recorder and audio-source enum differ only in their `.source` debug build
markers. Their full fields/methods are identical, and the current classes match
a fresh decode of the actual donor APK (SHA-256
`3ded9c27ad2aa1f982dde78cea254d82fc0af0a6a99166545c9cc34c18294704`).
The SystemUI patch no longer embeds that volatile marker in its field hunk;
the guard still admits only the exact reviewed whole-file hashes, not arbitrary
markers or normalized code. No routing/lifecycle instructions were changed.

SmartCapture 6.2.44.32 (APK SHA-256
`22e02765030fe995712f4edb7a5e93d5895677e199f011507184263412cc467c`)
retains the exact reviewed `BaseAudioRecorder` and `MP4Recorder` code with the
original decoder's `--no-debug-info` flags. Its separate ordinary identification
patch advances `624432000` to `624432001` and retains `6.2.44.32` in the version
name. The original 6.2.44.29 identification patch remains unchanged and supported;
exactly one version patch must match. Unknown versions are not downgraded or
relabeled as another release. The Settings XML is unchanged from the baseline.

Comparisons, fresh decoding and private original-helper replays are retained in
`out/recording-contracts-20261029/`. REA archive evidence for the SystemUI APK is
`ev_1ab283297bc62934dfc3e961b7f439f01b05c92bc79ad3cb0123373b064af23d`.
REA's Android/JADX provider was unavailable; the class comparisons use the real
installed smali/apktool decoder, not claimed REA decompilation. Archive inventory
does not establish runtime behavior or signer validity. These checks do not
claim a complete ROM build, ART verification or Bluetooth/device qualification.
