# Directional gP Shadow Rollout - 2026-07-27

## Ziel

Die gP-Profilzaehlung nutzt im Produktpfad weiterhin `abs(gP)`, damit sich
das Verhalten fuer Nutzer nicht aendert. Parallel dazu laeuft ein
signierter Shadow-Zaehler, der die Hauptbewegung und Rueckbewegung getrennt
behandelt. So koennen Doppelzaehlmuster gemessen werden, ohne die Live-Reps
zu veraendern.

## Aktiv in dieser Stufe

- `DirectionalGpShadow` beobachtet nur kalibrierte `ChosenSignal.gP`-Profile.
- Eine positive Hauptbewegung zaehlt genau einen Shadow-Rep.
- Die normale Gegenbewegung wird als Rueckbewegung verbraucht und nicht als
  zweiter Rep gewertet.
- Wiederholte qualifizierende Gegenrichtungszyklen ohne vorherige
  Hauptbewegung setzen `mountMismatchSuspected`.
- Template-Korrelation wird nur diagnostisch protokolliert.

## Bewusst noch nicht aktiv

- Der produktive Rep-Zaehler bleibt unveraendert.
- Es gibt keinen Fallback zwischen signierter und absoluter gP-Zaehlung.
- Die App zeigt noch keine Rekalibrierungswarnung.

## Hardware-Gate fuer die naechste Stufe

Vor einer Nutzer-Warnung oder einem produktiven Wechsel sollten echte
Sensorlaeufe mindestens diese Szenarien abdecken:

1. Normale Bizeps-Curls mit stabiler Montage.
2. Bewusst verdrehte oder verrutschte Montage.
3. Langsame, gueltige Wiederholungen.
4. Kurze oder schwache Wackler unterhalb der Rep-Guards.
5. Wechsel zwischen korrekter Montage und Mismatch nach Reconnect.

Erst wenn die Shadow-Diagnosen auf Hardware stabil sind, sollte die UI eine
Rekalibrierungsaufforderung anzeigen.
