---
title: Exporting
---

# Exporting

What's the point of writing music, if you cannot share it? _Bosca Ceoil Blue_ renders your composition into an uncompressed waveform audio file (`.wav`), universally supported by media players, music and video production software, and game engines. What you hear is what you get.


## Exporting a song

Press `EXPORT WAV...` in the `FILE` view, or use <kbd>Ctrl/Cmd + E</kbd> anywhere in the app. A save dialog opens right away; pick a location and a name for the file. If you leave out the `.wav` extension, it is added for you.

The entire arrangement is always exported, from the first bar to the last bar containing a pattern. Your timeline loop selection is left untouched. If the arrangement is empty, there is nothing to render, and the app tells you so instead of opening the dialog.

While the song is being rendered, editing is locked. This takes about as long as playing the song through.

<p class="warning">
Exporting is not a replacement for saving your song. Keep the <code>.ceol</code> file to continue working on it later.
</p>
