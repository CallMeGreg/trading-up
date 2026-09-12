"""Fast music-source regressions; no ffmpeg, simulator or full-loop rendering.

    python3 -B -m unittest discover -s tools -p test_music.py
"""

import hashlib
import unittest
from collections import Counter
from dataclasses import replace
from unittest.mock import patch

import generate_music
from sound_lab import classic_backgrounds, music, neon_dead_drop


SOFT_CIRCUIT_SHA256 = "e3f041fdf8da53db5177501e2a8ae0da9a4e80f66af1080663a4bc7a40188520"
PAPER_LANTERNS_SHA256 = "267acb0d1757bc7584c7f55893b5e9be728e5e73c338e60ec7f45d2f1456a913"


class MusicScoreTests(unittest.TestCase):
    def test_defaults_match_the_approved_tracks(self):
        generate_music.validate_scores()
        self.assertEqual(
            {score.mode: score.id for score in generate_music.SCORES if score.recommended},
            {"classic": "classic-soft-circuit", "gauntlet": "gauntlet-neon-dead-drop"},
        )
        self.assertEqual(len(generate_music.SCORES), 8)

    def test_neon_removes_only_the_original_melodic_events(self):
        original = neon_dead_drop._original_arrangement()
        self.assertEqual(
            neon_dead_drop.arrangement_sha256(original),
            "726153e7f7561929737c1b07258145dd83ff7d079a4d12412e11fdd9dd430d9e",
        )
        retained = neon_dead_drop.arrange()
        self.assertEqual(retained, tuple(event for event in original if event.voice not in ("pluck", "string")))
        self.assertEqual(len(original) - len(retained), 658)
        self.assertEqual(Counter(event.voice for event in retained), {
            "bass": 272, "clap": 64, "crash": 4, "hat": 256,
            "kick": 124, "open": 68, "snare": 104, "tom": 16,
        })
        self.assertEqual(neon_dead_drop.SCORE.tempo, 148)
        self.assertEqual(neon_dead_drop.SCORE.bars, 32)

    def test_neon_still_detects_a_changed_bass_or_drum_pattern(self):
        with self.assertRaises(AssertionError):
            neon_dead_drop.validate_score(replace(neon_dead_drop.SCORE, root=31))
        with self.assertRaises(AssertionError):
            neon_dead_drop.validate_score(replace(neon_dead_drop.SCORE, seed=911149))

    def test_classic_backgrounds_are_distinct_with_only_soft_circuit_selected(self):
        expected = {
            "classic-pocket-change": (108, "shuffle", 624),
            "classic-soft-circuit": (116, "straight", 716),
            "classic-velvet-current": (124, "halftime", 480),
        }
        self.assertEqual(set(expected), classic_backgrounds.SCORE_IDS)
        for score in classic_backgrounds.SCORES:
            with self.subTest(score=score.id):
                events = classic_backgrounds.arrange(score)
                self.assertEqual((score.tempo, score.groove, len(events)), expected[score.id])
                self.assertEqual(score.mode, "classic")
                self.assertEqual(score.recommended, score.id == "classic-soft-circuit")
                self.assertEqual(events, classic_backgrounds.arrange(score))
                self.assertTrue(all(event.voice in {
                    "bass", "kick", "rim", "brush", "shaker", "hat", "open", "snare", "tom", "low_tom",
                } for event in events))
                self.assertTrue(all(30 <= event.pitch <= 52 for event in events if event.voice == "bass"))
                self.assertTrue(all(event.pitch == 0 for event in events if event.voice != "bass"))

    def test_exact_circular_frame_budgets(self):
        expected = {
            "classic-paper-lanterns": 1_772_544,
            "gauntlet-neon-dead-drop": 2_490_368,
            "classic-pocket-change": 3_412_992,
            "classic-soft-circuit": 3_177_472,
            "classic-velvet-current": 2_972_672,
        }
        for score in generate_music.SCORES:
            if score.id not in expected:
                continue
            with self.subTest(score=score.id):
                self.assertEqual(score.frames, expected[score.id])
                self.assertEqual(score.frames % music.AAC_FRAME, 0)
                self.assertAlmostEqual(score.duration * music.SR, score.frames)
                self.assertLess(abs(score.tempo - score.bpm), .04)

    def test_render_dispatch_does_not_route_candidates_through_legacy_leads(self):
        with patch.object(generate_music, "render_legacy") as legacy, \
                patch.object(generate_music, "render_neon") as neon, \
                patch.object(generate_music, "render_classic_background") as background:
            for score in classic_backgrounds.SCORES:
                generate_music.render(score)
                background.assert_called_with(score)
            legacy.assert_not_called()
            neon.assert_not_called()
            generate_music.render(neon_dead_drop.SCORE)
            neon.assert_called_once_with(neon_dead_drop.SCORE)
            generate_music.render(music.SCORES[0])
            legacy.assert_called_once_with(music.SCORES[0])


class ClassicSelectionTests(unittest.TestCase):
    def setUp(self):
        self.selected = next(
            score for score in generate_music.SCORES if score.mode == "classic" and score.recommended
        )

    def test_soft_circuit_is_the_selected_classic_track(self):
        self.assertEqual(self.selected.id, "classic-soft-circuit")

    def test_selected_audio_matches_the_approved_audition(self):
        path = generate_music.AUDITIONS / f"{self.selected.id}.m4a"
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), SOFT_CIRCUIT_SHA256)

    def test_classic_app_copy_is_byte_identical_to_the_selected_audition(self):
        self.assertEqual(
            (generate_music.APP / "classic.m4a").read_bytes(),
            (generate_music.AUDITIONS / f"{self.selected.id}.m4a").read_bytes(),
        )

    def test_paper_lanterns_remains_an_unchanged_alternate(self):
        paper = next(score for score in music.SCORES if score.id == "classic-paper-lanterns")
        self.assertFalse(paper.recommended)
        path = generate_music.AUDITIONS / f"{paper.id}.m4a"
        self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), PAPER_LANTERNS_SHA256)


if __name__ == "__main__":
    unittest.main()
