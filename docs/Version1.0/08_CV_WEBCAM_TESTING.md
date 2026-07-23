# CV-05 — Webcam-Modus: PC-Testing ohne Android

> **Voraussetzung**: Doc 06 (Rep-Counter Winkel) abgeschlossen.
> **Ziel**: Pose Estimation mit PC-Webcam testen (ohne Android-Gerät).
> **Ergebnis**: Entwickler kann am PC die Kamera-Pipeline testen.
> **WICHTIG**: Dies ist ein DEVELOPMENT-Tool, kein Production-Feature.

---

## 1. Problemstellung

`flutter_pose_detection` unterstützt **nur Android und iOS**.
Für die Entwicklung am PC (Windows/Linux/macOS) braucht es einen Workaround.

### 1.1 Optionen

| Option | Vorteil | Nachteil |
|--------|---------|----------|
| A: Python-Script (MediaPipe) | Einfach, schnell, keine Flutter-Änderung | Separates Tool |
| B: Flutter Web + TensorFlow.js | Alles in Flutter | Komplex, langsam |
| C: Flutter Windows + OpenCV | Native | OpenCV-Setup aufwendig |

**Entscheidung**: **Option A** — Python-Script mit MediaPipe.

**Begründung**:
- MediaPipe ist die gleiche Engine wie `flutter_pose_detection`
- Python-Script ist in 30 Minuten einsatzbereit
- Liefert die gleichen Landmarks (33 Punkte)
- Kann als "Ground Truth" für die Flutter-Implementierung dienen
- Keine Änderung am Flutter-Code nötig

---

## 2. Python-Setup

### 2.1 Voraussetzungen

- Python 3.9+ installiert
- Webcam am PC angeschlossen
- `pip` verfügbar

### 2.2 Dependencies installieren

```bash
pip install mediapipe opencv-python numpy
```

**Fehlerbehandlung**:
- Falls `mediapipe` nicht installiert: `pip install mediapipe==0.10.14`
- Falls OpenCV-Fehler: `pip install opencv-python-headless`
- Auf Windows: Falls DLL-Fehler → Visual C++ Redistributable installieren

---

## 3. Python-Script: Webcam Rep-Counter

### 3.1 Neue Datei anlegen

**Datei**: `flowrep/tools/webcam_rep_counter.py` (NEUE DATEI)

**Ordner erstellen**: `flowrep/tools/`

```python
"""
FlowRep Webcam Rep-Counter — Development/Testing Tool.

Nutzt MediaPipe Pose Estimation + Webcam zum Zählen von Bicep Curls.
Dies ist das gleiche Verfahren wie in der Flutter-App (flutter_pose_detection),
aber als eigenständiges Python-Script für schnelles Testing am PC.

Verwendung:
    python tools/webcam_rep_counter.py

Steuerung:
    q = Beenden
    r = Rep-Counter zurücksetzen
    s = Skelett-Overlay an/aus

Ausgabe:
    - Live-Video mit Skelett-Overlay
    - Ellenbogen-Winkel in Echtzeit
    - Rep-Zähler
    - CSV-Log (optional)
"""

import cv2
import mediapipe as mp
import numpy as np
import time
import csv
from pathlib import Path
from datetime import datetime


# === KONFIGURATION ===
ANGLE_DOWN_THRESHOLD = 160.0  # Grad: Arm gestreckt
ANGLE_UP_THRESHOLD = 90.0    # Grad: Arm kontrahiert
MIN_REP_INTERVAL = 0.5       # Sekunden zwischen Reps
MAX_REP_DURATION = 5.0       # Maximale Rep-Dauer
MIN_CONFIDENCE = 0.5         # Mindest-Konfidenz für Landmarks
CAMERA_INDEX = 0             # 0 = Standard-Webcam
CSV_LOG = True               # CSV-Log schreiben


# === MEDIAPIPE SETUP ===
mp_pose = mp.solutions.pose
mp_drawing = mp.solutions.drawing_utils
mp_drawing_styles = mp.solutions.drawing_styles


def calculate_angle(a, b, c):
    """
    Berechnet den Winkel bei Punkt b (in Grad).
    
    Parameter:
        a: np.array [x, y] — z.B. Schulter
        b: np.array [x, y] — z.B. Ellenbogen (Scheitelpunkt)
        c: np.array [x, y] — z.B. Handgelenk
    
    Rückgabe:
        Winkel in Grad (0–180)
    
    Formel:
        BA = A - B
        BC = C - B
        Winkel = arccos( (BA · BC) / (|BA| * |BC|) )
    """
    ba = a - b
    bc = c - b
    
    dot = np.dot(ba, bc)
    mag_ba = np.linalg.norm(ba)
    mag_bc = np.linalg.norm(bc)
    
    if mag_ba < 1e-10 or mag_bc < 1e-10:
        return 0.0
    
    cos_angle = np.clip(dot / (mag_ba * mag_bc), -1.0, 1.0)
    angle_rad = np.arccos(cos_angle)
    angle_deg = np.degrees(angle_rad)
    
    return angle_deg


class RepCounter:
    """
    Winkel-basierter Rep-Counter (identisch zur Flutter-Implementierung).
    
    State Machine:
        WAITING → ARM_DOWN (Winkel > 160°)
        ARM_DOWN → ARM_UP (Winkel < 90°)
        ARM_UP → ARM_DOWN (Winkel > 160°) → REP!
    """
    
    WAITING = "waiting"
    ARM_DOWN = "arm_down"
    ARM_UP = "arm_up"
    
    def __init__(self):
        self.state = self.WAITING
        self.rep_count = 0
        self.last_rep_time = 0.0
        self.rep_start_time = 0.0
        self.history = []  # Für CSV-Log
    
    def process(self, angle, timestamp):
        """
        Verarbeitet einen Winkel-Wert.
        
        Parameter:
            angle: Ellenbogen-Winkel in Grad
            timestamp: Zeit in Sekunden
        
        Rückgabe:
            True wenn eine Rep gezählt wurde
        """
        if self.state == self.WAITING:
            if angle > ANGLE_DOWN_THRESHOLD:
                self.state = self.ARM_DOWN
            return False
        
        elif self.state == self.ARM_DOWN:
            if angle < ANGLE_UP_THRESHOLD:
                self.state = self.ARM_UP
                self.rep_start_time = timestamp
            return False
        
        elif self.state == self.ARM_UP:
            if angle > ANGLE_DOWN_THRESHOLD:
                # Timing prüfen
                time_since_last = timestamp - self.last_rep_time
                rep_duration = timestamp - self.rep_start_time
                
                if time_since_last < MIN_REP_INTERVAL:
                    self.state = self.ARM_DOWN
                    return False  # Zu schnell
                
                if rep_duration > MAX_REP_DURATION:
                    self.state = self.ARM_DOWN
                    return False  # Zu langsam
                
                # REP GEZÄHLT!
                self.rep_count += 1
                self.last_rep_time = timestamp
                self.state = self.ARM_DOWN
                self.history.append({
                    'rep': self.rep_count,
                    'timestamp': timestamp,
                    'duration': rep_duration,
                })
                return True
        
        return False
    
    def reset(self):
        self.state = self.WAITING
        self.rep_count = 0
        self.last_rep_time = 0.0
        self.rep_start_time = 0.0


def main():
    """Haupt-Schleife: Webcam → MediaPipe → Winkel → Rep-Counter."""
    
    print("=" * 60)
    print("FlowRep Webcam Rep-Counter")
    print("=" * 60)
    print(f"Schwellen: UNTEN > {ANGLE_DOWN_THRESHOLD}°, OBEN < {ANGLE_UP_THRESHOLD}°")
    print(f"Min. Rep-Intervall: {MIN_REP_INTERVAL}s")
    print(f"Max. Rep-Dauer: {MAX_REP_DURATION}s")
    print("-" * 60)
    print("Steuerung: q=Beenden, r=Reset, s=Skelett an/aus")
    print("=" * 60)
    
    # MediaPipe Pose initialisieren
    pose = mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,  # 0=lite, 1=full, 2=heavy
        smooth_landmarks=True,
        min_detection_confidence=MIN_CONFIDENCE,
        min_tracking_confidence=MIN_CONFIDENCE,
    )
    
    # Webcam öffnen
    cap = cv2.VideoCapture(CAMERA_INDEX)
    if not cap.isOpened():
        print(f"FEHLER: Kamera {CAMERA_INDEX} nicht verfügbar!")
        print("Versuche CAMERA_INDEX=1 oder prüfe die Webcam-Verbindung.")
        return
    
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    
    counter = RepCounter()
    show_skeleton = True
    start_time = time.time()
    
    # CSV-Log vorbereiten
    csv_file = None
    csv_writer = None
    if CSV_LOG:
        log_dir = Path("tools/logs")
        log_dir.mkdir(parents=True, exist_ok=True)
        log_name = log_dir / f"webcam_{datetime.now():%Y%m%d_%H%M%S}.csv"
        csv_file = open(log_name, 'w', newline='')
        csv_writer = csv.writer(csv_file)
        csv_writer.writerow(['timestamp_ms', 'angle', 'state', 'rep_count'])
        print(f"CSV-Log: {log_name}")
    
    try:
        while True:
            ret, frame = cap.read()
            if not ret:
                print("FEHLER: Kein Frame von der Kamera!")
                break
            
            timestamp = time.time() - start_time
            
            # Frame für MediaPipe vorbereiten
            frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            frame_rgb.flags.writeable = False
            results = pose.process(frame_rgb)
            frame_rgb.flags.writeable = True
            
            angle = None
            
            if results.pose_landmarks:
                landmarks = results.pose_landmarks.landmark
                
                # Rechte Seite: Schulter(12), Ellenbogen(14), Handgelenk(16)
                shoulder = landmarks[mp_pose.PoseLandmark.RIGHT_SHOULDER]
                elbow = landmarks[mp_pose.PoseLandmark.RIGHT_ELBOW]
                wrist = landmarks[mp_pose.PoseLandmark.RIGHT_WRIST]
                
                # Konfidenz prüfen
                if (shoulder.visibility >= MIN_CONFIDENCE and
                    elbow.visibility >= MIN_CONFIDENCE and
                    wrist.visibility >= MIN_CONFIDENCE):
                    
                    a = np.array([shoulder.x, shoulder.y])
                    b = np.array([elbow.x, elbow.y])
                    c = np.array([wrist.x, wrist.y])
                    
                    angle = calculate_angle(a, b, c)
                    
                    # Rep-Counter füttern
                    rep_counted = counter.process(angle, timestamp)
                    
                    if rep_counted:
                        print(f"  ✓ REP {counter.rep_count}! "
                              f"(Winkel: {angle:.1f}°, "
                              f"Zeit: {timestamp:.1f}s)")
                
                # Skelett zeichnen
                if show_skeleton:
                    mp_drawing.draw_landmarks(
                        frame,
                        results.pose_landmarks,
                        mp_pose.POSE_CONNECTIONS,
                        mp_drawing_styles.get_default_pose_landmarks_style(),
                    )
            
            # CSV-Log schreiben
            if csv_writer and angle is not None:
                csv_writer.writerow([
                    int(timestamp * 1000),
                    f"{angle:.2f}",
                    counter.state,
                    counter.rep_count,
                ])
            
            # HUD (Heads-Up Display) zeichnen
            hud_y = 30
            cv2.putText(frame, f"Reps: {counter.rep_count}",
                       (10, hud_y), cv2.FONT_HERSHEY_SIMPLEX,
                       1.2, (0, 255, 0), 3)
            hud_y += 40
            
            if angle is not None:
                color = (0, 255, 0) if angle < ANGLE_UP_THRESHOLD else \
                        (0, 165, 255) if angle > ANGLE_DOWN_THRESHOLD else \
                        (255, 255, 255)
                cv2.putText(frame, f"Winkel: {angle:.1f} deg",
                           (10, hud_y), cv2.FONT_HERSHEY_SIMPLEX,
                           0.8, color, 2)
                hud_y += 35
            
            cv2.putText(frame, f"State: {counter.state}",
                       (10, hud_y), cv2.FONT_HERSHEY_SIMPLEX,
                       0.7, (200, 200, 200), 2)
            hud_y += 30
            
            cv2.putText(frame, f"Zeit: {timestamp:.1f}s",
                       (10, hud_y), cv2.FONT_HERSHEY_SIMPLEX,
                       0.7, (200, 200, 200), 2)
            
            # Winkel-Balken (visuell)
            if angle is not None:
                bar_x = 550
                bar_height = int(angle / 180.0 * 400)
                cv2.rectangle(frame, (bar_x, 450 - bar_height),
                            (bar_x + 40, 450), (0, 255, 0), -1)
                cv2.putText(frame, f"{angle:.0f}",
                           (bar_x, 470), cv2.FONT_HERSHEY_SIMPLEX,
                           0.6, (255, 255, 255), 2)
            
            # Frame anzeigen
            cv2.imshow("FlowRep Webcam Rep-Counter", frame)
            
            # Tastatur-Input
            key = cv2.waitKey(1) & 0xFF
            if key == ord('q'):
                break
            elif key == ord('r'):
                counter.reset()
                print("  [RESET] Rep-Counter zurückgesetzt.")
            elif key == ord('s'):
                show_skeleton = not show_skeleton
                print(f"  [SKELETT] {'An' if show_skeleton else 'Aus'}")
    
    finally:
        cap.release()
        cv2.destroyAllWindows()
        pose.close()
        if csv_file:
            csv_file.close()
        
        print("\n" + "=" * 60)
        print(f"Session beendet. Reps: {counter.rep_count}")
        print(f"Dauer: {time.time() - start_time:.1f}s")
        if counter.history:
            durations = [h['duration'] for h in counter.history]
            print(f"Durchschn. Rep-Dauer: {np.mean(durations):.2f}s")
        print("=" * 60)


if __name__ == "__main__":
    main()
```

---

## 4. Script ausführen

### 4.1 Starten

```bash
cd flowrep
python tools/webcam_rep_counter.py
```

### 4.2 Erwartetes Verhalten

1. Webcam-Fenster öffnet sich
2. Skelett wird auf dem Körper angezeigt
3. Ellenbogen-Winkel wird in Echtzeit angezeigt
4. Bei Bicep Curls: Reps werden gezählt
5. CSV-Log wird in `tools/logs/` geschrieben

### 4.3 Testing-Szenario

1. **Starte das Script**
2. **Stelle dich vor die Webcam** (rechte Seite zur Kamera)
3. **Mache 5 Bicep Curls** (langsam und deutlich)
4. **Prüfe**: Zählt das Script korrekt?
5. **Teste Edge Cases**:
   - Schnelle Reps (< 0.5s) → sollten verworfen werden
   - Sehr langsame Reps (> 5s) → sollten verworfen werden
   - Arm nur halb bewegen → sollte NICHT zählen
   - Kamera kurz verdecken → sollte Zustand halten

---

## 5. CSV-Log als Test-Daten für Flutter

### 5.1 Format

```csv
timestamp_ms,angle,state,rep_count
0,172.34,arm_down,0
33,168.21,arm_down,0
66,145.67,arm_down,0
...
2000,45.12,arm_up,0
2500,170.89,arm_down,1
```

### 5.2 Nutzung in Flutter-Tests

Die CSV-Daten können als **Test-Vektor** für die Flutter-Implementierung
verwendet werden:

```dart
// In einem Flutter-Test:
final csvLines = File('tools/logs/webcam_test.csv').readAsLinesSync();
for (final line in csvLines.skip(1)) { // Header überspringen
  final parts = line.split(',');
  final timestampMs = int.parse(parts[0]);
  final angle = double.parse(parts[1]);
  
  counter.processAngle(
    elbowAngleDegrees: angle,
    timestampMs: timestampMs,
  );
}
// Dann: counter.repCount mit erwartetem Wert vergleichen
```

---

## 6. Vergleich: Python vs. Flutter

### 6.1 Validierungs-Test

1. Führe das Python-Script aus und mache 10 Reps
2. Notiere das Ergebnis (z.B. "10 Reps, Durchschnitt 2.1s")
3. Implementiere die gleiche Logik in Flutter (Doc 06)
4. Füttere die CSV-Daten in den Flutter-Counter
5. **Vergleiche**: Gleiche Rep-Anzahl? Gleiche Timing-Entscheidungen?

### 6.2 Erwartetes Ergebnis

- Rep-Anzahl: **identisch** (gleiche Schwellenwerte)
- Timing: **identisch** (gleiche Logik)
- Winkel: **±2° Toleranz** (MediaPipe-Version kann leicht variieren)

---

## 7. Commit

```bash
cd flowrep
git add tools/
git commit -m "feat(cv): Webcam Rep-Counter Python-Tool für PC-Testing (CV-05)"
git push
```

---

## 8. Checkliste

- [ ] Python 3.9+ installiert
- [ ] `pip install mediapipe opencv-python numpy` erfolgreich
- [ ] `tools/webcam_rep_counter.py` erstellt
- [ ] Script startet ohne Fehler
- [ ] Webcam-Bild wird angezeigt
- [ ] Skelett-Overlay funktioniert
- [ ] Bicep Curls werden gezählt
- [ ] CSV-Log wird geschrieben
- [ ] Reset (Taste 'r') funktioniert
- [ ] Commit + Push

---

## 9. Häufige Fehler

| Fehler | Ursache | Lösung |
|--------|---------|--------|
| `cv2.error: can't open camera` | Webcam nicht erkannt | CAMERA_INDEX ändern (0, 1, 2) |
| `ModuleNotFoundError: mediapipe` | Nicht installiert | `pip install mediapipe` |
| Winkel immer 0 | Landmarks nicht sichtbar | Rechte Seite zur Kamera drehen |
| Reps werden nicht gezählt | Schwellenwerte zu streng | ANGLE_UP_THRESHOLD auf 100 erhöhen |
| FPS < 10 | CPU zu langsam | model_complexity=0 setzen |
| DLL-Fehler (Windows) | VC++ Runtime fehlt | Visual C++ Redistributable installieren |
