# Aseprite Atari ST/STE Palette Editor Plugin

An [Aseprite](https://www.aseprite.org/) plugin for editing sprite palettes using the Atari ST's 3-bit-per-channel (or Atari STE's 4-bit-per-channel) RGB color model.

| | |
|---|---|
| **Plugin** | Atari ST/STE Palette Editor |
| **Version** | Beta 2 |
| **Author** | [sandord](https://github.com/sandord) |
| **License** | MIT |
| **AI Assisted** | Yes — code generated with AI help |

## Why?

Because editing Atari ST(E) palettes in Aseprite can be cumbersome without a dedicated tool. Because Aseprite uses 8 bits per channel (0–255) while the Atari ST's palette hardware uses only 3 bits per channel (0–7), it can be hard to know if the ST can display a given color.

## Screenshot

![Atari ST Palette Editor screenshot](screenshot.png)

## Installation

1. Open Aseprite
2. Go to **File → Scripts → Open Script Folder**
3. Open a second file explorer and browse to and select the `atari-st-palette` folder in this repository
4. Copy the `atari-st-palette` folder into the script folder you opened in step 2

## Usage

1. Open any sprite in Aseprite
2. Run the plugin from **File → Scripts → Atari ST Palette Editor**
3. **To pick a color**: click its corresponding button.
4. **To fine-tune**: use the R, G, B sliders (each 0–7) to adjust the selected slot with Atari ST/STE precision.
5. **Skip first**: check "Skip palette index 0" to shift all slots up by one, leaving palette index 0 untouched. This can be useful for assets that use index 0 for transparency.
6. **Stretch mode**: check "Stretch 3-bit colors to full 8-bit range" for maximum dynamic range (0–255); uncheck for a simple bit-shift mapping (0–224) that matches the raw hardware output. Use this feature to ensure that the colors are displayed with proper brightness in Aseprite.
7. **STE mode**: enables the extended color range of the Atari STE. This allows for 16 levels per channel (0–15) instead of 8.

## Requirements

- **Aseprite v1.3** or later

## License

MIT — see the [package.json](atari-st-palette/package.json) file for details.
