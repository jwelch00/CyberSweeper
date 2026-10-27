# Credits

Every third-party asset and tool that ships with CyberSweeper or is used to build it.

## Fonts (bundled in game/assets/fonts with their licenses)

| Font | Use | Copyright | License |
| --- | --- | --- | --- |
| Chakra Petch | UI words | Copyright 2018 The Chakra Petch Project Authors (https://github.com/m4rc1e/Chakra-Petch) | SIL Open Font License 1.1, `design/fonts/OFL-ChakraPetch.txt` |
| Martian Mono | Every digit | Copyright 2020 The Martian Mono Project Authors (https://github.com/evilmartians/mono) | SIL Open Font License 1.1, `design/fonts/OFL-MartianMono.txt` |
| Noto Sans JP Bold (subset) | The few decorative Japanese words | © 2014-2021 Adobe (http://www.adobe.com/). A glyph subset of Noto Sans CJK JP Bold | SIL Open Font License 1.1, `design/fonts/OFL-NotoSansCJK.txt` |

The download page (`site/index.html`, built into `dist/index.html`) embeds the same Chakra Petch and Martian Mono WOFF2 files from `design/fonts/`, under the same licenses, and its footer names them and their license.

## Engine

| Software | Version | License |
| --- | --- | --- |
| Godot Engine | 4.7.2-stable (official build ed1daf0bf) | MIT, https://godotengine.org/license |

Godot's own third-party components are listed in its `COPYRIGHT.txt` and at https://godotengine.org/license. Every download carries Godot's license and those notices in `LICENSES/Godot.txt`, written from the engine itself by `game/dev/licenses.gd`, next to the three font licenses.

## Build tools

| Software | Use | License |
| --- | --- | --- |
| Godot export templates 4.7.2-stable | the Windows, macOS and Linux runtimes the builds are made from (installed by `tools/build.py --install-templates`, checked against Godot's published SHA-512) | MIT, as Godot |

## Audio and art

- **Sound effects** (`game/assets/sfx/*.wav`): synthesized from scratch by `tools/make_sfx.py`, original to this project.
- **Glyphs** (flag, mine): drawn at runtime from the shapes in `design/shared/board.js`, original to this project.
- **Icon** (`design/icon/`, copied into `game/assets/icon/`): original to this project.
- Everything else (design, palettes) is original work for this project.

No third-party audio or art is used. Any CC0 asset added later goes here with its source and license.
