# About master_me
maste_me is an automatic dynamics processor originally developed for the ‘quarantine sessions' - a distributed electroacoustic network improvisation hosted weekly by Stanford University’s [CCRMA](https://ccrma.stanford.edu/) Institute in creative response to the challenges of the Covid-19 pandemic. Meanwhile, it has been used and adapted for various other streaming events.

master_me is meant as an automatic helper tool for live performances and live recordings. Applying final touches to the audio stream, it prevents clipping and distortion and makes the sound more balanced overall. master_me is NOT meant to act as a robot that automatically masters your music (which hopefully deserves more attention!).

The project is coded in [Faust](https://faust.grame.fr/), a functional programming language for sound synthesis and audio processing, which is developed at the [GRAME Research Lab](https://www.grame.fr/recherche) in Lyon, France.

master_me is a free and open-source software (FOSS, GNU General Public License) and can be compiled for various platforms and operating systems.

![master_me screenshot](https://github.com/trummerschlunk/master_me/blob/master/master_me_gui.png)
The Faust DSP code can directly be tested in the [Faust Web IDE](https://faustide.grame.fr/?code=https://raw.githubusercontent.com/trummerschlunk/master_me/master/master_me_gui.dsp), and possibly be exported to other targets.

# Signal flow
![master_me screenshot](https://github.com/trummerschlunk/master_me/blob/master/master_me_signal_flow.png)

In order to nudge sources to more dynamic headroom, an initial volume gain is applied.

DC-filtering is applied.

The ‘leveler’ section is the heart of master_me, featuring a slow, RMS-based leveling algorithm with gated loudness detection. The resulting level will smoothly follow the incoming signal, but hold if silence (below an adjustable threshold) is detected. The outgoing level will be just right to hit the mastering chain.

The ‘multiband-mid/side-compressor’ is a replica from Klaus Scheuermann's mastering studio. The signal is split into three frequency bands (with crossovers at 250Hz and 2500Hz). Each band is converted from stereo to mid/side. All resulting channels hit a 30%-linked 6-channel compressor. Combined and decoded back to stereo, this produces a smoothly compressed and decently widened sound image.

The ‘look-ahead limiter’ takes care of extreme peaks.

The ‘clipper’ is actually a brickwall-limiter.

# Installation
Various targets can easily be compiled. Click [here](https://faustide.grame.fr/?code=https://raw.githubusercontent.com/trummerschlunk/master_me/master/master_me_gui.dsp) and export your desired format/plattform.

# About the developer
master_me was created by Berlin-based Mastering Engineer and Sound Experimentalist [Klaus Scheuermann](https://4ohm.de). Over the past 20 years, he has mastered countless albums and worked with artists in audiophile jazz as well as sound fetishists from the electronic music scene.

His collaborations include Philip Caterine, Lars Danielsson, Benoît Delbecq, Klaus Doldinger, Wolfgang Haffner, Kalipo, Rolf & Joachim Kühn, Scott Matthew, Nils Landgren, Christian Lillinger, Jan Lundgren, Nguyên Lê, Leszek Mozdzer,  Emile Parisien & Vincent Peirani, Chris Schwarzwälder,  Michael Wollny, and many more.

# Contact information
[Email](mailto:info@4ohm.de) - [Website](https://4ohm.de) - [Mastodon](https://chaos.social/@trummerschlunk)

