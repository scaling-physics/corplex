# Demo clips

Scripts that drive the real app on an Android emulator and turn the
screenshots into the GIFs in `docs/demo/`. Rough, but repeatable.

1. Boot an emulator (1080×2400), install a release build, and put
   "Attention Is All You Need.pdf" in its Download folder.
2. `python3 flow_capture.py` (or any `flow_*.py`) records frames into a
   folder of the same name.
3. `python3 gif.py capture ../../docs/demo/capture.gif` builds the GIF.

Coordinates are for that screen size. `d.py` has the helpers (tap, type,
stylus strokes) and `setup_paper()` for the flows that need a paper.
