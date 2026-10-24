# ArchPup

A modern continuation of ArchPup. Bringing together the lightning speed, frugal persistence, and lightweight footprint of Puppy Linux with the package ecosystem of Arch Linux.

## Highlights

- **Base:** Arch / Artix compatible base without systemd bloat.
- **Package Manager:** Native `pacman` support.
- **Boot Design:** Puppy-style frugal install (loads into RAM, layered SquashFS, overlay persistence).
- **Desktop:** Classic ultra-lightweight X11 desktop (JWM + ROX-Filer).
- **Target Architectures:** `x86_64` (64-bit) with planned `i686` (32-bit legacy support).

## Versioning

- **Current Release:** 26 (v26.10)
- **Status:** Active development & CI testing

## Automated Cloud Builds

Builds run directly in the cloud on GitHub Actions with zero local setup:

1. Go to the **Actions** tab in this repository.
2. Select **Build ArchPup ISO**.
3. Click **Run workflow**.
4. Grab the generated ISO from the **Artifacts** section at the bottom of the completed run.

## Credits

- Puppy Linux community & tools
- Arch Linux & Artix Linux packaging ecosystems
