# MonoPlayer

Локальный умный аудиоплеер для iPhone: импорт файлов из «Файлов», автоматический поиск
метаданных, HD-обложек (iTunes Search API) и синхронизированных текстов (LRCLIB).
Дизайн-система — **Graphite** (раздел 6 ТЗ).

- Swift 6, SwiftUI, SwiftData, AVFoundation, MediaPlayer — без сторонних зависимостей
- Минимальная iOS 17, Liquid Glass и нижний аксессуар таб-бара на iOS 26+ (при сборке на Xcode 26+)
- Только iPhone, портретная ориентация

## Сборка без Мака (Windows): GitHub Actions + Sideloadly

Нужны: аккаунт GitHub, iPhone с кабелем, обычный Apple ID.

1. **Загрузите проект на GitHub.** Создайте репозиторий на github.com (публичный — минуты
   сборки бесплатны без лимита; приватный — в пределах бесплатной квоты) и загрузите
   содержимое этой папки (`project.yml`, `MonoPlayer/`, `MonoPlayerTests/`, `.github/`…)
   в его корень — через GitHub Desktop или `git push`.
2. **Дождитесь сборки.** Вкладка **Actions** → запуск **Build IPA** (стартует сам после
   загрузки, или вручную кнопкой *Run workflow*). Занимает ~5–10 минут.
3. **Скачайте IPA.** Каждая сборка публикуется в **Releases**; последняя всегда доступна
   по прямой ссылке без входа в аккаунт:
   `https://github.com/<владелец>/<репозиторий>/releases/latest/download/MonoPlayer.ipa`.
   Запасной путь — завершённый запуск в Actions → раздел **Artifacts** → `MonoPlayer-ipa`
   (zip, нужен вход в GitHub).
   Если сборка упала — там же лежит `build-log`; строки с `error:` видны прямо в логе шага
   *Build for device*.
4. **Установите на iPhone через [Sideloadly](https://sideloadly.io):**
   - на Windows нужны iTunes и iCloud в версии **с сайта Apple** (не из Microsoft Store) —
     Sideloadly использует их драйверы;
   - подключите iPhone кабелем, нажмите «Доверять этому компьютеру»;
   - перетащите `MonoPlayer.ipa` в Sideloadly, введите свой Apple ID и нажмите **Start**;
   - на iPhone: Настройки → Конфиденциальность и безопасность → **Режим разработчика** →
     включить (iPhone перезагрузится); затем Настройки → Основные → VPN и управление
     устройством → ваш Apple ID → **Доверять**.

Ограничения бесплатного Apple ID: приложение работает **7 дней** (потом повторите шаг 4 —
медиатека сохранится), не больше 3 таких приложений одновременно. С платным
Apple Developer Program ($99/год) срок — год, плюс доступен TestFlight.

## Сборка на Mac

Нужен Mac с **Xcode 16** или новее. На Xcode 26+ включаются Liquid Glass и мини-плеер
в нижнем аксессуаре таб-бара; на Xcode 16 эти места собираются в варианте для iOS 17–25
(проверка `#if compiler(>=6.2)`).

```bash
brew install xcodegen
cd MonoPlayer
xcodegen generate
open MonoPlayer.xcodeproj
```

Затем в Xcode: таргет **MonoPlayer → Signing & Capabilities → Team** — выберите свою команду
(подойдёт бесплатный Apple ID). Если bundle id `com.example.monoplayer` занят — замените
его в `project.yml` и перегенерируйте проект.

Запуск: схема **MonoPlayer**, устройство — iPhone (⌘R). Тесты — ⌘U.

> Ползунок громкости и кнопка AirPlay — системные контролы, на симуляторе они не
> отображаются. Экран блокировки и Dynamic Island лучше проверять на реальном устройстве.

### Без XcodeGen

1. Xcode → File → New → Project → iOS App (SwiftUI, Storage: None), имя `MonoPlayer`.
2. Удалите сгенерированные `ContentView.swift`, `MonoPlayerApp.swift`, `Assets.xcassets`.
3. Перетащите папку `MonoPlayer/` из этого репозитория в проект (Create groups).
4. Build Settings: **Swift Language Version = 6**, **Default Actor Isolation = nonisolated**
   (в новых проектах Xcode 26 по умолчанию стоит MainActor — код рассчитан на nonisolated),
   iOS Deployment Target = 17.0.
5. Signing & Capabilities → **+ Background Modes → Audio, AirPlay, and Picture in Picture**.
6. Info → Document Types: добавьте `public.audio` (Role: Viewer, Handler rank: Alternate),
   чтобы приложение появилось в меню «Поделиться» / «Открыть в…».

## Структура

```
.github/workflows/  build-ipa.yml — облачная сборка неподписанного IPA + тесты
MonoPlayer/
├── App/            MonoPlayerApp (SwiftData, тема), ContentView (TabView + мини-плеер),
│                   AppRouter (вкладки, стек медиатеки, переходы из плеера)
├── Models/         Track (@Model), LyricLine, LibraryIndex (альбомы и артисты из треков)
├── Services/       AudioPlayerManager, FileImportService, MetadataEnricherActor,
│                   ITunesSearchService, MetadataSources (Deezer, MusicBrainz, Cover Art Archive),
│                   LyricsService (LRCLIB + lyrics.ovh, LRCParser), VideoService (клипы, YouTube)
├── Utilities/      FilenameSanitizer, ArtworkPalette, TimeFormatting
├── DesignSystem/   Theme (токены Graphite), GlassModifiers (Liquid Glass / Material)
├── Views/
│   ├── Library/    LibraryView (разделы, песни), AlbumsView, ArtistsView, VideosView,
│   │               TrackRowView, SearchView, EditTrackView (ручной выбор обложки и текста)
│   ├── Player/     MiniPlayerView, FullPlayerView, ScrubberView,
│   │               NowPlayingBackground, SyncedLyricsView
│   ├── Components/ ArtworkView (+ ArtworkLoader), MediaCards (альбом, артист, клип)
│   └── Settings/   SettingsView
└── Resources/      Assets.xcassets (иконка: светлая, тёмная, tinted)
MonoPlayerTests/    Swift Testing: санитайзер имён, LRC-парсер, сопоставление iTunes
```

## Как работает пайплайн

1. **Импорт** (`FileImportService`) — файл копируется в `Documents/Tracks/{UUID}.ext`,
   название сразу берётся из имени файла через `FilenameSanitizer`, трек появляется в
   медиатеке и может играть немедленно.
2. **Обогащение** (`EnrichmentCoordinator` → `MetadataEnricherActor`) — по одному треку:
   встроенные теги → iTunes → Deezer → MusicBrainz/Cover Art Archive (по нескольким вариантам
   названия: без «feat.», «Remastered», скобок) → палитра обложки → текст: LRCLIB `/api/get`,
   затем `/api/search` с выбором записи по длительности (±3 с — иначе тайминги разъедутся),
   запасной обычный текст — lyrics.ovh. Ручные правки (`metadataLocked`) автопоиск не трогает.
   Актор не трогает SwiftData: он возвращает `EnrichmentResult`, который применяется к
   модели на главном акторе.
3. **Статусы:** `.completed` — есть обложка и текст; `.partial` — чего-то не нашлось;
   `.failed` — сеть недоступна и обложки нет. Прерванные задачи подхватываются при
   следующем запуске; повторить поиск можно из контекстного меню трека.

## Отличия от ТЗ

- `AVPlayer` с собственной очередью вместо `AVQueuePlayer` — так проще реализовать
  «назад», «играть следующим» и удаление из очереди.
- В модель `Track` добавлено поле `paletteHex` (цвета обложки для фона Now Playing),
  в `EnrichmentStatus` — `.partial` (упоминается в шаге 5 ТЗ).
- Добавлены вкладка «Поиск», экран правки сведений о треке, очередь и настройки темы.
