# Notification Navigation Matrix

The source of truth is `backend/notifications/serializers.py` (`_ROUTES`), which
resolves the destination from **(recipient role, reference_type)**. Companion:
`NOTIFICATION_TIMING_AND_NAVIGATION_AUDIT.md`. Nothing was committed.

**These columns are identical for every row below:**

- **Creation timestamp field:** `notifications.created_at`. It is stored as UTC
  wall-clock and returned as ISO 8601 with `+00:00`.
- **Relative-time expected result:** `Just now` (<1 min), `1 min ago`,
  `N mins ago`, `1 hour ago`, `N hours ago`, `1 day ago`, `N days ago`, then a
  date for 7+ days. It is recomputed client-side on fetch, refresh, foreground
  and every 30 s.
- **Target ID:** the notification's `reference_id`, when the producer set one.
- **Manual verification:** ⚪ **not performed** in this pass (see audit §8).
  It was verified by the live-DB backend suite and by widget tests with a real
  GoRouter.

**Legend:**

- **Backend:** ✅ route returned.
- **Flutter:** ✅ opens through the shared `NotificationNavigator`.
- **Test:**
  - **B** = asserted in `scripts/test_notifications.py`
  - **F** = tapped through in `test/notifications_test.dart`
  - **T** = timestamp/label asserted for this type (every type in the DB is
    covered by the timestamp checks)

**Access rule:**

- *Own list* = the destination's API returns only the caller's own records.
- *Participant check* = the target exists and the recipient is its farmer or
  doctor, or a conversation participant (`available:false` otherwise).
- *Active check* = the community post still exists and is active.

## Farmer
| Notification type | Destination | Route | Access rule | Backend | Flutter | Test |
|---|---|---|---|---|---|---|
| consultation (requested/accepted/rejected/rescheduled/started/completed/cancelled) | Find Vet → Consultations | `/farmer/find-vet/consultations` | Participant check + own list | ✅ | ✅ | B F T |
| consultation_payment (receipt updated, cash confirmed) | Consultations (receipt is in the consultation card) | `/farmer/find-vet/consultations` | Own list | ✅ | ✅ | B T |
| consultation_dispute | Consultations | `/farmer/find-vet/consultations` | Own list | ✅ | ✅ | T |
| prescription / follow_up | Consultations | `/farmer/find-vet/consultations` | Own list | ✅ | ✅ | T |
| conversation (new message) | Find Vet → Chats | `/farmer/find-vet/chats` | Participant check + own list | ✅ | ✅ | B F T |
| loan | Cost Mgmt → Loans | `/farmer/cost-management/loans` | Own list | ✅ | ✅ | B F T |
| expense | Cost Mgmt → Expenses | `/farmer/cost-management/expenses` | Own list | ✅ | ✅ | T |
| cashout (requested/approved/rejected) | Cost Management | `/farmer/cost-management` | Own list | ✅ | ✅ | T |
| feed_order (placed/status/delivered) | Feed Marketplace | `/farmer/feed-management/marketplace` | Own list | ✅ | ✅ | B F T |
| feed_stock / feed_low_stock / feed_daily_reminder / feed_stage_upcoming / feed | Feed Management | `/farmer/feed-management` | Own list | ✅ | ✅ | T |
| pharmacy_order (status) | Pharmacy marketplace | `/farmer/pharmacy` | Own list | ✅ | ✅ | B F T |
| worker | Labour | `/farmer/labor` | Own list | ✅ | ✅ | T |
| subscription_plan | Subscription | `/subscription` | Own subscription | ✅ | ✅ | B F T |
| community_post | Community post | `/community/post/{id}` | Active check | ✅ | ✅ | B F T |

## Doctor
| Notification type | Destination | Route | Access rule | Backend | Flutter | Test |
|---|---|---|---|---|---|---|
| consultation (new request, reschedule accepted/declined, cancellation) | Appointments / request queue | `/doctor/appointments` | Participant check + own list | ✅ | ✅ | B F T |
| consultation_dispute | Appointments | `/doctor/appointments` | Own list | ✅ | ✅ | T |
| consultation_payment (cash confirmed) | Earnings | `/doctor/earnings` | Own earnings | ✅ | ✅ | B F T |
| consultation_rating | Earnings (ratings feed) | `/doctor/earnings` | Own earnings | ✅ | ✅ | B F T |
| follow_up | Follow-ups | `/doctor/followups` | Own list | ✅ | ✅ | B F T |
| conversation (new message) | Messenger | `/doctor/messenger` | Participant check + own list | ✅ | ✅ | B F T |
| community_post | Community post | `/community/post/{id}` | Active check | ✅ | ✅ | F T |

## Pharmacy
| Notification type | Destination | Route | Access rule | Backend | Flutter | Test |
|---|---|---|---|---|---|---|
| pharmacy_order (new order) | Orders | `/pharmacy/orders` | Own orders | ✅ | ✅ | B F T |
| pharmacy_medicine (approved/rejected) | Catalogue | `/pharmacy/catalogue` | Own catalogue | ✅ | ✅ | T |
| admin_pharmacy (account action) | Profile | `/pharmacy/profile` | Own profile | ✅ | ✅ | T |
| community_post | Community post | `/community/post/{id}` | Active check | ✅ | ✅ | T |

*Entry point added:* `NotificationBellButton` in the pharmacy dashboard app bar.

## Delivery rider
| Notification type | Destination | Route | Access rule | Backend | Flutter | Test |
|---|---|---|---|---|---|---|
| delivery_order (assigned/completed) | Orders | `/delivery/orders` | Own deliveries | ✅ | ✅ | B F T |
| delivery_nearby | Orders | `/delivery/orders` | Own deliveries | ✅ | ✅ | T |
| delivery_payout | Earnings | `/delivery/earnings` | Own earnings | ✅ | ✅ | B F T |
| community_post | Community post | `/community/post/{id}` | Active check | ✅ | ✅ | T |

*Entry point added:* bell in the delivery dashboard app bar.

## Researcher
| Notification type | Destination | Route | Access rule | Backend | Flutter | Test |
|---|---|---|---|---|---|---|
| article (content decision) | Papers | `/research/papers` | Own papers | ✅ | ✅ | B F T |
| profile_change_application | Profile | `/research/profile` | Own profile | ✅ | ✅ | T |
| community_post | Community post | `/community/post/{id}` | Active check | ✅ | ✅ | T |

*Entry point added:* bell in `ResearchScaffold` (both layouts).

## Admin roles

**Applies to:** Super, Operations, Finance, Content, Research, Delivery,
Pharmacy, Doctor, Team, Feed, and Support.

An admin route is returned **only if the recipient's role can view that
module**, using the same `can_perform_action` that guards the screen's API.
Otherwise `navigation` is `null`.

*Entry point added:* bell in `AdminScaffold` (narrow and wide layouts) for
every admin role.

| Notification type | Destination | Route | Required permission | Backend | Flutter | Test |
|---|---|---|---|---|---|---|
| admin_approval_queue | Approval Queue | `/admin/approvals` | `approvals.view` (Ops/Super; **not** Finance) | ✅ | ✅ | B F T |
| admin_escalation | Oversight | `/admin/oversight` | `oversight.view` | ✅ | ✅ | T |
| support_ticket | Support | `/admin/support` | `support.view` | ✅ | ✅ | T |
| consultation_dispute | Doctors | `/admin/doctors` | `doctors.view` | ✅ | ✅ | T |
| delivery_order / delivery_payout | Delivery | `/admin/delivery` | `delivery.view` | ✅ | ✅ | B F T |
| pharmacy_order / pharmacy_medicine / admin_pharmacy | Pharmacy | `/admin/pharmacy` | `pharmacy.view` | ✅ | ✅ | T |
| article | Content | `/admin/content` | `articles.view` | ✅ | ✅ | T |
| profile_change_application | Content | `/admin/content` | `research.view` | ✅ | ✅ | T |
| community_moderation | Community | `/admin/community` | `community.view` | ✅ | ✅ | T |
| cashout (escalated) | Pending Cashout Requests | `/admin/cashouts/pending` | `cashouts.view` (Finance) | ✅ | ✅ | B F T |
| feed_order | Feed | `/admin/feed` | `feed-orders.view` | ✅ | ✅ | T |
| admin_shift (shift started/ended) | Team & Payroll | `/admin/payroll` | **Super Admin only** | ✅ | ✅ | B F T |
| admin_payment ("You have been paid") | My Earnings | `/admin/earnings` | Hourly admins (tier > 1) | ✅ | ✅ | T |

**Verified RBAC withholding (test B):** Finance Admin gets `null` for
`admin_approval_queue`, and Operations Admin gets `null` for `admin_shift`.

## No meaningful destination

`navigation: null`. The tap keeps the user in the center and shows the full
text; toasts get no **Open** action.

| Type | Recipient | Why |
|---|---|---|
| community_follow | any user | The follower isn't recorded on the notification, so there's no object to open. |
| community_moderation (author side) | post author | It has no `reference_id`; the actioned content may be hidden. |
| support_ticket (non-admin side) | ticket opener | No user-facing ticket screen exists. |
| farm | farmer | No live producer emits it. |
| any admin type the role can't view | that admin | RBAC: never routes to a screen the role would be refused. |

## Deleted / inaccessible targets

These cases return `available: false, route: null`, and Flutter shows
**"This item is no longer available."**:

- a consultation or conversation that no longer exists, or where the recipient
  is not a participant
- a community post that is no longer `active`

Verified in test B (another farmer's consultation, a removed post) and test F.
