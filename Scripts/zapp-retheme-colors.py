#!/usr/bin/env python3
"""
Retint the ZDesign primitive ramps in Colors.xcassets to the Zapp palette.

Why this works, and why it is only ~160 small JSON edits instead of 254 Swift edits:

DesignSystem.swift resolves every semantic token through
    Design.col(<lightPrimitive>, <darkPrimitive>, colorScheme)
where the primitives are `Asset.Colors.ZDesign.*` colorsets. The *pairing* is
already semantically correct (bgPrimary = col(Base.bone, Base.midnight) really
is "light surface / dark surface"). So we do not need to touch the Swift at all
to reskin: we redefine what the endpoints of each pair mean.

This also automatically retints the ~202 `Design.Utility.<Ramp>._500` references,
which are otherwise the worst part of the reskin — a numbered ramp carries no
semantics, so there is nothing to map them onto by hand.

Source of truth for the target values:
    zodl-android/ui-design-lib/.../theme/colors/ZappPalette.kt   (21 tokens)

Zapp's neutrals are WARM (brown-tinted: #15120D text, #F4F2EE surfaceAlt,
#0F0E0C dark bg), not the cool grays Zashi ships. That warmth plus the
#FF9417 accent is most of what makes the reskin read as Zapp.

IMPORTANT: Shark ASCENDS DARKER. Verified against DesignSystem.swift:
    bgSecondary   = col(gray50,  shark900)   <- bg      (darkest)
    strokePrimary = col(gray200, shark700)   <- stroke  (lighter than bg)
so shark950 is the darkest surface and shark25 is near-white text.

Run:  python3 Scripts/zapp-retheme-colors.py
Idempotent. Revert with `git checkout secant/Resources/Colors.xcassets`.
"""

import json
import pathlib
import sys

ASSETS = pathlib.Path(__file__).resolve().parent.parent / "secant/Resources/Colors.xcassets"

# --- Zapp anchors, copied from ZappPalette.kt -------------------------------
# light                        dark
# bg           #FFFFFF         #0F0E0C
# surface      #FFFFFF         #171512
# surfaceAlt   #F4F2EE         #1B1916
# surfaceInput #F6F4F0         #201D19
# border       #EBE7E0         #2A2622
# borderStrong #D9D4CA         #3A342D
# text         #15120D         #F6F2EA
# textMuted    #6B645A         #A59C90
# textSubtle   #9A9288         #726A60
# accent       #FF9417         #FF9417
# accentSoft   #FFE7CC         #3A2713
# accentText   #A65500         #FFB26B
# success      #2F9D6A         #5FD49C
# successSoft  #D7F0E3         #1A2E24
# danger       #D94545         #EF6A5F
# dangerSoft   #FDE2E0         #2E1A18

RAMPS = {
    # Accent. 500 is the Zapp accent; 100/800 are accentSoft/accentText (light),
    # 950 is accentSoft (dark).
    "Brand": {
        "25": "FFF8EF", "50": "FFEFDA", "100": "FFE7CC", "200": "FED7AA",
        "300": "FDBA74", "400": "FBA043", "500": "FF9417", "600": "EA7C0C",
        "700": "C2620A", "800": "A65500", "900": "7C3D00", "950": "3A2713",
    },
    # Warm light neutrals. Ascends darker.
    "Gray": {
        "25": "FCFBF9", "50": "F6F4F0", "100": "F4F2EE", "200": "EBE7E0",
        "300": "D9D4CA", "400": "BDB6A9", "500": "9A9288", "600": "6B645A",
        "700": "4F4941", "800": "35302A", "900": "221E19", "950": "15120D",
    },
    # Warm dark neutrals. Ascends darker (see module docstring).
    "Shark": {
        "25": "F6F2EA", "50": "E8E3D9", "100": "D3CCC0", "200": "B5ACA0",
        "300": "A59C90", "400": "8A8177", "500": "726A60", "600": "3A342D",
        "700": "2A2622", "800": "1B1916", "900": "171512", "950": "0F0E0C",
    },
    "SuccessGreen": {
        "25": "F0FBF5", "50": "D7F0E3", "100": "B9E5CE", "200": "8DD5B0",
        "300": "5FD49C", "400": "43B681", "500": "2F9D6A", "600": "268055",
        "700": "1F6644", "800": "184F35", "900": "123B28", "950": "1A2E24",
    },
    "ErrorRed": {
        "25": "FEF5F4", "50": "FDE2E0", "100": "FBCBC7", "200": "F7A6A0",
        "300": "F08078", "400": "EF6A5F", "500": "D94545", "600": "BE3838",
        "700": "9C2E2E", "800": "7A2525", "900": "551A1A", "950": "2E1A18",
    },
    # Zapp has no warning token. Keep a yellow, but warm it toward the accent
    # so it sits in the same family instead of reading as a foreign hue.
    "WarningYellow": {
        "25": "FEFAF0", "50": "FDF2D9", "100": "FAE4B0", "200": "F6D080",
        "300": "F0B94F", "400": "E8A62B", "500": "D89112", "600": "B8770D",
        "700": "935D0C", "800": "70470C", "900": "4E320A", "950": "2C1D08",
    },
    # Warm near-black. Already Zapp-adjacent; anchor it on the text token.
    "Espresso": {
        "25": "F7F5F2", "50": "EDE9E3", "100": "D8D1C7", "200": "B8AE9F",
        "300": "958A79", "400": "756A5B", "500": "5A5145", "600": "463F35",
        "700": "352F28", "800": "26221C", "900": "1A1712", "950": "15120D",
    },
}

# Purple / Indigo / HyperBlue: Zapp HAS NO BLUE, INDIGO OR PURPLE.
#
# These were left alone in the first pass on the theory that they carried
# categorical meaning worth keeping. Putting the app on a simulator disproved
# that in one screenshot: `Design.Utility.Purple._700/._950` is the SmartBanner
# gradient, i.e. the single loudest surface on the home screen, and it rendered
# as a giant violet slab in an otherwise warm monochrome app. It did not read as
# Zapp at all.
#
# Zapp is a monochrome system with exactly one chromatic pop (accent orange),
# plus green/red reserved for success/danger state. So the honest collapse is:
# every decorative/promotional hue folds onto the accent ramp. If an orange
# SmartBanner then reads as too loud, that is a design decision about the
# *banner* (Phase 2), not about the token.
ACCENT_ALIASED_RAMPS = ["HyperBlue", "Indigo", "Purple"]

# Dark-mode elevation ladder: Zapp bg -> surface -> surfaceAlt -> surfaceInput -> border.
SHARK_SHADES = {
    "00dp": "0F0E0C", "01dp": "131110", "02dp": "171512", "03dp": "191714",
    "04dp": "1B1916", "06dp": "1D1B17", "08dp": "201D19", "12dp": "23201B",
    "16dp": "26231E", "24dp": "2A2622",
}

BASE = {
    "Black": "000000",
    "Bone": "FFFFFF",       # Zapp light bg / surface
    "Brand": "FF9417",      # Zapp accent
    "Concrete": "F4F2EE",   # Zapp surfaceAlt (light)
    "Espresso": "15120D",   # warm near-black
    "Midnight": "0F0E0C",   # Zapp dark bg
    "Obsidian": "15120D",   # Zapp text (light) / warm black
}


def colorset_json(hex_rgb: str) -> dict:
    """Match the shipped format exactly: extended-srgb, 0xNN components."""
    r, g, b = hex_rgb[0:2], hex_rgb[2:4], hex_rgb[4:6]
    return {
        "colors": [
            {
                "color": {
                    "color-space": "extended-srgb",
                    "components": {
                        "alpha": "1.000",
                        "blue": f"0x{b.upper()}",
                        "green": f"0x{g.upper()}",
                        "red": f"0x{r.upper()}",
                    },
                },
                "idiom": "universal",
            }
        ],
        "info": {"author": "xcode", "version": 1},
    }


def write(path: pathlib.Path, hex_rgb: str) -> bool:
    contents = path / "Contents.json"
    if not contents.exists():
        print(f"  MISS  {path.name} (no Contents.json)", file=sys.stderr)
        return False
    contents.write_text(json.dumps(colorset_json(hex_rgb), indent=2) + "\n")
    return True


def main() -> int:
    if not ASSETS.exists():
        print(f"error: {ASSETS} not found", file=sys.stderr)
        return 1

    zdesign = ASSETS / "ZDesign"
    written = 0
    missed = 0

    for ramp, steps in RAMPS.items():
        for step, hex_rgb in steps.items():
            if write(zdesign / f"{ramp}{step}.colorset", hex_rgb):
                written += 1
            else:
                missed += 1

    # Fold the foreign hues onto the accent ramp (see ACCENT_ALIASED_RAMPS).
    for ramp in ACCENT_ALIASED_RAMPS:
        for step, hex_rgb in RAMPS["Brand"].items():
            if write(zdesign / f"{ramp}{step}.colorset", hex_rgb):
                written += 1
            else:
                missed += 1

    for step, hex_rgb in SHARK_SHADES.items():
        if write(zdesign / f"SharkShades{step}.colorset", hex_rgb):
            written += 1
        else:
            missed += 1

    for name, hex_rgb in BASE.items():
        if write(zdesign / "Base" / f"{name}.colorset", hex_rgb):
            written += 1
        else:
            missed += 1

    print(f"retinted {written} colorsets to the Zapp palette ({missed} missing)")
    print(f"folded onto the accent ramp: {', '.join(ACCENT_ALIASED_RAMPS)}")
    return 1 if missed else 0


if __name__ == "__main__":
    sys.exit(main())
