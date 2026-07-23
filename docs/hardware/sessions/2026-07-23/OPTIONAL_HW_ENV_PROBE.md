# Optional HW / Env Probe — 2026-07-23

> Automatisierter Agent-Lauf. Keine erfundenen Motion-Passes.

DEVICE
- adb: 55j7xkiffixsyhxg product=amber_eea model=21081111RG ONLINE
- package installed: com.flowrep.flowrep (pm path OK)
- App launch via monkey: Events injected 1; ProfileInstaller for flowrep
- Background HOME + am start: Activity brought to front (no FATAL in filtered log)
- M5 / Serial ports: none listed via Win32_SerialPort → IMU motion HW not attached this run
- Operator body motion (curls/wiggle/15min gym): NOT available in automated agent session

B* STATUS (this run)
- B1 Drehen/Dummy signal: DEFERRED — needs handheld motion + stream
- B2 Re-Calib clean-install: DEFERRED — needs interactive clean install + calib wizard
- B3 App-Hintergrund lang: PARTIAL — short HOME/resume without crash; long HW still open; code P1-2 + lifecycle unit exists
- B4 G5/G6 Curl vs Wiggle device DoD: DEFERRED — needs arm motion + M5
- B5 _useNewPipeline: remains false (policy)
- B6 G8 Langzeit/Drift: DEFERRED — long session + motion
- B7 15-min crash-free: DEFERRED — only short launch smoke; no 15-min operator session
- B8 Gym session no tools: DEFERRED — human gym session
- B9 Guided Calib 5-reps physical: DEFERRED — needs M5 + motion; wizard UI already code-complete

D1 device NPU live
- Phone online; live pose NPU not exercised end-to-end without camera permission UI + user posing
- Code soft-fail path unit-covered; mark D1 device still [~]

D3 webcam
- OpenCV VideoCapture(0) open True, frame shape (576,1024,3)
- pure logic: tools/test_webcam_logic.py 4 tests OK
- headless: python webcam_rep_counter.py --headless --max-frames 25 --no-csv
  → Session done. frames=25 pose_frames=0 reps=0
  (pipeline green; no person in frame expected in agent desk setup)

D4 Android emulator
- emulator -list-avds: empty / no AVD configured for this lab
- Soft-fail empty-camera unit covers 0-camera case
- Full VirtualScene checklist DEFERRED env

Evidence files under this directory.
