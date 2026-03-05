# Core ML model hookup

The app now supports optional Core ML scoring for recommendations.

## Expected bundle artifact

Place compiled model in the app bundle with name:
- `MovieClass.mlmodel` (preferred)
- or `MovieTasteClassifier.mlmodel`

## Expected input feature names

- `genre_match`
- `rating_fit`
- `runtime_fit`
- `movie_rating`
- `movie_runtime`
- `user_avg_rating`
- `user_avg_runtime`
- `liked_count`
- `disliked_count`

## Input scale used in app

- `genre_match`, `rating_fit`, `runtime_fit`: binary `0/1`
- `movie_rating`, `user_avg_rating`: TMDB scale `0...10`
- `movie_runtime`, `user_avg_runtime`: minutes
- `liked_count`, `disliked_count`: integer counters

## Expected output

The app tries these outputs in order:
- `likeProbability` (Double)
- `targetProbability` (Double)
- `classProbability` dictionary with keys `"like"/"dislike"` or `"1"/"0"`
- `targetProbability` dictionary with keys `"like"/"dislike"` or `"1"/"0"`
- `target` label (`"like"`/`"dislike"` or `1`/`0`)

If no model is present (or schema mismatches), the app falls back to heuristic scoring.

## Online personalizer

The app also keeps a lightweight online logistic calibrator in `UserDefaults`.
- It learns from explicit like/dislike actions on device.
- Final recommendation score in app: `0.7 * baseModelScore + 0.3 * personalizerScore`.
