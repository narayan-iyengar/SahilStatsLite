#!/usr/bin/env python3
"""
SahilStats Game Footage Analyzer
Runs old game recordings through the current Skynet tracking pipeline
(YOLO v8n + action center + deadband + PID sim) and outputs metrics
to help tune Kp, deadband, and confidence thresholds.

Usage:
  python3 analyze.py /path/to/game.mov
  python3 analyze.py /path/to/game.mov --output annotated.mp4  # save annotated video
  python3 analyze.py /path/to/game.mov --kp-sweep              # sweep Kp 0.8-3.0
  python3 analyze.py /path/to/game.mov --fps 15                # match app AI frame rate

Output metrics:
  - Detection rate (% frames with players found)
  - Tracking stability (std dev of action center X)
  - Whip count (sudden large jumps in action center)
  - Gimbal command frequency at different Kp values
  - Recommended Kp based on smoothness score
"""

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO

# ── Config matching the iOS app ────────────────────────────────────────────────

AI_FRAME_SIZE  = (640, 360)   # Same as RecordingManager downscale
CONFIDENCE     = 0.35          # YOLOv8n confidence threshold (same as YOLODetector.swift)
DEADBAND       = 0.03          # 3% — same as AutoZoomManager
BALL_AHEAD_THRESHOLD = 0.15   # 15% — ball fast-break threshold
PERSON_CLASS   = 0             # COCO class 0 = person
COURT_Y_MIN    = 0.10          # Approximate court bounds (normalized)
COURT_Y_MAX    = 0.80

# ── Simulation ─────────────────────────────────────────────────────────────────

def weighted_action_center(boxes, scores):
    """Weighted centroid of detected players — mirrors PersonClassifier logic."""
    if len(boxes) == 0:
        return 0.5, 0.5

    total_w = 0.0
    wx, wy  = 0.0, 0.0

    for box, score in zip(boxes, scores):
        x1, y1, x2, y2 = box
        cx = (x1 + x2) / 2
        cy = (y1 + y2) / 2
        w  = (x2 - x1) * (y2 - y1) * score   # area × confidence = weight
        wx += cx * w
        wy += cy * w
        total_w += w

    return (wx / total_w, wy / total_w) if total_w > 0 else (0.5, 0.5)


def simulate_pid(action_centers, kp, deadband=DEADBAND, max_vel=0.8):
    """Simulate PID gimbal velocity commands for a series of action centers."""
    velocities  = []
    whips       = []
    prev_vel    = 0.0

    for cx, _ in action_centers:
        error = cx - 0.5
        if abs(error) <= deadband:
            vel = 0.0
        else:
            vel = max(-max_vel, min(max_vel, kp * error))

        velocities.append(vel)
        delta = abs(vel - prev_vel)
        whips.append(delta > 0.3)   # "whip" = velocity change > 0.3 rad/s in one frame
        prev_vel = vel

    return velocities, whips


def smoothness_score(velocities, whips):
    """0-100 score: higher = smoother. Penalises whips and high velocity variance."""
    if not velocities:
        return 0
    whip_rate  = sum(whips) / len(whips)
    vel_std    = float(np.std(velocities))
    return max(0, 100 - whip_rate * 60 - vel_std * 40)


# ── Main Analysis ──────────────────────────────────────────────────────────────

def analyze(video_path: str, output_path: str | None, fps_target: int, kp_sweep: bool):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"ERROR: Cannot open {video_path}")
        sys.exit(1)

    src_fps    = cap.get(cv2.CAP_PROP_FPS) or 30
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    frame_skip = max(1, round(src_fps / fps_target))
    duration_s = total_frames / src_fps

    print(f"\n{'='*60}")
    print(f"  SahilStats Footage Analyzer")
    print(f"{'='*60}")
    print(f"  File     : {Path(video_path).name}")
    print(f"  Duration : {duration_s:.0f}s  ({src_fps:.0f}fps source → {fps_target}fps analysis)")
    print(f"  Frames   : {total_frames} total, analysing every {frame_skip}th")
    print(f"{'='*60}\n")

    model = YOLO("yolov8n.pt")   # downloads if not cached (~6MB)

    # Video writer for annotated output
    writer = None
    if output_path:
        orig_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        orig_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        writer = cv2.VideoWriter(
            output_path,
            cv2.VideoWriter_fourcc(*"mp4v"),
            fps_target,
            (orig_w, orig_h)
        )

    action_centers   = []   # (cx, cy) per analysed frame
    detection_counts = []   # player count per frame
    frame_idx        = 0
    analysed         = 0

    print("  Analysing frames", end="", flush=True)

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        frame_idx += 1
        if frame_idx % frame_skip != 0:
            continue

        analysed += 1
        if analysed % 30 == 0:
            print(".", end="", flush=True)

        # Downscale for YOLO (matches iOS pipeline)
        small = cv2.resize(frame, AI_FRAME_SIZE)
        h_s, w_s = small.shape[:2]

        results = model(small, classes=[PERSON_CLASS], conf=CONFIDENCE, verbose=False)
        boxes_norm, scores = [], []

        for r in results:
            for box in r.boxes:
                x1, y1, x2, y2 = box.xyxy[0].tolist()
                # Normalize to 0-1
                nx1, ny1 = x1 / w_s, y1 / h_s
                nx2, ny2 = x2 / w_s, y2 / h_s
                cy_feet  = ny2   # feet = bottom of box

                # Court bounds filter (rough — no AR calibration in offline mode)
                if cy_feet < COURT_Y_MIN or ny1 > COURT_Y_MAX:
                    continue
                # Foreground filter
                if (ny2 - ny1) > 0.50:
                    continue

                boxes_norm.append([nx1, ny1, nx2, ny2])
                scores.append(float(box.conf[0]))

        detection_counts.append(len(boxes_norm))
        cx, cy = weighted_action_center(boxes_norm, scores)
        action_centers.append((cx, cy))

        # Annotate frame if writing output
        if writer and boxes_norm:
            orig_h_f, orig_w_f = frame.shape[:2]
            sx = orig_w_f / w_s
            sy = orig_h_f / h_s
            for box, score in zip(boxes_norm, scores):
                x1 = int(box[0] * w_s * sx)
                y1 = int(box[1] * h_s * sy)
                x2 = int(box[2] * w_s * sx)
                y2 = int(box[3] * h_s * sy)
                cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 165, 255), 2)

            # Action center marker
            acx = int(cx * orig_w_f)
            acy = int(cy * orig_h_f)
            cv2.circle(frame, (acx, acy), 18, (0, 0, 255), -1)
            cv2.circle(frame, (orig_w_f // 2, acy), 6, (255, 255, 255), -1)  # frame center

            writer.write(frame)

    cap.release()
    if writer:
        writer.release()

    print(f"\n\n  Analysed {analysed} frames.\n")

    # ── Metrics ────────────────────────────────────────────────────────────────

    if not action_centers:
        print("  No frames analysed. Check the video path.")
        return

    xs = [c[0] for c in action_centers]
    detection_rate  = sum(1 for d in detection_counts if d > 0) / len(detection_counts)
    avg_players     = sum(detection_counts) / len(detection_counts)
    center_std      = float(np.std(xs))
    center_mean_err = float(abs(np.mean(xs) - 0.5))   # how far off center on average

    print(f"{'='*60}")
    print(f"  TRACKING METRICS")
    print(f"{'='*60}")
    print(f"  Detection rate  : {detection_rate*100:.1f}% of frames had players")
    print(f"  Avg players/frame: {avg_players:.1f}")
    print(f"  Action center std: {center_std:.3f}  (lower = more stable)")
    print(f"  Mean off-center  : {center_mean_err:.3f}  (lower = better framing)")

    # ── PID Sweep ──────────────────────────────────────────────────────────────

    kp_values = [0.8, 1.0, 1.2, 1.4, 1.6, 2.0, 2.4, 3.0] if kp_sweep else [1.6]

    print(f"\n{'='*60}")
    print(f"  PID SIMULATION (deadband={DEADBAND}, max_vel=0.8 rad/s)")
    print(f"{'='*60}")
    print(f"  {'Kp':>5}  {'Smoothness':>10}  {'Whips':>6}  {'Vel Std':>8}  {'Rec':>4}")
    print(f"  {'-'*45}")

    best_score = -1
    best_kp    = 1.6

    for kp in kp_values:
        vels, whips = simulate_pid(action_centers, kp)
        score       = smoothness_score(vels, whips)
        whip_count  = sum(whips)
        vel_std     = float(np.std(vels))
        rec         = "◀" if score > best_score else ""
        if score > best_score:
            best_score = score
            best_kp    = kp
        print(f"  {kp:>5.1f}  {score:>10.1f}  {whip_count:>6}  {vel_std:>8.3f}  {rec}")

    print(f"\n  Recommended Kp: {best_kp}  (smoothness score: {best_score:.1f}/100)")

    print(f"\n{'='*60}")
    print(f"  TUNING NOTES")
    print(f"{'='*60}")

    if detection_rate < 0.5:
        print(f"  ⚠️  Detection rate {detection_rate*100:.0f}% is low.")
        print(f"     → Camera angle may be too low (players occlude each other)")
        print(f"     → Try raising tripod height before the next game")
    if center_std > 0.15:
        print(f"  ⚠️  Action center std {center_std:.3f} is high — camera was jumping around.")
        print(f"     → Reduce Kp or increase deadband")
    if best_kp != 1.6:
        print(f"  📐 Current app Kp=1.6, recommended Kp={best_kp}")
        print(f"     → Update GimbalTrackingManager.swift: private let Kp: Double = {best_kp}")
    else:
        print(f"  ✅  Current Kp=1.6 appears optimal for this footage")

    if output_path:
        print(f"\n  Annotated video saved to: {output_path}")

    print(f"\n{'='*60}\n")


# ── Entry point ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="SahilStats footage analyzer")
    ap.add_argument("video",       help="Path to game recording (.mov or .mp4)")
    ap.add_argument("--output",    help="Save annotated video to this path", default=None)
    ap.add_argument("--fps",       help="Analysis frame rate (default 15)", type=int, default=15)
    ap.add_argument("--kp-sweep",  help="Sweep Kp 0.8-3.0 to find best value",
                    action="store_true")
    args = ap.parse_args()

    analyze(args.video, args.output, args.fps, args.kp_sweep)
