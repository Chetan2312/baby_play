#!/usr/bin/env python3
"""Fail the build on broken content.

Errors (exit 1):
  - a line_id/variant missing one of mr/hi/en, empty text, unknown category
  - a game references an unknown line, or a prompt check the vision service doesn't know
  - manifest points at a missing voice file
  - a session step with an unknown line/type, a missing fallback game or bridge lines
  - a week without mr/hi/en title or games, duplicate week numbers
  - a centre profile value out of range (language mode, week, session, minutes, slots, PIN …)
  - a UI string missing mr/en
  - with --release: draft voice files, and any text not reviewed by a native speaker
Warnings:
  - no voice file yet for a line (errors with --strict-audio)
  - fewer praise/encourage variants than the brief asks for
  - a session/week game that isn't built yet (the session plays the fallback game)
  - Aadharshila references still TODO
  - text not reviewed yet (reviewed: false); --list-unreviewed prints every one
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "vision"))

from content_common import (CATEGORIES, CONTENT, LANGS, read_centre_profile, read_games,  # noqa: E402
                            read_lines, read_manifest, read_sessions, read_ui_strings, read_weeks,
                            voice_key)

MIN_POOL = {"praise": 25, "encourage": 15}
STEP_TYPES = ("game", "mascot_line")
LANGUAGE_MODES = ("mr_first", "all_three", "single")
DIFFICULTIES = ("toddler", "kid")
SPONSORS = ("none", "cummins_foundation")
LANDINGS = ("picker", "session")
UI_LANGS = ("mr", "en")


def lint_sessions(sessions, lines, games):
    errors, warnings = [], []
    for sid, sess in sessions.items():
        fb = sess.get("fallback_game")
        if fb not in games:
            errors.append(f"session {sid}: fallback_game {fb!r} is not a built game")
        prefix = sess.get("bridge_prefix")
        if prefix and not any(lid.startswith(prefix) for lid in lines):
            errors.append(f"session {sid}: no lines with bridge_prefix {prefix!r}")
        total = 0.0
        ids = set()
        for i, st in enumerate(sess.get("steps", [])):
            sid_ = st.get("id") or f"#{i + 1}"
            if sid_ in ids:
                errors.append(f"session {sid}: duplicate step id {sid_!r}")
            ids.add(sid_)
            kind = st.get("type", "game")
            if kind not in STEP_TYPES:
                errors.append(f"session {sid} step {sid_}: unknown type {kind!r}")
            elif kind == "mascot_line":
                if st.get("line") not in lines:
                    errors.append(f"session {sid} step {sid_}: unknown line {st.get('line')!r}")
                if st.get("then") not in (None, "end_session"):
                    errors.append(f"session {sid} step {sid_}: unknown then {st.get('then')!r}")
            else:
                g = st.get("game")
                if not g:
                    errors.append(f"session {sid} step {sid_}: no game")
                elif g != "from_week" and g not in games:
                    warnings.append(f"session {sid} step {sid_}: game {g!r} not built yet (plays {fb})")
                m = st.get("minutes")
                if not isinstance(m, (int, float)) or m <= 0:
                    errors.append(f"session {sid} step {sid_}: minutes must be > 0")
                else:
                    total += m
        tm = sess.get("total_minutes", 0)
        if not 12 <= tm <= 20:
            warnings.append(f"session {sid}: total_minutes {tm} outside 12–20")
        if total > tm:
            warnings.append(f"session {sid}: game steps add up to {total} min > total_minutes {tm}")
    return errors, warnings


def lint_weeks(weeks, games):
    errors, warnings = [], []
    seen = set()
    for w in weeks:
        n = w.get("week")
        tag = f"week {n}"
        if not isinstance(n, int) or n < 1:
            errors.append(f"{tag}: week must be a positive integer")
        elif n in seen:
            errors.append(f"{tag}: duplicate week number")
        seen.add(n)
        for lang in LANGS:
            if not (w.get("title") or {}).get(lang):
                errors.append(f"{tag}: title missing {lang}")
        if not w.get("theme_id"):
            errors.append(f"{tag}: no theme_id")
        if not w.get("games"):
            errors.append(f"{tag}: no games")
        for g in w.get("games") or []:
            if g not in games:
                warnings.append(f"{tag} ({w.get('theme_id')}): game {g!r} not built yet")
        if "TODO" in str(w.get("aadharshila_ref", "TODO")):
            warnings.append(f"{tag} ({w.get('theme_id')}): aadharshila_ref is TODO "
                            "(fill from the Aadharshila document; never invent it)")
    return errors, warnings


def lint_centre(c, weeks, sessions):
    errors = []

    def bad(k, why):
        errors.append(f"centre_profile: {k} {c.get(k)!r} {why}")

    if c.get("language_mode") not in LANGUAGE_MODES:
        bad("language_mode", f"must be one of {LANGUAGE_MODES}")
    if c.get("primary_language") not in LANGS:
        bad("primary_language", f"must be one of {LANGS}")
    if c.get("difficulty") not in DIFFICULTIES:
        bad("difficulty", f"must be one of {DIFFICULTIES}")
    if c.get("landing") not in LANDINGS:
        bad("landing", f"must be one of {LANDINGS}")
    if c.get("session") not in sessions:
        bad("session", "is not a session in content/sessions/")
    if not isinstance(c.get("session_minutes"), (int, float)) or not 12 <= c["session_minutes"] <= 20:
        bad("session_minutes", "must be 12–20")
    if not isinstance(c.get("slots"), int) or not 1 <= c["slots"] <= 4:
        bad("slots", "must be 1–4")
    if c.get("current_week") not in {w.get("week") for w in weeks}:
        bad("current_week", "is not in curriculum/weeks.yaml")
    if not isinstance(c.get("ai_literacy_enabled"), bool):
        bad("ai_literacy_enabled", "must be true/false")
    if c.get("sponsor_branding") not in SPONSORS:
        bad("sponsor_branding", f"must be one of {SPONSORS}")
    for k in ("max_sessions_per_day", "max_minutes_per_day"):
        if not isinstance(c.get(k), int) or c[k] < 1:
            bad(k, "must be a positive integer")
    pin = c.get("supervisor_pin")
    if not (isinstance(pin, str) and len(pin) == 4 and pin.isdigit()):
        bad("supervisor_pin", "must be a quoted 4-digit string")
    return errors


def lint_ui(ui):
    errors = []
    for k, v in ui.items():
        for lang in UI_LANGS:
            if not isinstance(v, dict) or not v.get(lang):
                errors.append(f"ui string {k}: missing {lang}")
    return errors


def unreviewed():
    """Every piece of text a native speaker hasn't checked yet: [(kind, id)]."""
    out = [("line", lid) for lid, e in read_lines().items() if not e.get("reviewed")]
    out += [("week title", f"week {w.get('week')} {w.get('theme_id')}") for w in read_weeks()
            if not w.get("reviewed", False)]
    out += [("ui string", k) for k, v in read_ui_strings().items()
            if not (isinstance(v, dict) and v.get("reviewed", False))]
    return out


def lint(strict_audio=False, release=False):
    errors, warnings = [], []
    lines = read_lines()
    for lid, e in lines.items():
        if e["category"] not in CATEGORIES:
            errors.append(f"{lid}: unknown category {e['category']!r}")
        for v, data in e["variants"].items():
            for lang in LANGS:
                t = data["text"].get(lang)
                if not t:
                    errors.append(f"{lid} v{v}: missing {lang}")
                elif "{" in t or "}" in t:
                    errors.append(f"{lid} v{v} {lang}: placeholders are not speakable: {t!r}")
    for cat, n in MIN_POOL.items():
        have = sum(len(e["variants"]) for e in lines.values() if e["category"] == cat)
        if have < n:
            warnings.append(f"category {cat}: {have} variants, brief asks for ≥ {n} per language")

    try:
        from takatak_vision.gestures import CHECKS
    except ImportError:
        CHECKS = None
    for gid, g in read_games().items():
        refs = [g.get("intro_line")] + [p.get(k) for p in g.get("prompts", []) for k in ("line", "word")]
        for r in refs:
            if r and r not in lines:
                errors.append(f"game {gid}: unknown line {r!r}")
        prefix = g.get("hint_prefix")
        if prefix and not any(lid.startswith(prefix) for lid in lines):
            errors.append(f"game {gid}: no lines with hint_prefix {prefix!r}")
        for pack, pitems in (g.get("packs") or {}).items():
            if not pitems:
                errors.append(f"game {gid}: pack {pack!r} is empty")
            for it in pitems or []:
                tag = f"game {gid} pack {pack} item {it.get('id')!r}"
                for k in ("line", "word"):
                    if it.get(k) not in lines:
                        errors.append(f"{tag}: unknown {k} {it.get(k)!r}")
                if it.get("image") and not os.path.exists(os.path.join(CONTENT, it["image"])):
                    errors.append(f"{tag}: image missing {it['image']}")
        for entry in g.get("picker") or []:
            if entry.get("pack") not in (g.get("packs") or {}):
                errors.append(f"game {gid}: picker pack {entry.get('pack')!r} is not one of its packs")
            for lang in LANGS:
                if not (entry.get("title") or {}).get(lang):
                    errors.append(f"game {gid}: picker {entry.get('pack')!r} title missing {lang}")
        levels = g.get("levels") or {}
        if levels and isinstance(next(iter(levels.values())), dict):
            for lv, cfg in levels.items():
                if lv not in ("easy", "medium", "hard"):
                    errors.append(f"game {gid}: unknown level {lv!r} (easy | medium | hard)")
                if cfg.get("distractors", "all") not in ("all", "other_packs", "same_pack"):
                    errors.append(f"game {gid} level {lv}: distractors must be all | other_packs | same_pack")
            for dif, lv in (g.get("session_level") or {}).items():
                if lv not in levels:
                    errors.append(f"game {gid}: session_level {dif} → unknown level {lv!r}")
        for k in ("bee_intro_line", "bee_oops_line", "finger_intro_line", "perfect_line"):
            if g.get(k) and g[k] not in lines:
                errors.append(f"game {gid}: unknown {k} {g[k]!r}")
        if g.get("bee") and g["bee"].get("word") not in lines:
            errors.append(f"game {gid}: bee word {g['bee'].get('word')!r} unknown")
        if g.get("default_pack") and g["default_pack"] not in (g.get("packs") or {}):
            errors.append(f"game {gid}: default_pack {g['default_pack']!r} is not one of its packs")
        ids = {p["id"] for p in g.get("prompts", [])}
        for level, pool in (g.get("levels") or {}).items():
            if not isinstance(pool, list):   # Bubble Pop-style levels are settings, not prompt lists
                continue
            for pid in pool:
                if pid not in ids:
                    errors.append(f"game {gid}: level {level} lists unknown prompt {pid!r}")
        if CHECKS is not None:
            for p in g.get("prompts", []):
                if p.get("check") and p["check"] not in CHECKS:
                    errors.append(f"game {gid}: prompt {p['id']} has unknown check {p['check']!r}")

    games = read_games()
    sessions, weeks = read_sessions(), read_weeks()
    for e, w in (lint_sessions(sessions, lines, games), lint_weeks(weeks, games)):
        errors += e
        warnings += w
    errors += lint_centre(read_centre_profile(), weeks, sessions)
    errors += lint_ui(read_ui_strings())
    todo = unreviewed()
    if todo:
        kinds = {}
        for k, _ in todo:
            kinds[k] = kinds.get(k, 0) + 1
        msg = ("not reviewed by a native speaker: "
               + ", ".join(f"{n} {k}{'s' if n > 1 else ''}" for k, n in kinds.items())
               + " (--list-unreviewed)")
        (errors if release else warnings).append(msg)

    manifest = read_manifest()
    missing_audio = 0
    for lid, e in lines.items():
        for v in e["variants"]:
            for lang in LANGS:
                m = manifest.get(voice_key(lid, v, lang))
                if m is None:
                    missing_audio += 1
                    continue
                if not os.path.exists(os.path.join(CONTENT, m["path"])):
                    errors.append(f"{lid} v{v} {lang}: manifest file missing {m['path']}")
                if release and m.get("draft"):
                    errors.append(f"{lid} v{v} {lang}: draft voice in a release build")
    if missing_audio:
        msg = f"{missing_audio} line/language combinations have no voice file yet (run ./run.sh content)"
        (errors if strict_audio else warnings).append(msg)
    return errors, warnings


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strict-audio", action="store_true")
    ap.add_argument("--release", action="store_true",
                    help="also fail on draft voices and unreviewed text")
    ap.add_argument("--list-unreviewed", action="store_true",
                    help="print every line, week title and UI string still marked reviewed: false")
    args = ap.parse_args()
    if args.list_unreviewed:
        for kind, ident in unreviewed():
            print(f"unreviewed {kind}: {ident}")
    errors, warnings = lint(args.strict_audio, args.release)
    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("ERROR:", e)
    print(f"content lint: {len(errors)} errors, {len(warnings)} warnings")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
