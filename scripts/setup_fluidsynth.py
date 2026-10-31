#!/usr/bin/env python3
"""
LibrePianoRoll - Automated FluidSynth Dependency Setup Script
Downloads, installs, and configures FluidSynth libraries for development.
Compatible with Windows, GNU+Linux, and MacOS.
"""

import os
import sys
import argparse
import urllib.request
import zipfile
import shutil
import subprocess

DEFAULT_VERSION = "2.6.1"
GITHUB_REPO = "FluidSynth/fluidsynth"

def log(msg: str) -> None:
    print(f"[FluidSynth Setup] {msg}")

def setup_windows(version: str, project_root: str) -> None:
    build_dir = os.path.join(project_root, "build", "fluidsynth")
    os.makedirs(build_dir, exist_ok=True)

    folder_name = f"fluidsynth-v{version}-win10-x64-cpp11"
    install_target = os.path.join(build_dir, folder_name)

    if os.path.exists(os.path.join(install_target, "bin", "libfluidsynth-3.dll")):
        log(f"FluidSynth v{version} already present in {install_target}")
    else:
        zip_url = f"https://github.com/{GITHUB_REPO}/releases/download/v{version}/{folder_name}.zip"
        zip_path = os.path.join(build_dir, f"{folder_name}.zip")

        log(f"Downloading {zip_url}...")
        try:
            urllib.request.urlretrieve(zip_url, zip_path)
            log(f"Extracting {zip_path}...")
            with zipfile.ZipFile(zip_path, "r") as z:
                z.extractall(build_dir)
        except Exception as e:
            log(f"Download failed: {e}")
            sys.exit(1)

    bin_src = os.path.join(install_target, "bin")
    bin_dst = os.path.join(project_root, "addons", "fluidsynth", "bin")
    os.makedirs(bin_dst, exist_ok=True)

    required_dlls = ["libfluidsynth-3.dll", "sndfile.dll", "SDL3.dll"]
    for dll in required_dlls:
        src = os.path.join(bin_src, dll)
        if os.path.exists(src):
            shutil.copy2(src, bin_dst)
            shutil.copy2(src, project_root)
            log(f"Copied {dll} -> addons/fluidsynth/bin/ and root")
        else:
            log(f"Warning: {dll} not found in {bin_src}")

    # Copy license
    license_src = os.path.join(install_target, "LICENSE")
    if os.path.exists(license_src):
        os.makedirs(os.path.join(project_root, "addons", "fluidsynth", "license"), exist_ok=True)
        shutil.copy2(license_src, os.path.join(project_root, "addons", "fluidsynth", "license", "FLUIDSYNTH_LGPL.txt"))
        log("Copied FluidSynth LGPL license to addons/fluidsynth/license/")

    log("Windows setup complete!")

def setup_linux() -> None:
    log("On GNU+Linux, install development packages via your distribution:")
    log("  Debian/Ubuntu: sudo apt install -y libfluidsynth-dev libsndfile1-dev pkg-config cmake")
    log("  Fedora:        sudo dnf install -y fluidsynth-devel libsndfile-devel pkgconf-pkg-config cmake")
    log("  Arch Linux:    sudo pacman -S fluidsynth libsndfile pkgconf cmake")

def setup_macos() -> None:
    log("On MacOS, install packages via Homebrew:")
    log("  brew install fluidsynth libsndfile pkg-config cmake")

def main() -> None:
    parser = argparse.ArgumentParser(description="Setup FluidSynth libraries for LibrePianoRoll")
    parser.add_argument("--version", default=DEFAULT_VERSION, help=f"FluidSynth version to fetch (default: {DEFAULT_VERSION})")
    args = parser.parse_args()

    project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

    if sys.platform.startswith("win"):
        setup_windows(args.version, project_root)
    elif sys.platform.startswith("darwin"):
        setup_macos()
    else:
        setup_linux()

if __name__ == "__main__":
    main()
