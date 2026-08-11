#!/usr/bin/env python3
"""Unit tests for sanitize_apple_store_notes.py."""

import importlib.util
import os
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location(
    "sanitize_apple_store_notes",
    os.path.join(_HERE, "sanitize_apple_store_notes.py"),
)
san = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(san)

TERMS = san.load_terms()


def matched(text):
    """The matched substrings in text, in order."""
    return [text[s:e] for s, e, _cls in san.find_matches(text, TERMS)]


class TestDetection(unittest.TestCase):
    def test_detects_each_platform_name(self):
        self.assertEqual(matched("Broken on Windows."), ["Windows"])
        self.assertEqual(matched("Broken on Android."), ["Android"])
        self.assertEqual(matched("Broken on Linux."), ["Linux"])

    def test_platform_names_are_case_insensitive_except_windows(self):
        self.assertEqual(matched("broken on android"), ["android"])
        self.assertEqual(matched("broken on linux"), ["linux"])

    def test_distro_and_installer_names(self):
        self.assertEqual(matched("Install the Ubuntu build."), ["Ubuntu"])
        self.assertEqual(matched("Install the Debian build."), ["Debian"])
        self.assertEqual(matched("A Flatpak is provided."), ["Flatpak"])
        self.assertEqual(matched("An AppImage is provided."), ["AppImage"])
        self.assertEqual(matched("Run Submersion.exe now."), [".exe"])
        self.assertEqual(matched("Ships as an MSI package."), ["MSI"])

    def test_apt_only_matches_command_context(self):
        self.assertEqual(matched("Run sudo apt install tesseract-ocr"),
                         ["sudo apt install"])
        self.assertEqual(matched("That is an apt description."), [])

    def test_microsoft_and_pc(self):
        self.assertEqual(matched("Your Mac or PC can browse them."), ["PC"])
        self.assertEqual(matched("Reads the Microsoft Store listing."),
                         ["Microsoft Store"])

    def test_store_class_terms(self):
        hits = san.find_matches("Available on Google Play Store today.", TERMS)
        self.assertTrue(hits)
        self.assertEqual({cls for _s, _e, cls in hits}, {"store"})

    def test_google_play_store_is_consumed_whole(self):
        # Declaration order matters: the longer spelling must win, or a stray
        # "Store" is left behind for the replacement pass to mangle.
        self.assertEqual(matched("On Google Play Store.")[0],
                         "Google Play Store")

    # --- The negative corpus: real sentences from docs/releases/ -------------

    def test_lowercase_window_prose_is_never_matched(self):
        for line in [
            "A two-column layout on wide windows for desktop and tablet.",
            "The planner gets the whole window.",
            "photos plainly inside the dive window were rejected",
            "falls only across the windows where it is",
            "on a window that was too narrow, zooming out can unlock it",
        ]:
            with self.subTest(line=line):
                self.assertEqual(matched(line), [])


class TestListRepair(unittest.TestCase):
    def repair(self, text):
        return san.repair_lists(text, TERMS)

    def test_four_members_one_survivor(self):
        self.assertEqual(
            self.repair("Downloads (macOS, Windows, Linux, and Android)"),
            "Downloads (macOS)",
        )

    def test_three_members_one_survivor(self):
        self.assertEqual(
            self.repair("shown on Mac, Windows, and Linux today"),
            "shown on Mac today",
        )

    def test_five_members_two_survivors_get_a_conjunction(self):
        self.assertEqual(
            self.repair("on iOS, Android, macOS, Windows, and Linux"),
            "on iOS and macOS",
        )

    def test_three_survivors_keep_the_oxford_comma(self):
        self.assertEqual(
            self.repair("on iOS, iPadOS, macOS, Windows, and Android"),
            "on iOS, iPadOS, and macOS",
        )

    def test_no_survivors_collapse_to_the_neutral_phrase(self):
        self.assertEqual(
            self.repair("broken on Windows, Linux, and Android"),
            "broken on other platforms",
        )

    def test_clean_list_is_untouched(self):
        text = "covers dives, dive sites, and gear"
        self.assertEqual(self.repair(text), text)

    def test_conjunction_is_not_parsed_as_a_member(self):
        # The clause after the list must survive: "and continues with the app"
        # is not part of the list and must not be rewritten away with it.
        self.assertEqual(
            self.repair(
                "Recording works on iPhone, iPad, and Android and continues "
                "with the app backgrounded"
            ),
            "Recording works on iPhone and iPad and continues "
            "with the app backgrounded",
        )

    def test_or_lists_are_handled(self):
        self.assertEqual(
            self.repair("use Windows or macOS"),
            "use macOS",
        )

    def test_leading_prose_is_not_absorbed_into_the_first_member(self):
        # The regression that multi-word members caused: the greedy first
        # member swallowed the words before the list ("broken on Windows"),
        # which is not entirely a banned term, so the platform name survived.
        self.assertEqual(
            self.repair("broken on Windows, Linux, and Android today"),
            "broken on other platforms today",
        )
        self.assertEqual(
            self.repair("a fix for Windows or Linux"),
            "a fix for other platforms",
        )


class TestReplacement(unittest.TestCase):
    def replace(self, text):
        return san.replace_terms(text, TERMS)

    def test_default_replacement(self):
        self.assertEqual(
            self.replace("a crash specific to Android devices"),
            "a crash specific to other platforms devices",
        )

    def test_preposition_form_falls_out_of_the_default(self):
        self.assertEqual(
            self.replace("On Android this works through the USB Host API."),
            "On other platforms this works through the USB Host API.",
        )

    def test_possessive_does_not_leave_an_orphan_s(self):
        self.assertEqual(
            self.replace("reads Windows's certificate store"),
            "reads other platforms' certificate store",
        )
        self.assertEqual(
            self.replace("uses Android’s folder picker"),
            "uses other platforms’ folder picker",
        )

    def test_sentence_initial_is_capitalised(self):
        self.assertEqual(
            self.replace("Fixed a bug. Android backups now work."),
            "Fixed a bug. Other platforms backups now work.",
        )

    def test_line_initial_is_capitalised(self):
        self.assertEqual(
            self.replace("- Fixed a thing\nLinux users are unblocked"),
            "- Fixed a thing\nOther platforms users are unblocked",
        )

    def test_store_class_uses_its_own_phrase(self):
        self.assertEqual(
            self.replace("also on Google Play"),
            "also on another store",
        )


class TestTidy(unittest.TestCase):
    def test_collapses_adjacent_duplicate_phrases(self):
        self.assertEqual(
            san.tidy("broken on other platforms and other platforms today"),
            "broken on other platforms today",
        )

    def test_removes_emptied_parentheses(self):
        self.assertEqual(san.tidy("Downloads ( )"), "Downloads")

    def test_repairs_dangling_commas(self):
        self.assertEqual(san.tidy("Downloads (macOS, )"), "Downloads (macOS)")

    def test_collapses_runs_of_spaces(self):
        self.assertEqual(san.tidy("a  b"), "a b")

    def test_strips_trailing_whitespace_per_line(self):
        self.assertEqual(san.tidy("a  \nb"), "a\nb")


if __name__ == "__main__":
    unittest.main()
