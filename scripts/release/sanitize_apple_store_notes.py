#!/usr/bin/env python3
"""Strip non-Apple platform references out of App Store Connect note fields.

App Review guideline 2.3.10 forbids referring to other platforms in App Store
metadata, but the text both Apple-bound note fields are generated from is
multi-platform by nature. The App Store "What's New" comes from the GitHub
release body, written for every platform at once, and the TestFlight "What to
Test" comes from PR titles that carry scopes like `fix(android):`. Every file
in docs/releases/ contains at least one banned term.

This rewrites that text rather than rejecting it, so a release is never blocked
on wording. Redaction is word-level: platform names are dropped out of lists
("macOS, Windows, Linux, and Android" becomes "macOS") and otherwise replaced
with a neutral phrase. The accepted trade-off is that a clause written about
one platform can survive as a non-sequitur.

Only Apple-bound text passes through here. Google Play notes, the GitHub
release body, the Sparkle appcast and docs/releases/*.md keep every platform
name.

Usage: sanitize_apple_store_notes.py [--fallback TEXT] [--report] < in > out

Diagnostics go to stderr; stdout is only ever the sanitized text. Exit 2 means
a banned term survived every pass, which is a bug in this script rather than a
problem with the input. Pure stdlib.
"""

import argparse
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
TERMS_PATH = os.path.join(_HERE, "apple_store_banned_terms.json")

REPLACEMENT = {"platform": "other platforms", "store": "another store"}


def load_terms(path=TERMS_PATH):
    """Return [(compiled_pattern, term_class)] in declaration order.

    Declaration order is preserved and significant; see the note in the JSON.
    """
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    terms = []
    for term in data["terms"]:
        flags = re.IGNORECASE if term["ignorecase"] else 0
        terms.append((re.compile(term["pattern"], flags), term["class"]))
    return terms


def find_matches(text, terms):
    """Return [(start, end, term_class)] for every banned term, by position.

    Overlapping hits from different patterns are all reported; callers use
    this for detection and reporting, never for rewriting.
    """
    hits = []
    for pattern, term_class in terms:
        for match in pattern.finditer(text):
            hits.append((match.start(), match.end(), term_class))
    return sorted(hits)


# A list member is exactly one word. Allowing multi-word members looks more
# general but is actively wrong: the leading member is greedy, so
# "broken on Windows, Linux, and Android" would parse its first member as
# "broken on Windows", which is not *entirely* a banned term, and the platform
# name would survive. Real platform lists are single tokens (macOS, Windows,
# iOS, Android). The one multi-word banned term that shows up in a list,
# "Google Play", is left to the replacement pass instead.
#
# The negative lookahead stops "and"/"or" being parsed as a member.
_WORD = r"(?!(?:and|or)\b)[A-Za-z0-9][A-Za-z0-9.+/-]*"
_MEMBER = _WORD

_LIST_RE = re.compile(
    r"\b" + _MEMBER +
    r"(?:\s*,\s*" + _MEMBER + r")*"
    r"\s*,?\s+(?:and|or)\s+" + _MEMBER + r"\b"
)

# The conjunction alternative must come first. Python tries alternatives left
# to right, so a leading plain-comma branch would consume the ", " of ", and "
# and leave "and Linux" behind as a member, rebuilding the list as
# "Mac and and Linux".
_SPLIT_RE = re.compile(r"\s*,?\s+(?:and|or)\s+|\s*,\s*")


def _is_banned_member(member, terms):
    """True when the member is *entirely* one banned term.

    A member that merely contains a banned term is left for the replacement
    pass; dropping it would delete real content alongside the platform name.
    """
    stripped = member.strip()
    return any(pattern.fullmatch(stripped) for pattern, _cls in terms)


def _join(members):
    """Rebuild a list with the Oxford comma the surrounding prose uses."""
    if len(members) >= 3:
        return ", ".join(members[:-1]) + ", and " + members[-1]
    if len(members) == 2:
        return members[0] + " and " + members[1]
    return members[0]


def repair_lists(text, terms):
    """Drop banned members from comma/conjunction lists, repairing punctuation.

    "(macOS, Windows, Linux, and Android)" becomes "(macOS)". A list whose
    members are all banned collapses to the neutral phrase, and the tidy pass
    removes the parentheses that are left empty around it.
    """
    def substitute(match):
        raw = match.group(0)
        members = [m for m in _SPLIT_RE.split(raw) if m]
        if not any(_is_banned_member(m, terms) for m in members):
            return raw
        kept = [m for m in members if not _is_banned_member(m, terms)]
        if not kept:
            return REPLACEMENT["platform"]
        return _join(kept)

    return _LIST_RE.sub(substitute, text)
