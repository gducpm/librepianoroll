# LibrePianoRoll  
![Test](https://github.com/gducpm/librepianoroll/actions/workflows/test.yml/badge.svg) ![Build](https://github.com/gducpm/librepianoroll/actions/workflows/build.yml/badge.svg) ![Platform](https://img.shields.io/badge/platform-GNU+Linux%20%7C%20Darwin%20%7C%20Windows-brightgreen) ![License: AGPLv3](https://img.shields.io/badge/License-AGPLv3-blue.svg) ![Repo Size](https://img.shields.io/github/repo-size/gducpm/librepianoroll)  
A free MIDI-Piano visualizer - free as in YOUR freedom.  

![LibrePianoRoll Program Screenshot](readme_images/main.png)

## General Info  
### LibrePianoRoll is part of the **GLP (GDucpm Libre Programs) Project.**  
**Platforms**: GNU+Linux, Windows, Darwin (or MacOS)  
**Version**: 1.0.0-beta  
**Author**: GDucpm  
**Contributors**: none for the time being  
**Engine**: Godot 4.x  
**License**: GNU Affero General Public License v3.0 (AGPLv3)  
**Human Intervention**: Yes  

## Quickstart  
1. Head to the **Releases** section on the right side of this repository.  
2. Download the package for your platform:  
   - **Windows**: `LibrePianoRoll-Setup-x64.exe` (installer with desktop shortcuts) or `LibrePianoRoll-Windows-Portable.zip` (standalone portable archive).  
   - **GNU+Linux**: `LibrePianoRoll-GNU+Linux-x86_64.tar.gz` (standalone portable archive).  
   - **Darwin / macOS**: `LibrePianoRoll-MacOS-Universal.zip` (universal binary for Apple Silicon & Intel).  
3. Extract (or run the installer) and launch **LibrePianoRoll**!  
   *(A high-quality General MIDI SoundFont `default.sf3` is included out of the box).*  

## Running / Editing from Source  
1. Clone this repository:  
   ```bash
   git clone https://github.com/gducpm/librepianoroll.git
   cd librepianoroll
   ```
2. Download and install [Godot Engine 4.x](https://godotengine.org/download/) (v4.3 or later).  
3. Compile the native **FluidSynth GDExtension**:  
   - **Windows (MSVC)**:  
     ```cmd
     python scripts/setup_fluidsynth.py
     scripts\build_fluidsynth_extension.bat
     ```  
     *(Or via CMake: `cmake -B build -G "Visual Studio 17 2022" -A x64 && cmake --build build --config Release`)*  
   - **GNU+Linux (Debian / Ubuntu / Arch / Fedora)**:  
     ```bash
     # Install dependencies (example for Debian/Ubuntu):
     sudo apt install -y libfluidsynth-dev libsndfile1-dev cmake pkg-config
     cmake -B build -DCMAKE_BUILD_TYPE=Release
     cmake --build build --config Release
     ```  
   - **Darwin / macOS**:  
     ```bash
     brew install fluidsynth libsndfile cmake pkg-config
     cmake -B build -DCMAKE_BUILD_TYPE=Release
     cmake --build build --config Release
     ```  
   *The compiled library will automatically be placed in `addons/fluidsynth/bin/`.*  
4. Open the Godot Project Manager, click **Import**, select `project.godot`, and click **Edit**.  
5. Press **F5** (or click the Play icon) to run the visualizer!  

## Exporting / Building Standalone Binaries  
To build standalone release packages locally:  
1. Make sure you have compiled the native extension in `addons/fluidsynth/bin/` as shown above.  
2. Open the project in Godot 4.x and open **Project** > **Export...** (export presets for Windows Desktop, GNU+Linux, and macOS are pre-configured in `export_presets.cfg`).  
3. Select your platform and click **Export Project**.  
4. Ensure `default.sf3`, `default.mid`, and the `addons/fluidsynth/bin/` folder are placed alongside the exported executable.  
5. *(Optional on Windows)*: Compile the NSIS installer by running:  
   ```cmd
   makensis /DVERSION=1.0.0-beta scripts/installer.nsi
   ```  

## Attributions  
- **MuseScore** for the MS Basic SoundFont (MIT)  
- **The Mutopia Project** for Ludwig van Beethoven's *Piano Sonata No. 14 in C♯ minor ("Moonlight")*, Op. 27 No. 2, 3rd Movement (*Presto agitato*) demo MIDI (`default.mid`), typeset by Stewart Holmes from the 1908 Berners/Winterberger edition (Public Domain / CC-BY-SA)  

## Warranty  
This program is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.  

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public License for more details.  

You should have received a copy of the GNU Affero General Public License along with this program.  If not, see <https://www.gnu.org/licenses/>.  
