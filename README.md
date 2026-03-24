# Touchpaddy 2

This is a second implementation of customizable touchpad gestures for KDE Plasma 6.x using `kdotool` and
parsing `libinput debug-events` gestures.

This is not very efficient, because using `kdotool` and having to shell out every frame is eating a bunch of CPU... so I want to switch over to using a DBus API like what `kdotool` does under the hood. Unfortunately KDE does *not* expose a sane API so the only way an application can move windows is literally by generating a javascript kwin script at runtime, saving it to a file somewhere, sending it over the bus, load/execute/stop, etc. which sucks.

## Install/Usage

You need a recent version of the [seal runtime](https://github.com/seal-runtime/seal) to run Luau code.

Runtime dependencies (which you can fetch from your package manager) include:

- yad
- screen (optional)
- kdotool
- ydotool
- libinput and libinput-tools

To run this program, use screen or just run `seal r` in this repo after cloning it.

Gestures are hardcoded and can be customized by editing `./src/main.luau`. 

I probably won't be adding a better way to do this since KDE is finally gonna officially add customizable touchpad gestures SOON TM.
