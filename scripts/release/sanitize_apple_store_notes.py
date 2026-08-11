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
