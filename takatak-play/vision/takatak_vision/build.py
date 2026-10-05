"""Build flavour: "field" (anganwadi kits, the default) or "dev".

Field builds never record, dump frames or save debug images. In a packaged field
build (tools/make_field_build.py) the dev tools are left out entirely and
_build.py pins BUILD = "field", which no environment variable can override.
In a source checkout TAKATAK_BUILD=dev unlocks the dev tools.
"""
import os
import sys

BUILDS = ("field", "dev")

try:
    from ._build import BUILD as _PINNED   # written only by tools/make_field_build.py
except ImportError:
    _PINNED = None


def current():
    if _PINNED:
        return _PINNED
    b = os.environ.get("TAKATAK_BUILD", "field").strip().lower()
    return b if b in BUILDS else "field"


def is_field():
    return current() == "field"


def require_dev(feature):
    """Hard stop for dev-only features (recording, frame dumps) in a field build."""
    if is_field():
        sys.exit(f"{feature} is disabled in field builds (privacy: nothing is recorded). "
                 "Developers: TAKATAK_BUILD=dev in a source checkout.")
