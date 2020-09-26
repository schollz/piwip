## piwip

a sampler that works in realtime.

![screenshot](piwip.gif)

my goal here was to make a sampler that plays back samples of your instrument while you are playing. that way, i can have a "autotune" for my bad trumpet playing (keeping monitor mode off). what this ended up being is a customizable sampler that should be able to do that, and more.

future directions:

- fix bugs

### Requirements

- midi input
- audio input
- norns

### Documentation

- K2 arms recording
- K3 forces recording
- K1+K2 toggles monitor
- E1 activates presets
- E2/E3 trims sample


**quick start:** plug in midi and audio source. turn E1 to "sampler". press K2 to arm. then play audio. now you can play it back on your midi source.

there are a number of customizable parameters in the global m enu. currently there are two presets (E1 toggles):

- "sampler": generic sampler. record once and then midi notes are shifted by a constant amount (relative to middle c).
- "follower": sample in realtime. playing midi during recording will try to play notes near the leading edge, using a realtime pitch-detector to correctly pitch shift.

i'm sure there are other interesting combos.



## demo 


## my other norns scripts

- [barcode](https://github.com/schollz/barcode): replays a buffer six times, at different levels & pans & rates & positions, modulated by lfos on every parameter.
- [blndr](https://github.com/schollz/blndr): a quantized delay with time morphing
- [clcks](https://github.com/schollz/clcks): a tempo-locked repeater
- [oooooo](https://github.com/schollz/oooooo): digital tape loops

## license 

mit 


