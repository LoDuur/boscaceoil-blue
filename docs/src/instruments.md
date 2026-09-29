---
title: Instruments
---

# Instruments

The second most important tool after the arrangement view is the `INSTRUMENT` view.

In _Bosca Ceoil Blue_ you can find hundreds of instrument presets, but instead of using them directly you first must create a song instrument out of one of them. This allows you to quickly find the instrument that you need when editing patterns, and to use the same preset multiple times with different tuning configurations.

![](/images/overview-instrument-view.png)


## Instrument management

The instrument view is split into two parts: the instrument dock and the instrument configuration panel. Similarly to how you can create and delete patterns from the dock in the [arrangement view](/arrangements.html), you can create and delete instruments from the instrument dock. Pressing `ADD NEW INSTRUMENT` adds a random instrument to the list, while dragging and dropping one of the existing instruments onto the `DELETE?` label deletes it.

![](/images/instruments-dock-delete.png)

You can only create up to 16 unique instruments.

The newly added instrument is a random melodic one (random picks never include drumkits or percussion), so you can discover something fresh every time! But you have full control over what you will use in the end. To the right of the dock is the configuration panel, where you can select a specific instrument, or roll the dice again and find another random one.

Instruments are grouped into several categories, with the MIDI set being split even further due to its sheer size. The complete list of instrument categories is as follows:

- MIDI
- Chiptune
- Bass
- Brass
- Bell
- Guitar
- Lead
- Piano
- Special
- Strings
- Wind
- World
- Drumkit

![](/images/instruments-categories.png)

And the following are sub-categories of MIDI instruments:

- Piano
- Bells
- Organ
- Guitar
- Bass
- Strings
- Ensemble
- Brass
- Reed
- Pipe
- Lead
- Pads
- Synth
- World
- Drums
- Effects

Instruments are loosely color-coded, which not only makes _Bosca Ceoil BLue_ look fun and appealing, but also helps you to distinguish them. The instrument used also defines the color of the pattern, as you might've noticed already.

Once created, the instrument can be selected for any pattern using the list in the bottom-left corner of the [pattern editor](/notes_and_patterns.html).

![](/images/instruments-pattern-picker.png)


## Tuning

One way to further define the voice of the instrument that you've selected is to tweak and tune it. Each instrument allows you to adjust two settings: the low-pass filter and the volume. The volume should be self-explanatory, and it gives you means to make the instrument quieter.

The low-pass filter may require a bit of an explanation. Controlled with a pad rather than a 1-dimensional slider, this filter has two parameters, resonance and cutoff. Moving the pad head left and right adjusts the cutoff point, while moving it up and down changes the resonance.

![](/images/instruments-tuning-pads.png)

The low-pass filter, as the name suggests, allows audio frequencies below the cutoff threshold to pass freely, while damping those that go beyond that limit. In other words, the further left you move the pad head, the less high-frequency sounds will be allowed by the instrument.

Resonance, in turn, allows to additionally amplify the sound around the cutoff point. This makes the sounds close to the cutoff frequency to be more pronounced, peaking. A use case for this would heavily depend on each particular instrument, so feel free to experiment!

<p class="warning">
Some sounds produced this way may be unpleasant, especially at extreme values. Please take care and try lowering the volume first, or avoid using headphones until you understand what you can expect here.
</p>


## Custom instruments

Besides presets, you can build your own oscillator-based instruments. Pick the `CUSTOM` category in the type drop-down for the instrument you are editing. The preset list is then replaced by a sound panel:

- **Oscillator**: `SINGLE` or `DUAL` mode and a waveform for each oscillator. With two oscillators you can also set how they are linked, their balance, and a detune of up to one semitone either way.
- **Envelope**: attack, decay, sustain level, sustain decay and release (higher rates are faster), plus an overall attenuation. A small curve sketches the shape.
- **Vibrato**: a constant pitch wobble of up to one semitone.
- **Identity**: a name (up to 24 characters) and a color.

The low-pass filter and volume pads work the same as for presets. While the song is stopped, every change plays a short note so you can hear it. Every change can be undone, and dragging a slider counts as a single change. The `RANDOM` button rolls new sound settings for a custom instrument instead of switching it to a preset.

Custom instruments are stored inside the song file, so a song sounds the same on any machine. To reuse one in other songs, press `SAVE TO LIBRARY`. Saved instruments appear under the `CUSTOM` category's list, next to the other custom instruments in the song; picking one copies it into the edited instrument.

<p class="warning">
Tremolo and delayed vibrato are not available yet. Custom instruments count toward the limit of 16 instruments per song.
</p>


## Adding audio effects

Continue on to [Effects](/effects.html), and you will learn about the final piece of the puzzle — global effects and filters.
