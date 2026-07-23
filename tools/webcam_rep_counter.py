#!/usr/bin/env python3
"""
FlowRep Webcam Rep-Counter — Development/Testing Tool (CV-05).

Uses MediaPipe Pose + Webcam to count bicep curls with the same angle
thresholds as the Flutter PoseRepCounter / VisionConfig.

Usage:
    pip install -r tools/requirements-cv.txt
    python tools/webcam_rep_counter.py
    python tools/webcam_rep_counter.py --headless --max-frames 30 --no-csv

Keys (interactive):
    q = quit
    r = reset counter
    s = skeleton overlay on/off
"""

from __future__ import annotations

import argparse
import csv
import time
import urllib.request
from datetime import datetime
from pathlib import Path

import numpy as np

# === CONFIG (must match app/lib/domain/vision/vision_config.dart defaults) ===
ANGLE_DOWN_THRESHOLD = 160.0
ANGLE_UP_THRESHOLD = 90.0
MIN_REP_INTERVAL = 0.5
MAX_REP_DURATION = 5.0
MIN_CONFIDENCE = 0.5
CAMERA_INDEX = 0
CSV_LOG = True

# MediaPipe Pose landmark indices (same as Flutter PoseLandmarkIndex)
RIGHT_SHOULDER = 12
RIGHT_ELBOW = 14
RIGHT_WRIST = 16

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
    "pose_landmarker_lite/float16/1/pose_landmarker_lite.task"
)
MODEL_NAME = "pose_landmarker_lite.task"


def calculate_angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """Angle at point b in degrees (same formula as AngleCalculator)."""
    ba = a - b
    bc = c - b
    mag_ba = np.linalg.norm(ba)
    mag_bc = np.linalg.norm(bc)
    if mag_ba < 1e-10 or mag_bc < 1e-10:
        return 0.0
    cos_angle = np.clip(np.dot(ba, bc) / (mag_ba * mag_bc), -1.0, 1.0)
    return float(np.degrees(np.arccos(cos_angle)))


class RepCounter:
    """Angle hysteresis SM aligned with Flutter PoseRepCounter."""

    WAITING = "waiting"
    ARM_DOWN = "arm_down"
    ARM_UP = "arm_up"

    def __init__(self) -> None:
        self.state = self.WAITING
        self.rep_count = 0
        self.last_rep_time = 0.0
        self.rep_start_time = 0.0
        self.history: list[dict] = []

    def process(self, angle: float, timestamp: float) -> bool:
        if self.state == self.WAITING:
            if angle > ANGLE_DOWN_THRESHOLD:
                self.state = self.ARM_DOWN
            return False

        if self.state == self.ARM_DOWN:
            if angle < ANGLE_UP_THRESHOLD:
                self.state = self.ARM_UP
                self.rep_start_time = timestamp
            return False

        if self.state == self.ARM_UP:
            if angle > ANGLE_DOWN_THRESHOLD:
                time_since_last = timestamp - self.last_rep_time
                rep_duration = timestamp - self.rep_start_time
                if self.last_rep_time > 0 and time_since_last < MIN_REP_INTERVAL:
                    self.state = self.ARM_DOWN
                    return False
                if rep_duration > MAX_REP_DURATION:
                    self.state = self.ARM_DOWN
                    return False
                self.rep_count += 1
                self.last_rep_time = timestamp
                self.state = self.ARM_DOWN
                self.history.append(
                    {
                        "rep": self.rep_count,
                        "timestamp": timestamp,
                        "duration": rep_duration,
                    }
                )
                return True
        return False

    def reset(self) -> None:
        self.state = self.WAITING
        self.rep_count = 0
        self.last_rep_time = 0.0
        self.rep_start_time = 0.0
        self.history.clear()


def ensure_pose_model(model_dir: Path) -> Path:
    """Return path to pose_landmarker_lite.task, downloading if needed."""
    model_dir.mkdir(parents=True, exist_ok=True)
    path = model_dir / MODEL_NAME
    if path.is_file() and path.stat().st_size > 1000:
        return path
    print(f"Downloading pose model → {path}")
    urllib.request.urlretrieve(MODEL_URL, path)
    return path


def elbow_angle_from_landmarks(landmarks) -> float | None:
    """Right-arm elbow angle if shoulder/elbow/wrist visibility is enough."""
    if landmarks is None or len(landmarks) <= RIGHT_WRIST:
        return None
    shoulder = landmarks[RIGHT_SHOULDER]
    elbow = landmarks[RIGHT_ELBOW]
    wrist = landmarks[RIGHT_WRIST]
    # Tasks API: visibility; solutions-compat may use same attr.
    s_vis = getattr(shoulder, "visibility", 1.0) or 0.0
    e_vis = getattr(elbow, "visibility", 1.0) or 0.0
    w_vis = getattr(wrist, "visibility", 1.0) or 0.0
    if min(s_vis, e_vis, w_vis) < MIN_CONFIDENCE:
        return None
    a = np.array([shoulder.x, shoulder.y])
    b = np.array([elbow.x, elbow.y])
    c = np.array([wrist.x, wrist.y])
    return calculate_angle(a, b, c)


def main() -> None:
    parser = argparse.ArgumentParser(description="FlowRep webcam rep counter")
    parser.add_argument("--camera", type=int, default=CAMERA_INDEX)
    parser.add_argument("--no-csv", action="store_true")
    parser.add_argument(
        "--max-frames",
        type=int,
        default=0,
        help="Stop after N frames (0 = unlimited interactive).",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        help="No imshow/waitKey window (CI / automated probe).",
    )
    args = parser.parse_args()

    try:
        import cv2
        from mediapipe.tasks import python as mp_python
        from mediapipe.tasks.python import vision as mp_vision
        from mediapipe import Image as MpImage
        from mediapipe import ImageFormat
    except ImportError as e:
        print("Missing dependency:", e)
        print("Install with: pip install -r tools/requirements-cv.txt")
        raise SystemExit(1) from e

    print("=" * 60)
    print("FlowRep Webcam Rep-Counter (CV-05)")
    print("=" * 60)
    print(
        f"Thresholds: DOWN > {ANGLE_DOWN_THRESHOLD}°, "
        f"UP < {ANGLE_UP_THRESHOLD}°"
    )
    if args.headless:
        print(f"Mode: headless max_frames={args.max_frames or 'inf'}")
    else:
        print("Keys: q=quit, r=reset, s=skeleton toggle")
    print("=" * 60)

    model_path = ensure_pose_model(Path(__file__).resolve().parent / "models")
    options = mp_vision.PoseLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=str(model_path)),
        running_mode=mp_vision.RunningMode.VIDEO,
        num_poses=1,
        min_pose_detection_confidence=MIN_CONFIDENCE,
        min_pose_presence_confidence=MIN_CONFIDENCE,
        min_tracking_confidence=MIN_CONFIDENCE,
    )
    landmarker = mp_vision.PoseLandmarker.create_from_options(options)

    cap = cv2.VideoCapture(args.camera)
    if not cap.isOpened():
        print(f"ERROR: camera {args.camera} not available")
        raise SystemExit(1)

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)

    counter = RepCounter()
    show_skeleton = True
    start_time = time.time()

    csv_file = None
    csv_writer = None
    if CSV_LOG and not args.no_csv:
        log_dir = Path(__file__).resolve().parent / "logs"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_name = log_dir / f"webcam_{datetime.now():%Y%m%d_%H%M%S}.csv"
        csv_file = open(log_name, "w", newline="", encoding="utf-8")
        csv_writer = csv.writer(csv_file)
        csv_writer.writerow(["timestamp_ms", "angle", "state", "rep_count"])
        print(f"CSV log: {log_name}")

    frames = 0
    frames_with_pose = 0
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print("ERROR: no frame from camera")
                break

            frames += 1
            timestamp = time.time() - start_time
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = MpImage(image_format=ImageFormat.SRGB, data=frame_rgb)
            # VIDEO mode needs monotonically increasing ms timestamp.
            result = landmarker.detect_for_video(
                mp_image, int(timestamp * 1000)
            )

            angle = None
            if result.pose_landmarks:
                frames_with_pose += 1
                landmarks = result.pose_landmarks[0]
                angle = elbow_angle_from_landmarks(landmarks)
                if angle is not None and counter.process(angle, timestamp):
                    print(
                        f"  REP {counter.rep_count}! "
                        f"angle={angle:.1f}° t={timestamp:.1f}s"
                    )

            if csv_writer is not None and angle is not None:
                csv_writer.writerow(
                    [
                        int(timestamp * 1000),
                        f"{angle:.2f}",
                        counter.state,
                        counter.rep_count,
                    ]
                )

            if not args.headless:
                cv2.putText(
                    frame,
                    f"Reps: {counter.rep_count}",
                    (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    1.2,
                    (0, 255, 0),
                    3,
                )
                if angle is not None:
                    cv2.putText(
                        frame,
                        f"Angle: {angle:.1f} deg",
                        (10, 70),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.8,
                        (255, 255, 255),
                        2,
                    )
                cv2.putText(
                    frame,
                    f"State: {counter.state}",
                    (10, 105),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.7,
                    (200, 200, 200),
                    2,
                )
                if show_skeleton and result.pose_landmarks:
                    # Simple joint dots (no solutions drawing utils).
                    h, w = frame.shape[:2]
                    for lm in result.pose_landmarks[0]:
                        cx, cy = int(lm.x * w), int(lm.y * h)
                        cv2.circle(frame, (cx, cy), 2, (0, 255, 255), -1)

                cv2.imshow("FlowRep Webcam Rep-Counter", frame)
                key = cv2.waitKey(1) & 0xFF
                if key == ord("q"):
                    break
                if key == ord("r"):
                    counter.reset()
                    print("  [RESET]")
                if key == ord("s"):
                    show_skeleton = not show_skeleton

            if args.max_frames > 0 and frames >= args.max_frames:
                print(f"Reached max-frames={args.max_frames}")
                break
    finally:
        cap.release()
        if not args.headless:
            cv2.destroyAllWindows()
        landmarker.close()
        if csv_file is not None:
            csv_file.close()
        print(
            f"Session done. frames={frames} pose_frames={frames_with_pose} "
            f"reps={counter.rep_count}"
        )


if __name__ == "__main__":
    main()
