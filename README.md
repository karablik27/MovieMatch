# MovieMatch

MovieMatch — iOS-приложение с Tinder-like онбордингом и локальными рекомендациями фильмов.
Пользователь оценивает фильмы свайпами/кнопками лайк-дизлайк, а приложение персонализирует выдачу на устройстве.

Источники персонализации:

- каталог TMDB
- профиль вкуса в `UserDefaults`
- Core ML модель `MovieClass.mlmodel`
- онлайн-калибратор (локальная логистическая модель)

## Что реализовано

- Онбординг: 10 карточек фильмов (свайп влево/вправо).
- После онбординга открывается `TabView`:
  - `Все`
  - `Рекомендации`
  - `Понравились`
  - `Дизлайки`
- Лайк/дизлайк доступен на всех экранах списка.
- Повторный тап по активной реакции снимает оценку.
- В рекомендациях подходящие фильмы отмечаются `🔥`.
- Бесконечная подгрузка каталога с fallback на повторы (чтобы лента не пустела).

## Логика рекомендаций

1. Базовый скор:
   - скор от Core ML (если модель доступна)
   - эвристический скор по совпадению жанров, рейтинга и длительности
   - смесь: `0.6 * model + 0.4 * heuristic`
2. Онлайн-персоналайзер:
   - донастраивается по лайкам/дизлайкам пользователя
   - хранится локально в `UserDefaults`
3. Финальный скор:
   - `0.7 * base + 0.3 * personalizer`

## Data layer

- `Movie`: `id`, `title`, `genres`, `voteAverage`, `runtime`, `posterPath`
- `TMDBClient` использует:
  - `/movie/popular`
  - `/movie/{id}` (детали: `runtime`, `genres`, `posterPath`)

## Что сохраняется в UserDefaults

- `likedMovieIDs`
- `dislikedMovieIDs`
- `seenMovieIDs`
- счётчики жанров лайков
- средние значения рейтинга/длительности + число сэмплов
- веса/смещение/количество обновлений онлайн-калибратора

## Структура проекта

```text
MovieMatch/
  Features/
    OnboardingSwipeView.swift
    CatalogView.swift
    RecommendationsView.swift
    LikedMoviesView.swift
    DislikedMoviesView.swift
    MovieGridCard.swift
    MainTabView.swift
  Models/
    Movie.swift
  Network/
    TMDBClient.swift
    TMDBConfiguration.swift
  Storage/
    TasteStore.swift
  ML/
    MovieClass.mlmodel
    CoreMLScorer.swift
    OnlineCalibrator.swift
```

## Требования

- Xcode 26+
- Deployment target в проекте: `iOS 26.0`
- TMDB API credentials

## Запуск

1. Открой `MovieMatch.xcodeproj` в Xcode.
2. Проверь/заполни TMDB ключи в `MovieMatch/Network/TMDBConfiguration.swift`.
3. Запусти схему `MovieMatch` на симуляторе или устройстве.

Пример CLI сборки:

```bash
xcodebuild -project MovieMatch.xcodeproj \
  -scheme MovieMatch \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```

## Важно по безопасности

TMDB ключи нельзя хранить в публичном репозитории.
Если ключи были засвечены, перевыпусти их в TMDB и обнови локальную конфигурацию.

## Демо-сценарий

1. Пользователь свайпает 10 фильмов в онбординге.
2. Открывается основной интерфейс с вкладками.
3. Пользователь ставит лайки/дизлайки в любых вкладках.
4. Вкладка рекомендаций ранжирует фильмы по персональному скору.

## Автор

Карабельников Степан
