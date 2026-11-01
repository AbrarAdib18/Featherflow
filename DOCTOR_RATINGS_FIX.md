# Doctor ratings fix and dummy-data removal

## Problem

- **Ratings page said "0.0" above 7 reviews.** The headline on Earnings → Ratings read the
  stored `DoctorProfile.rating` while the star bars and review list read the actual ratings.
  The stored value was stale (0.00) because the data reached the database without going through
  the in-app rating flow (seed commands, then the local → Supabase merge).
- **The dashboard and profile mixed two sources.** They used the stored average (0.00) alongside
  a live count (7).
- **Fake consultations and ratings.** `seed_farmer_demo_data` and `seed_demo_data_for_phone`
  created consultations directly. They had fake 4–5★ ratings, the canned review "Very helpful,
  clear guidance on treatment." and scripted doctor chats. Those fake ratings counted towards
  real doctors' averages.
- **Fake profile in the app.** The Flutter `DoctorSession` started from a demo profile (4.7 from
  128 ratings) in `lib/features/doctor/data/doctor_demo_data.dart`.

## One definition of a doctor's rating

`backend/doctor/ratings.py`:

- **Rating** is the average of the 1–5 stars on the doctor's rated consultations.
- **Count** is the number of rated consultations.
- **Distribution** is the per-star counts.

How each surface uses it:

| Surface | Source |
|---|---|
| Doctor dashboard (`/api/doctor/dashboard/`: `profile` and `summary`) | Live `rating_summary` |
| Doctor profile (`/api/doctor/profile/`) | Live `rating_summary` |
| Ratings tab (`/api/doctor/earnings/`: `ratings` newest first, plus `rating_summary`) | Live. The app computes the headline from the same list it shows. |
| Farmer-facing vet lists / map | Stored `DoctorProfile.rating` |

The stored `DoctorProfile.rating` stays in sync in two ways:

- `refresh_stored_rating` runs on every in-app rating (both write paths in `consultations/views.py`).
- `manage.py recalculate_doctor_ratings` fixes it after any change made outside the app.

## App changes

- **Ratings tab:** the average, stars (with half stars), "N ratings" and bars all come from one
  list. With no ratings it shows "No ratings yet", not 0.0.
- **Profile:** shows `4.1 (7)`, or "No ratings yet".
- **Dashboard:** unchanged. It already hides the rating when there are none, and it now receives
  live values.
- **Demo data removed:** `doctor_demo_data.dart` is deleted. The session starts from an empty
  profile until `/api/doctor/dashboard/` loads.

## Dummy data removed

- **Seeds:** `seed_farmer_demo_data` and `seed_demo_data_for_phone` no longer create consultations,
  ratings or doctor chats. Their `--reset` still wipes the ones they made before.
  - `seed_consultation_demo_data` is unchanged. It books two *pending* requests through the real
    booking path and creates no ratings.
- **New command `remove_demo_consultations`** (dry run by default; `--apply`; optional
  `--farmer EMAIL`):
  - It finds consultations with **no case and no status history**. Every booking made in the app
    creates a case (`consultations/booking.py`), so a row with neither came from a seed.
  - It deletes those consultations together with their conversations and messages, in one
    transaction.

### Run on the shared Supabase DB (2026-11-02)

```
python manage.py remove_demo_consultations            # dry run: 13 consultations, 3 conversations, 13 messages
python manage.py remove_demo_consultations --apply
python manage.py recalculate_doctor_ratings
```

- **Deleted:** 13 seeded consultations (all from 2026-09-24 08:50–08:51, farmer
  `andrew26499@gmail.com`), including 4 fake ratings, plus 3 scripted conversations and their
  13 messages.
  - The farmer account and its other data were kept.
- **Kept:** the 10 real consultations, each with a case and status history.
- **Ratings now:**
  - `dr.samira.rahman`: 4.25 from 4 real ratings. Before, 0.00 was stored and 4.14 from 7
    (inflated) was live.
  - `dr.pending.kabir`: no ratings. Their only rating was fake.
  - `test@gmail.com`: 5.0 from 1.

On another database (for example a teammate's local copy), run the same three commands.

## Tests

- **Backend: `backend/scripts/test_doctor_ratings.py`** (new, 25 checks). Covers:
  - live values on the dashboard, profile and earnings even when the stored value is stale;
  - the recalc dry run and apply;
  - in-app rating refresh;
  - the doctor with no ratings;
  - the cleanup's dry run, apply and idempotency.
- **Backend: `test_dashboard_integrity_and_seed_idempotency.py`.** Checks that the seed creates no
  consultations, ratings or chat messages.
- **Flutter: `test/doctor_ratings_test.dart`** (new). Covers the Ratings tab, profile and
  dashboard with real payloads.
- **Flutter: `doctor_dashboard_profile_test.dart`.** Now loads an explicit payload instead of the
  demo profile.
- **Flutter: `doctor_consultation_queue_test.dart`.** Asserts the demo file is gone.

Backend suites were run against the **local** DB (the env override in the commented `.env`
lines), never against Supabase.
