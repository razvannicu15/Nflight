# Nflight

Portofel de bilete de îmbarcare pentru **Android**, în stil Material 3, **fără reclame și fără cont**.

## Funcții

- **Import bilete**: din PDF-ul trimis de companie, captură de ecran, poză, bilet tipărit (cameră) sau fișier `.pkpass`. Merge și din „Distribuie” / „Deschide cu” al oricărei aplicații.
- Citește codul standard IATA de pe bilet (PDF417, Aztec, QR): pasager, rezervare, zbor, rută, dată, loc, clasă, secvență, card de fidelitate. Biletele cu mai multe zboruri apar ca un card pe zbor.
- **Ecran pentru poartă**: codul mare, luminozitate maximă, ecranul nu se stinge, fără internet. Pasagerii de pe aceeași rezervare se parcurg cu swipe.
- **Notificări**: cu o zi înainte, cu 3 ore înainte și la îmbarcare (atingi și se deschide biletul).
- **Status live (opțional)**: întârziere, poartă, terminal, prin AeroDataBox cu cheia ta gratuită (Setări → Status live). Se verifică doar zborurile din următoarele 36 de ore.
- **Statistici**: zboruri, km, ore în aer, aeroporturi și țări, recorduri, geam sau culoar, top rute, companii și aeroporturi.
- **Aeroporturi**: ora locală și diferența față de tine (bază de date inclusă, offline).
- **Compensație UE 261**: calcul orientativ pentru întârziere sau anulare.
- Copie de siguranță JSON, temă luminoasă / întunecată.

## Build

Build-ul se face automat în **GitHub Actions** la fiecare push pe `main`; APK-ul apare în release-ul `latest`.

Pe PC: rulează **`Nflight.bat`** (de oriunde, chiar și de pe Desktop):

- `[1]` descarcă ultimul APK în `D:\Apps\Nflight\dist`
- `[2]` îl instalează pe telefon prin cablu USB (descarcă singur `adb` prima dată)
- `[4]` / `[5]` actualizează codul / build local, doar dacă ai Flutter

Toate build-urile sunt semnate cu aceeași cheie (`tool/debug.keystore`), deci un APK nou se instalează peste cel vechi fără să pierzi biletele.

Manual (cu Flutter instalat):

```bash
flutter create --platforms=android --org ro.noraz --project-name nflight .
flutter pub get
dart run tool/patch_platforms.dart
dart run flutter_launcher_icons
flutter build apk --release
```

Date aeroporturi: [mwgg/Airports](https://github.com/mwgg/Airports) (MIT).
