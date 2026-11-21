# MediCheck · Aplicación Flutter

Aplicación para pacientes y cuidadores. Consulte el [README principal](../README.md) y el [manual técnico](../docs/manual_tecnico.md).

```bash
flutter pub get
flutter run -d chrome                                    # web (API en http://localhost:3000)
flutter run                                              # emulador Android (API en http://10.0.2.2:3000)
flutter run --dart-define=API_URL=http://192.168.1.10:3000   # celular físico en la misma red
flutter test                                             # pruebas unitarias y de widgets
flutter build apk --release --dart-define=API_URL=https://mi-api.onrender.com
```

> En Windows, si la compilación falla por rutas largas, ubique el proyecto en una carpeta corta (por ejemplo `C:\dev\medicheck`).
