# Profile photo — change from Edit Profile

## What was wrong

The signup wizard uploaded a profile photo, but **no post-signup screen let you
replace it**. The farmer "Edit farm profile" sheet had no photo field at all;
every role's profile header (`farmer`, `doctor`, `pharmacy`, `delivery`,
`researcher`, `admin`) showed the avatar read-only or as initials. There was
also no backend endpoint that would update `users.User.profile_photo_url` for a
signed-in user — the farmer profile `PATCH` ignores that field.

## What changed

### Backend — `POST` / `DELETE /api/auth/profile-photo/`

`backend/verification/views.py::profile_photo` — authenticated, role-agnostic
(the field lives on `users.User`, so one endpoint serves every role).

| Step | Detail |
|---|---|
| Auth | `IsAuthenticated` + `ProfilePhotoRateThrottle` (20/hour/user) |
| Accept | `multipart/form-data`, field `file` (or `image`) |
| Validate | shared `verification/uploads.py::validate_upload(images_only=True)` — extension ∈ {jpg, jpeg, png, webp}, advisory MIME (generic/`octet-stream` allowed — Flutter web sends that), **real magic bytes**, ≤ 5 MB (same limits as signup) |
| Store | `verification/documents.py::store()` → `private_media/registration/profile_photo/<uuid>.<ext>`, **never** under `MEDIA_URL` |
| Track | an unclaimed `SignupDocument` row is created by `store()`, then `claim()`ed to the user **inside one `transaction.atomic()`** with the `profile_photo_url` write |
| Roll back | if the DB step fails, the just-stored file **and** its row are deleted (`documents.delete_document`); the response is a 400 and the old photo is untouched |
| Old photo | removed (file + `SignupDocument`) **only after** the new one is committed — a failed swap always leaves the previous photo working |
| Response | `200 {"profile_photo_url": "<signed url>", "document": {...}}` |
| `DELETE` | clears `profile_photo_url` and removes the file/row; initials fall back |

The served URL is the existing signed, access-controlled endpoint
`/api/auth/registration-documents/<token>/`.

### Access control (unchanged policy, now exercised)

`verification/documents.py::can_access` — `profile_photo` is in
`_PUBLIC_TO_AUTHED`, so:

* **Owner** — always.
* **Any signed-in user** — yes (profile avatars are visible platform-wide).
* **Admin-panel users** — yes.
* **Anonymous** — only within the 2-hour unclaimed grace window (signup
  preview); a claimed photo is 401 for anonymous requests.
* **Licences / national ID / certificates / farm photos** — unchanged, still
  owner + admin only. The new endpoint only ever stores `kind='profile_photo'`.

### Frontend

`lib/core/widgets/profile_photo_field.dart` — one reusable widget:

1. Tap → `file_picker` (`FileType.custom` jpg/jpeg/png/webp, falls back to
   `FileType.image`). Works on web + Windows.
2. Client-side validation mirrors the server: extension, ≤ 5 MB, magic bytes
   (JPEG `FF D8 FF`, PNG signature, `RIFF…WEBP`).
3. **Immediate local preview** (`MemoryImage`) while uploading.
4. Uploads through `AuthService.updateProfilePhoto()` (multipart, JWT header,
   `MediaType` from the filename).
5. On success: the stored session's `AuthUser.profilePhotoUrl` is updated and
   `notifyListeners()` fires → avatars bound to the session refresh with no app
   restart. The old + new URLs are evicted from `PaintingBinding.imageCache`.
6. On failure: preview is dropped, the **old photo stays**, and a humanised
   message + **Try again** are shown (`ErrorStateView.humanize`).
7. Duplicate taps are ignored while `_busy`; the button shows "Uploading…".

Wired in:

| Role | Where |
|---|---|
| Farmer | profile header **and** the "Edit farm profile" sheet |
| Researcher | profile header |
| Admin (all admin roles) | profile "avatar section" (replaced the fake camera icon) |
| Doctor | dashboard welcome header (compact) |
| Delivery | Profile tab card |
| Pharmacy | dashboard app-bar leading (compact — pharmacy has no dedicated profile screen) |

`AuthUser` gained `profilePhotoUrl` (parsed from `me` / login) and
`AuthSession.toJson` persists it.

## Tests

`backend/scripts/test_profile_photo.py` — **58 checks** across 6 roles:
upload → URL set → row claimed → owner fetch → replace → old file removed →
exactly one row → cross-user isolation → avatar visible to other signed-in
users but not anonymously → invalid type / fake magic bytes / oversized / no
file all 400 → unauthenticated 401 → `DELETE` clears.

`test/profile_photo_test.dart` — widget smoke: initials fallback, "Change
profile photo" vs "Add profile photo", `editable:false`, `showLabel:false`.

## Production notes

Nothing to configure — this works the same in dev and prod. Files live in
`PRIVATE_MEDIA_ROOT` (`backend/private_media/`); for a multi-node deployment
point `PRIVATE_MEDIA_ROOT` at shared storage or swap
`verification.documents.private_storage` for an S3/GCS `Storage` backend
(the token/URL scheme is storage-agnostic).
