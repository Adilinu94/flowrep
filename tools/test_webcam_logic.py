"""Pure unit tests for CV-05 angle + rep logic (no camera / mediapipe)."""

from __future__ import annotations

import unittest

import numpy as np

from webcam_rep_counter import (
    ANGLE_DOWN_THRESHOLD,
    ANGLE_UP_THRESHOLD,
    RepCounter,
    calculate_angle,
)


class TestCalculateAngle(unittest.TestCase):
    def test_right_angle(self) -> None:
        a = np.array([0.0, 1.0])
        b = np.array([0.0, 0.0])
        c = np.array([1.0, 0.0])
        self.assertAlmostEqual(calculate_angle(a, b, c), 90.0, places=2)

    def test_straight(self) -> None:
        a = np.array([-1.0, 0.0])
        b = np.array([0.0, 0.0])
        c = np.array([1.0, 0.0])
        self.assertAlmostEqual(calculate_angle(a, b, c), 180.0, places=2)


class TestRepCounter(unittest.TestCase):
    def test_full_rep(self) -> None:
        c = RepCounter()
        self.assertFalse(c.process(170.0, 0.0))
        self.assertEqual(c.state, c.ARM_DOWN)
        self.assertFalse(c.process(50.0, 0.6))
        self.assertEqual(c.state, c.ARM_UP)
        self.assertTrue(c.process(170.0, 1.3))
        self.assertEqual(c.rep_count, 1)

    def test_thresholds_match_flutter_defaults(self) -> None:
        self.assertEqual(ANGLE_DOWN_THRESHOLD, 160.0)
        self.assertEqual(ANGLE_UP_THRESHOLD, 90.0)


if __name__ == "__main__":
    unittest.main()
