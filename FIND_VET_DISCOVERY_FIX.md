# Find Vet — Doctor Discovery Fix

Nothing in this work was committed.

## 1. Symptom

Farmer → Find Vet showed no doctors, despite eligible doctors existing on the
platform. The screen rendered its **empty state**, not an error — so it looked
like "no vets exist" rather than "something is broken".

## 2. Reproduction (before the fix)

| Field | Value |
|---|---|
| Farmer account | `farmer.rashed@example.com` (seeded, active) |
| Doctor account | `dr.samira.rahman@example.com` (seeded, labelled "active") |
| Doctor role / account_status | `doctor` / `active` |
| Doctor `DoctorProfile.is_verified` | **`False`** ← the problem |
| Doctor `is_available` / `availability_status` | `True` / `available` |
| Doctor consultation mode | `both` |
| Doctor specialty / fee | `Avian Medicine` / `900.00` |
| Request URL | `GET /api/consultations/vets/` |
| Query parameters | *(none — the default, unfiltered list)* |
| HTTP status | **200** (not an error) |
| Response body | `{"doctors": [], "summary": {"nearby_doctors": 0, "active_clinics": 0, "available_now": 0}}` |
| Flutter parsing/state | Parsed fine; `_doctors` empty, `_error == null` |
| Rendered result | Empty state: "no vets match" |

A DB-wide dump confirmed the scope: **all 7 `DoctorProfile` rows had
`is_verified = False`** — including both seeded demo doctors.

## 3. Path traced

```text
DoctorProfile row (is_verified=False)
  → consultations/views.py:vets() queryset .filter(..., is_verified=True)   ← excluded here
  → _doctor_row() serializer                                (never reached)
  → 200 {"doctors": []}
  → VetDiscoveryService.discover()                          (parsed correctly)
  → DiscoverVetsTab._load() → _doctors = []                 (no error raised)
  → empty-state branch rendered
```

## 4. Root cause

**Two layers. The application code was correct; the database state was not.**

### Proximate cause
`consultations/views.py:vets()` requires `is_verified=True` (correct, and
deliberate — an unverified doctor may use their own dashboard but is not yet
bookable). No doctor in the database satisfied it.

### Actual defect — the thing that kept de-verifying doctors

`backend/scripts/test_admin_panel.py` (the shared admin suite) contained:

```python
vd = DoctorProfile.objects.filter(is_verified=True).select_related('user').first()
```

It picked **whatever verified doctor happened to exist in the whole database** —
in practice the seeded demo doctor — and then suspended her as part of its
"low tier suspends verified doctor → approval queue" test.
`api/admin_approvals.py:_do_suspend()` sets `is_verified = False` and
`is_available = False` on that profile.

The suite already had `_make_test_doctor()` — a dedicated throwaway doctor that
force-sets `is_verified=True` on every call — but it was only used as a
last-resort fallback when *no* verified doctor existed anywhere.

So: **every run of the admin test suite silently destroyed farmer-facing doctor
discovery**, and nothing detected it, because every consultation suite builds
its own doctor and therefore stayed green.

### Evidence

**Immutable audit trail** (`activity_logs`) — four separate suspensions of the
seeded demo doctor, all by `adminpaneltest+*` accounts, reason `e2e queue test`:

```text
2026-09-28 00:06 | doctors | suspend | Suspend (via approval) | by=adminpaneltest+ops@featherflow.dev | e2e queue test
2026-09-27 23:52 | doctors | suspend | Suspend (via approval) | by=adminpaneltest+ops@featherflow.dev | e2e queue test
2026-09-27 23:51 | doctors | suspend | Suspend (via approval) | by=adminpaneltest+ops@featherflow.dev | e2e queue test
2026-09-26 08:37 | doctors | suspend | Suspend (via approval) | by=adminpaneltest+ops@featherflow.dev | e2e queue test
```

**Controlled before/after experiment** (causation, not correlation):

```text
BEFORE test suite: is_verified=True
--- ran scripts/test_admin_panel.py ---
AFTER  test suite: is_verified=False, is_available=False
```

## 5. Fix

`backend/scripts/test_admin_panel.py` now always uses its own throwaway doctor:

```python
vd = _make_test_doctor()
```

Every assertion in that block is unchanged — the test still queues a suspend,
still rejects self-approval, still verifies the doctor ends up suspended. It is
now *deterministic* (no dependence on ambient DB state) and *self-healing*
(`_make_test_doctor()` re-asserts `is_verified=True` each run) rather than
destructive to shared demo data.

Verified after the fix:

```text
BEFORE suite: demo doctor is_verified=True
--- ran scripts/test_admin_panel.py (62 passed, 1 pre-existing unrelated failure) ---
  ok  suspend verified doctor -> 202 queued
  ok  doctor now suspended
AFTER suite:  demo doctor is_verified=True   | throwaway test doctor is_verified=False
```

Data restored with `manage.py seed_platform_demo` (idempotent; it already sets
`is_verified: True` for the active demo doctor — the seed was never the bug).

## 6. Authoritative "discoverable doctor" rule

A doctor is discoverable in Find Vet when **all** of these hold
(`consultations/views.py:vets()`):

| Condition | Field |
|---|---|
| Account is active (not suspended/pending/banned) | `user.account_status == 'active'` |
| Holds the doctor role | `user.user_roles.role.name == 'doctor'` |
| A doctor profile exists | `DoctorProfile` row present |
| Admin verification approved | `DoctorProfile.is_verified is True` |

**Deliberately *not* part of the default rule:**

- `is_available` / `availability_status` — applied **only** when the caller
  passes `?available=true`. The default list intentionally includes doctors who
  have future availability but are not free at this exact minute.
- Any availability-slot requirement — `booking_options` reports
  `requires_availability: false`, i.e. booking is not slot-gated by current
  product policy.
- Distance — only applied when the caller supplies coordinates *and*
  `max_distance_km`.

Optional filters (each verified to work alone and combined): `search` (name /
specialty / focus area / clinic / address, case-insensitive), `mode`,
`specialty`, `available`, `emergency`, `verified`, `max_fee`, `min_rating`,
`max_distance_km` + `latitude`/`longitude`.

## 7. Verification after the fix

```text
GET /api/consultations/vets/                  -> 200, 1 doctor  (Dr. Samira Rahman, fee 900, available)
GET /api/consultations/vets/?search=Samira    -> 200, 1 doctor
GET /api/consultations/vets/?search=zzzznomatch -> 200, 0 doctors (empty list, not an error)
GET /api/consultations/vets/?mode=online      -> 200, 1 doctor
GET /api/consultations/vets/?available=true   -> 200, 1 doctor
GET /api/consultations/vets/?specialty=Avian  -> 200, 1 doctor
GET /api/consultations/vets/?max_fee=500      -> 200, 0 doctors (fee is 900 — correctly excluded)
GET /api/consultations/vets/<id>/             -> 200 (includes availability_slots)
GET /api/consultations/vets/<id>/booking-options/ -> 200 (farms, slot_minutes=30, requires_availability=false)
```

## 8. Frontend — inspected, no change required

`DiscoverVetsTab` (`lib/features/farmer/presentation/widgets/discover_vets_tab.dart`)
already distinguishes the three states correctly and in the right order:

```dart
else if (_error != null)      _ErrorCard(message: _error!, onRetry: _load)
else if (_doctors.isEmpty)    <empty state>
```

with `_loading`, `_error`, and a working **Retry**. The file's own header comment
records that a previous bare `catch (_) {}` (which *did* make failures look like
emptiness) was already fixed. No mock doctors, hard-coded cards, or dummy
fallback exist in this path — and none were added.

## 9. Regression protection added

`backend/scripts/test_find_vet_discovery.py` (new, **38 checks, all passing**) —
the suite that was missing. It asserts eligibility rules, search, every filter
alone and combined, card/detail payload shape, that no private document fields
leak, access control, and — critically — that **the seeded demo doctor is
actually discoverable by the seeded demo farmer**, which is the exact scenario
that silently broke.

**Negative control** (proving the guard is not a vacuous pass): with the bug
re-introduced, the suite fails on precisely those checks, and passes again once
restored:

```text
(demo doctor de-verified)  -> 36 passed, 2 failed
  FAIL the seeded demo doctor is discoverable by the seeded demo farmer
  FAIL seeded demo doctor is verified + active
(restored)                 -> 38 passed, 0 failed
```
