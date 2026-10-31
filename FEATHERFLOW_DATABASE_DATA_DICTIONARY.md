# FEATHERFLOW Database Data Dictionary

Generated from Django model introspection (live code at HEAD + working tree). Sensitivity column is a heuristic by field name; verify manually. Tables listed as `managed=False` are owned by the SQL schema files (featherflow_schema.sql + *_extension.sql), not Django migrations.

## Index

| App | Model | Table | Managed | Fields | FKs |
|---|---|---|---|---|---|
| articles | Article | `articles` | False | 21 | 1 |
| articles | ArticleAuthor | `article_authors` | False | 4 | 2 |
| audit | ActivityLog | `activity_logs` | False | 14 | 1 |
| audit | AdminApprovalQueue | `admin_approval_queue` | False | 15 | 2 |
| audit | AdminEscalation | `admin_escalations` | False | 14 | 3 |
| audit | AdminPanelRecord | `backend_admin_records` | False | 6 | 0 |
| audit | SecurityFlag | `backend_admin_records` | True | 6 | 0 |
| audit | SupportTicket | `support_tickets` | False | 16 | 3 |
| audit | SupportTicketReply | `support_ticket_replies` | False | 7 | 2 |
| billing | PaymentIntent | `billing_payment_intents` | True | 21 | 1 |
| billing | WebhookEvent | `billing_webhook_events` | True | 5 | 1 |
| chatbot | ChatbotMessage | `backend_admin_records` | True | 6 | 0 |
| chatbot | ChatbotSession | `backend_admin_records` | True | 6 | 0 |
| community | Bookmark | `bookmarks` | False | 5 | 1 |
| community | Comment | `comments` | False | 11 | 3 |
| community | CommunityMember | `backend_admin_records` | True | 6 | 0 |
| community | CommunityMute | `community_mutes` | False | 8 | 2 |
| community | CommunityReport | `backend_admin_records` | True | 6 | 0 |
| community | Follow | `follows` | False | 3 | 2 |
| community | PollVote | `poll_votes` | False | 5 | 2 |
| community | Post | `posts` | False | 19 | 2 |
| community | PostCategory | `post_categories` | False | 3 | 0 |
| community | Reaction | `reactions` | False | 6 | 1 |
| community | Report | `reports` | False | 9 | 2 |
| community | Repost | `post_reposts` | False | 5 | 2 |
| community | UserBlock | `user_blocks` | False | 4 | 2 |
| consultations | Consultation | `consultations` | False | 22 | 2 |
| consultations | ConsultationDispute | `consultation_disputes` | False | 12 | 3 |
| delivery | DeliveryAttendance | `delivery_attendance` | False | 7 | 1 |
| delivery | DeliveryEarning | `delivery_earnings` | False | 10 | 2 |
| delivery | DeliveryOrder | `delivery_orders` | False | 21 | 1 |
| delivery | DeliveryQueueRecord | `backend_admin_records` | True | 6 | 0 |
| disease | Disease | `backend_admin_records` | True | 6 | 0 |
| disease | DiseaseScan | `backend_admin_records` | True | 6 | 0 |
| doctor | AvailabilitySlot | `doctor_availability_slots` | False | 8 | 1 |
| doctor | CaseDetail | `consultation_case_details` | False | 18 | 2 |
| doctor | ClinicalPrescription | `clinical_prescriptions` | False | 10 | 2 |
| doctor | ConsultationNote | `consultation_notes` | False | 10 | 2 |
| doctor | ConsultationStatusHistory | `consultation_status_history` | False | 7 | 2 |
| doctor | Conversation | `conversations` | False | 8 | 4 |
| doctor | DoctorEarning | `doctor_earnings` | False | 9 | 2 |
| doctor | FollowUp | `follow_ups` | False | 9 | 2 |
| doctor | Message | `messages` | False | 8 | 2 |
| doctor | PayoutRequest | `doctor_payout_requests` | False | 6 | 1 |
| doctor | PrescriptionItem | `clinical_prescription_items` | False | 6 | 1 |
| expenses | Expense | `expenses` | False | 19 | 4 |
| expenses | ExpenseCategory | `expense_categories` | False | 5 | 0 |
| expenses | Loan | `loans` | False | 17 | 3 |
| expenses | LoanInstallment | `loan_installments` | False | 8 | 1 |
| expenses | Revenue | `revenues` | False | 12 | 3 |
| expenses | RevenueSource | `revenue_sources` | False | 3 | 0 |
| expenses | TaxRecord | `tax_records` | False | 14 | 1 |
| farms | Farm | `farms` | False | 13 | 1 |
| farms | Flock | `flocks` | False | 13 | 2 |
| farms | FlockEvent | `flock_events` | False | 9 | 2 |
| farms | Shed | `sheds` | False | 8 | 1 |
| feed | FeedConsumption | `feed_consumption` | False | 8 | 3 |
| feed | FeedSchedule | `feed_schedules` | False | 7 | 2 |
| feed | FeedStock | `feed_stock` | False | 9 | 2 |
| feed | FeedStockMovement | `feed_stock_movements` | False | 10 | 3 |
| feed | FeedType | `feed_types` | False | 6 | 0 |
| feed | FeedingGuideline | `feeding_guidelines` | False | 12 | 0 |
| feed_catalogue | FeedCompany | `feed_companies` | False | 17 | 1 |
| feed_catalogue | FeedProduct | `feed_products` | False | 22 | 3 |
| messaging | Conversation | `backend_admin_records` | True | 6 | 0 |
| messaging | Message | `backend_admin_records` | True | 6 | 0 |
| ml | DiseaseRef | `diseases` | False | 10 | 0 |
| ml | DiseaseScan | `disease_scans` | False | 13 | 2 |
| notifications | Notification | `notifications` | False | 9 | 1 |
| payments | Payment | `payments` | False | 16 | 1 |
| pharmacy | PharmacyAppeal | `pharmacy_appeals` | False | 12 | 2 |
| pharmacy | PharmacyCommission | `pharmacy_commissions` | False | 7 | 1 |
| pharmacy | PharmacyEmployee | `pharmacy_employees` | False | 12 | 2 |
| pharmacy | PharmacyExpiryAlert | `pharmacy_expiry_alerts` | False | 7 | 2 |
| pharmacy | PharmacyMedicine | `pharmacy_catalogue_medicines` | False | 28 | 1 |
| pharmacy | PharmacyMedicineRecord | `backend_admin_records` | True | 6 | 0 |
| pharmacy | PharmacyOrganization | `backend_admin_records` | True | 6 | 0 |
| pharmacy | PharmacySale | `pharmacy_sales` | False | 8 | 1 |
| pharmacy | PharmacySettlement | `pharmacy_settlements` | False | 13 | 2 |
| pharmacy | PharmacySupplier | `pharmacy_suppliers` | False | 12 | 1 |
| profiles | AdminPayment | `admin_payments` | False | 19 | 3 |
| profiles | AdminProfile | `admin_profiles` | False | 33 | 5 |
| profiles | AdminShift | `admin_shifts` | False | 15 | 2 |
| profiles | DeliveryProfile | `delivery_profiles` | False | 20 | 2 |
| profiles | DoctorProfile | `doctor_profiles` | False | 30 | 2 |
| profiles | FarmerProfile | `farmer_profiles` | False | 21 | 2 |
| profiles | FeedOwnerProfile | `feed_owner_profiles` | False | 10 | 2 |
| profiles | PharmacyOrganization | `pharmacy_organizations` | False | 16 | 2 |
| profiles | ResearcherProfile | `researcher_profiles` | False | 26 | 2 |
| research | ArticleTag | `article_tags` | False | 2 | 2 |
| research | ArticleVersionSnapshot | `article_version_snapshots` | False | 7 | 2 |
| research | ProfileChangeApplication | `profile_change_applications` | False | 12 | 2 |
| research | ResearchTag | `research_tags` | False | 5 | 0 |
| subscriptions | FeatureUsage | `feature_usage` | False | 8 | 1 |
| subscriptions | Subscription | `subscriptions` | False | 9 | 2 |
| subscriptions | SubscriptionPlan | `subscription_plans` | False | 10 | 0 |
| tax | TaxPayment | `tax_payments` | True | 10 | 1 |
| tax | TaxProfile | `tax_profiles` | True | 15 | 1 |
| token_blacklist | BlacklistedToken | `token_blacklist_blacklistedtoken` | True | 3 | 1 |
| token_blacklist | OutstandingToken | `token_blacklist_outstandingtoken` | True | 6 | 1 |
| users | Role | `roles` | False | 11 | 0 |
| users | User | `users` | False | 27 | 0 |
| users | UserRole | `user_roles` | False | 4 | 3 |
| verification | SignupDocument | `signup_documents` | True | 13 | 2 |
| workers | Worker | `workers` | False | 10 | 1 |
| workers | WorkerAttendance | `worker_attendance` | False | 8 | 1 |
| workers | WorkerPayment | `worker_payments` | False | 9 | 1 |
| workers | WorkerTask | `worker_tasks` | False | 10 | 2 |

## Models

### articles.Article

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_views.py, views.py
- **Tests referencing the model:** test_admin_row_builder_performance.py, test_articles_feed.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `articles` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** published_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `author` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `title` | CharField | False |  | yes |  |  |
| `abstract` | TextField | False |  | yes |  |  |
| `body` | TextField | False |  | yes |  |  |
| `content_type` | CharField | True |  | no |  |  |
| `category` | CharField | True |  | no |  |  |
| `keywords` | JSONField | False | list | no |  |  |
| `references_list` | JSONField | False | list | no |  |  |
| `pdf_url` | TextField | True |  | no |  | Uploaded file/URL |
| `farmer_summary` | TextField | True |  | no |  |  |
| `status` | CharField | False | draft | no |  |  |
| `version` | IntegerField | False | 1 | no |  |  |
| `read_count` | IntegerField | False | 0 | no |  |  |
| `co_authors` | JSONField | False | list | no |  |  |
| `content_details` | JSONField | False | dict | no |  |  |
| `review_notes` | TextField | True |  | no |  |  |
| `is_featured` | BooleanField | False | False | no |  |  |
| `published_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### articles.ArticleAuthor

- **Used by APIs/views (source modules referencing the model):** — (not referenced by any view module)
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `article_authors` (managed=False)
- **Primary key:** `pk`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `article` | ForeignKey | False |  | yes | articles.Article / CASCADE |  |
| `user` | ForeignKey | False |  | yes | users.User / CASCADE |  |
| `author_role` | CharField | False |  | yes |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### audit.ActivityLog

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_approvals.py, admin_cashouts.py, admin_extra.py, admin_farmer_loans.py, admin_finance.py, admin_pharmacy.py, admin_security.py, admin_shifts.py, admin_subscriptions.py, admin_support.py, admin_views.py, appeal_views.py, catalogue_views.py …
- **Tests referencing the model:** test_admin_panel.py, test_pharmacy_admin.py, test_pharmacy_medicine_edit.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `activity_logs` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `module` | CharField | False |  | yes |  |  |
| `action` | CharField | False |  | yes |  |  |
| `action_type` | CharField | True |  | no |  |  |
| `entity_type` | CharField | True |  | no |  |  |
| `entity_id` | UUIDField | True |  | no |  |  |
| `old_values` | JSONField | True |  | no |  |  |
| `new_values` | JSONField | True |  | no |  |  |
| `reason` | TextField | True |  | no |  |  |
| `ip_address` | CharField | True |  | no |  | PII/Location |
| `user_agent` | TextField | True |  | no |  |  |
| `request_id` | UUIDField | True |  | no |  |  |
| `created_at` | DateTimeField | True | now | no |  |  |

### audit.AdminApprovalQueue

- **Used by APIs/views (source modules referencing the model):** admin_approvals.py, admin_extra.py, admin_views.py
- **Tests referencing the model:** test_admin_panel.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `admin_approval_queue` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** requested_by, approved_by, created_at, decided_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `requested_by` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `approved_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `action_type` | CharField | False |  | yes |  |  |
| `module_affected` | CharField | False |  | yes |  |  |
| `target_id` | UUIDField | True |  | no |  |  |
| `target_type` | CharField | True |  | no |  |  |
| `request_data` | JSONField | False | dict | no |  |  |
| `status` | CharField | False | pending | no |  |  |
| `required_tier` | SmallIntegerField | False | 2 | no |  |  |
| `reason` | TextField | True |  | no |  |  |
| `rejection_reason` | TextField | True |  | no |  |  |
| `result_ref_id` | UUIDField | True |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `decided_at` | DateTimeField | True |  | no |  |  |

### audit.AdminEscalation

- **Used by APIs/views (source modules referencing the model):** admin_extra.py, admin_support.py, admin_views.py, appeal_views.py, services.py
- **Tests referencing the model:** test_subscription_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `admin_escalations` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** raised_by, created_at, resolved_at, resolved_by

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `raised_by` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `assigned_to` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `module` | CharField | False |  | yes |  |  |
| `target_id` | UUIDField | True |  | no |  |  |
| `target_type` | CharField | True |  | no |  |  |
| `priority` | CharField | False | medium | no |  |  |
| `subject` | CharField | False |  | yes |  |  |
| `detail` | TextField | True |  | no |  |  |
| `status` | CharField | False | open | no |  |  |
| `resolution` | TextField | True |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `resolved_at` | DateTimeField | True |  | no |  |  |
| `resolved_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |

### audit.AdminPanelRecord

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_approvals.py, admin_base.py, admin_extra.py, admin_pharmacy.py, admin_security.py, admin_subscriptions.py, admin_views.py, catalogue_views.py, dashboard_views.py, documents.py, farmer_views.py, order_admin_views.py, services.py …
- **Tests referencing the model:** test_admin_panel.py, test_delivery_multi_active.py, test_delivery_proof_and_earnings.py, test_feed_catalogue.py, test_feed_marketplace_ux.py, test_feed_order_delivery.py, test_pharmacy_admin.py, test_private_documents.py, tests.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** unique_admin_module_record
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### audit.SecurityFlag

- **Used by APIs/views (source modules referencing the model):** admin.py, views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### audit.SupportTicket

- **Used by APIs/views (source modules referencing the model):** admin_extra.py, admin_support.py, admin_views.py, appeal_views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `support_tickets` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** raised_by, created_at, updated_at, resolved_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `ticket_number` | CharField | False |  | yes |  |  |
| `raised_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `raised_by_name` | CharField | True |  | no |  |  |
| `assigned_to` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `category` | CharField | False | general | no |  |  |
| `subject` | CharField | False |  | yes |  |  |
| `description` | TextField | True |  | no |  |  |
| `priority` | CharField | False | medium | no |  |  |
| `status` | CharField | False | open | no |  |  |
| `is_escalated` | BooleanField | False | False | no |  | Location |
| `escalation` | ForeignKey | True |  | no | audit.AdminEscalation / SET_NULL | Location |
| `resolution` | TextField | True |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |
| `resolved_at` | DateTimeField | True |  | no |  |  |

### audit.SupportTicketReply

- **Used by APIs/views (source modules referencing the model):** admin_support.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `support_ticket_replies` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `ticket` | ForeignKey | False |  | yes | audit.SupportTicket / CASCADE |  |
| `author` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `author_role` | CharField | True |  | no |  |  |
| `body` | TextField | False |  | yes |  |  |
| `is_internal` | BooleanField | False | False | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### billing.PaymentIntent

- **Used by APIs/views (source modules referencing the model):** services.py, views.py, webhooks.py
- **Tests referencing the model:** test_labour_payment.py, test_subscription_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `billing_payment_intents` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** billing_intent_idempotency_unique, billing_intent_status_valid, billing_intent_payment_method_valid, billing_intent_amount_positive
- **Indexes:** billing_pay_user_id_81de55_idx
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at, confirmed_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / CASCADE |  |
| `target_type` | CharField | False | subscription | no |  |  |
| `plan_id` | IntegerField | False | 0 | no |  |  |
| `plan_code` | CharField | False |  | no |  |  |
| `plan_name` | CharField | False |  | no |  |  |
| `interval` | CharField | False | month | no |  |  |
| `amount` | DecimalField | False |  | yes |  | Financial |
| `currency` | CharField | False | BDT | no |  |  |
| `payment_method` | CharField | False |  | no |  | Financial |
| `provider` | CharField | False | dev | no |  |  |
| `status` | CharField | False | created | no |  |  |
| `provider_ref` | CharField | False |  | no |  |  |
| `idempotency_key` | CharField | False |  | no |  |  |
| `failure_reason` | CharField | False |  | no |  |  |
| `payment_id` | UUIDField | True |  | no |  | Financial |
| `subscription_id` | UUIDField | True |  | no |  |  |
| `metadata` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |
| `confirmed_at` | DateTimeField | True |  | no |  |  |

### billing.WebhookEvent

- **Used by APIs/views (source modules referencing the model):** services.py, webhooks.py
- **Tests referencing the model:** test_subscription_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `billing_webhook_events` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** billing_webhook_event_unique
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** received_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `provider` | CharField | False |  | yes |  |  |
| `event_id` | CharField | False |  | yes |  |  |
| `intent` | ForeignKey | True |  | no | billing.PaymentIntent / SET_NULL |  |
| `received_at` | DateTimeField | False |  | no |  |  |

### chatbot.ChatbotMessage

- **Used by APIs/views (source modules referencing the model):** admin.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### chatbot.ChatbotSession

- **Used by APIs/views (source modules referencing the model):** admin.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### community.Bookmark

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** test_community_feed_performance.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `bookmarks` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['user', 'target_id', 'target_type']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `target_id` | UUIDField | False |  | yes |  |  |
| `target_type` | CharField | False |  | yes |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### community.Comment

- **Used by APIs/views (source modules referencing the model):** admin_views.py, views.py
- **Tests referencing the model:** test_admin_row_builder_performance.py, test_community.py, test_community_feed_performance.py, test_dashboard_integrity_and_seed_idempotency.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `comments` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `post` | ForeignKey | False |  | yes | community.Post / DO_NOTHING |  |
| `author` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `parent_comment` | ForeignKey | True |  | no | community.Comment / DO_NOTHING |  |
| `content` | TextField | False |  | yes |  |  |
| `is_anonymous` | BooleanField | False | False | no |  |  |
| `is_best_answer` | BooleanField | True | False | no |  |  |
| `status` | CharField | True | active | no |  |  |
| `hidden_reason` | TextField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### community.CommunityMember

- **Used by APIs/views (source modules referencing the model):** admin.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### community.CommunityMute

- **Used by APIs/views (source modules referencing the model):** admin_views.py, permissions.py
- **Tests referencing the model:** test_community.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `community_mutes` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** muted_by, expires_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `muted_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `reason` | TextField | True |  | no |  |  |
| `is_active` | BooleanField | False | True | no |  |  |
| `expires_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### community.CommunityReport

- **Used by APIs/views (source modules referencing the model):** admin.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### community.Follow

- **Used by APIs/views (source modules referencing the model):** content.py, prescription_pdf.py, views.py
- **Tests referencing the model:** test_community.py, test_community_feed_performance.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `follows` (managed=False)
- **Primary key:** `pk`
- **Unique constraints:** ['follower', 'following']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `follower` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `following` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### community.PollVote

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** test_community.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `poll_votes` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['post', 'user']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `post` | ForeignKey | False |  | yes | community.Post / DO_NOTHING |  |
| `user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `option_indexes` | JSONField | False | list | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### community.Post

- **Used by APIs/views (source modules referencing the model):** admin_views.py, permissions.py, services.py, views.py
- **Tests referencing the model:** test_admin_row_builder_performance.py, test_community.py, test_community_feed_performance.py, test_dashboard_integrity_and_seed_idempotency.py, test_delivery_proof_and_earnings.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `posts` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `author` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `post_type` | CharField | False | text | no |  |  |
| `title` | TextField | True |  | no |  |  |
| `content` | TextField | False |  | yes |  |  |
| `media_urls` | JSONField | True | list | no |  | Uploaded file/URL |
| `tags` | JSONField | False | list | no |  |  |
| `mentions` | JSONField | False | list | no |  |  |
| `poll_options` | JSONField | True |  | no |  |  |
| `poll_multi` | BooleanField | False | False | no |  |  |
| `category` | ForeignKey | True |  | no | community.PostCategory / DO_NOTHING |  |
| `is_anonymous` | BooleanField | True | False | no |  |  |
| `is_pinned` | BooleanField | True | False | no |  |  |
| `is_official` | BooleanField | True | False | no |  |  |
| `is_trending` | BooleanField | False | False | no |  |  |
| `status` | CharField | True | active | no |  |  |
| `hidden_reason` | TextField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### community.PostCategory

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `post_categories` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | AutoField | False |  | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### community.Reaction

- **Used by APIs/views (source modules referencing the model):** admin_views.py, views.py
- **Tests referencing the model:** test_community.py, test_community_feed_performance.py, test_dashboard_integrity_and_seed_idempotency.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `reactions` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['user', 'target_id', 'target_type']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `target_id` | UUIDField | False |  | yes |  |  |
| `target_type` | CharField | False |  | yes |  |  |
| `reaction_type` | CharField | False | helpful | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### community.Report

- **Used by APIs/views (source modules referencing the model):** admin_views.py, content.py, cost_views.py, views.py
- **Tests referencing the model:** test_admin_row_builder_performance.py, test_community.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `reports` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** reviewed_by, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `reporter` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `target_id` | UUIDField | False |  | yes |  |  |
| `target_type` | CharField | False |  | yes |  |  |
| `reason` | TextField | False |  | yes |  |  |
| `status` | CharField | False | pending | no |  |  |
| `reviewed_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### community.Repost

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** test_community.py, test_community_feed_performance.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `post_reposts` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['post', 'user']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `post` | ForeignKey | False |  | yes | community.Post / DO_NOTHING |  |
| `user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `comment` | TextField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### community.UserBlock

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** test_community.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `user_blocks` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['blocker', 'blocked']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `blocker` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `blocked` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### consultations.Consultation

- **Used by APIs/views (source modules referencing the model):** admin_views.py, booking.py, dashboard_views.py, metrics.py, payments.py, prescription_pdf.py, views.py, workflow.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_consultation_chat_access.py, test_consultation_transitions_and_receipts.py, test_dashboard_integrity_and_seed_idempotency.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `consultations` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** rated_at, video_started_at, video_ended_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farmer` | ForeignKey | False |  | yes | users.User / PROTECT |  |
| `doctor` | ForeignKey | False |  | yes | users.User / PROTECT |  |
| `scan_id` | UUIDField | True |  | no |  |  |
| `mode` | CharField | False |  | yes |  |  |
| `status` | CharField | False | requested | no |  |  |
| `urgency_level` | CharField | False | routine | no |  |  |
| `appointment_date` | DateField | False |  | yes |  |  |
| `appointment_time` | TimeField | False |  | yes |  |  |
| `consultation_fee` | DecimalField | True |  | no |  |  |
| `payment_id` | UUIDField | True |  | no |  | Financial |
| `rating` | PositiveSmallIntegerField | True |  | no |  |  |
| `review_text` | TextField | False |  | no |  |  |
| `rated_at` | DateTimeField | True |  | no |  |  |
| `proposed_date` | DateField | True |  | no |  |  |
| `proposed_time` | TimeField | True |  | no |  |  |
| `decision_reason` | TextField | True |  | no |  |  |
| `video_room` | CharField | True |  | no |  |  |
| `video_started_at` | DateTimeField | True |  | no |  |  |
| `video_ended_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### consultations.ConsultationDispute

- **Used by APIs/views (source modules referencing the model):** admin_views.py, metrics.py, views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `consultation_disputes` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** raised_by, reviewed_by, resolved_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `consultation` | ForeignKey | False |  | yes | consultations.Consultation / DO_NOTHING |  |
| `raised_by` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `raised_role` | CharField | False |  | yes |  |  |
| `category` | CharField | False |  | yes |  |  |
| `description` | TextField | False |  | yes |  |  |
| `status` | CharField | False | open | no |  |  |
| `resolution` | TextField | True |  | no |  |  |
| `reviewed_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `resolved_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### delivery.DeliveryAttendance

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `delivery_attendance` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['delivery_person', 'attendance_date']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `delivery_person` | ForeignKey | False |  | yes | profiles.DeliveryProfile / DO_NOTHING |  |
| `attendance_date` | DateField | False |  | yes |  |  |
| `check_in_time` | DateTimeField | True |  | no |  |  |
| `check_out_time` | DateTimeField | True |  | no |  |  |
| `status` | CharField | False | present | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### delivery.DeliveryEarning

- **Used by APIs/views (source modules referencing the model):** admin_approvals.py, admin_finance.py, admin_views.py, views.py
- **Tests referencing the model:** test_delivery_multi_active.py, test_delivery_proof_and_earnings.py, test_feed_order_delivery.py, test_pharmacy_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `delivery_earnings` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** payout_status
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `delivery_person` | ForeignKey | False |  | yes | profiles.DeliveryProfile / DO_NOTHING |  |
| `delivery_order` | OneToOneField | False |  | yes | delivery.DeliveryOrder / DO_NOTHING |  |
| `base_pay` | DecimalField | False |  | yes |  |  |
| `bonus` | DecimalField | False | 0 | no |  |  |
| `penalty` | DecimalField | False | 0 | no |  |  |
| `total_earned` | DecimalField | False |  | yes |  |  |
| `payout_status` | CharField | False | pending | no |  |  |
| `payout_date` | DateField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### delivery.DeliveryOrder

- **Used by APIs/views (source modules referencing the model):** admin_pharmacy.py, admin_views.py, catalogue_views.py, documents.py, farmer_views.py, order_admin_views.py, services.py, test_catalogue.py, views.py
- **Tests referencing the model:** test_admin_panel.py, test_admin_row_builder_performance.py, test_delivery_multi_active.py, test_delivery_proof_and_earnings.py, test_feed_order_delivery.py, test_pharmacy_admin.py, test_pharmacy_flow.py, test_private_documents.py, tests.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `delivery_orders` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** assigned_at, delivered_at, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `delivery_person` | ForeignKey | False |  | yes | profiles.DeliveryProfile / DO_NOTHING |  |
| `order_reference_id` | UUIDField | False |  | yes |  |  |
| `order_type` | CharField | False |  | yes |  |  |
| `pickup_address` | TextField | False |  | yes |  | PII/Location |
| `delivery_address` | TextField | False |  | yes |  | PII/Location |
| `pickup_lat` | DecimalField | True |  | no |  | Location |
| `pickup_lng` | DecimalField | True |  | no |  | Location |
| `delivery_lat` | DecimalField | True |  | no |  | Location |
| `delivery_lng` | DecimalField | True |  | no |  | Location |
| `status` | CharField | False | pending | no |  |  |
| `otp_code` | CharField | True |  | no |  |  |
| `proof_of_delivery_url` | TextField | True |  | no |  | Uploaded file/URL |
| `failure_reason` | TextField | True |  | no |  |  |
| `is_pharmacy_delivery` | BooleanField | False | False | no |  |  |
| `is_cold_chain` | BooleanField | False | False | no |  |  |
| `is_prescription_required` | BooleanField | False | False | no |  | Medical |
| `notes` | TextField | True |  | no |  |  |
| `assigned_at` | DateTimeField | True |  | no |  |  |
| `delivered_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### delivery.DeliveryQueueRecord

- **Used by APIs/views (source modules referencing the model):** admin.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### disease.Disease

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_views.py, apps.py, content.py, inference.py, settings.py, views.py
- **Tests referencing the model:** test_disease_detection.py, test_private_documents.py, test_signup_flows.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### disease.DiseaseScan

- **Used by APIs/views (source modules referencing the model):** admin.py, views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### doctor.AvailabilitySlot

- **Used by APIs/views (source modules referencing the model):** booking.py, views.py, workflow.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_consultation_transitions_and_receipts.py, test_doctor_flow.py, test_find_vet_discovery.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `doctor_availability_slots` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `doctor` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `weekday` | PositiveSmallIntegerField | False |  | yes |  |  |
| `start_time` | TimeField | False |  | yes |  |  |
| `end_time` | TimeField | False |  | yes |  |  |
| `mode` | CharField | False | online | no |  |  |
| `is_active` | BooleanField | False | True | no |  |  |
| `created_at` | DateTimeField | False | now | no |  |  |

### doctor.CaseDetail

- **Used by APIs/views (source modules referencing the model):** booking.py, views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `consultation_case_details` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** case_status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `consultation` | OneToOneField | False |  | yes | consultations.Consultation / DO_NOTHING |  |
| `flock` | ForeignKey | True |  | no | farms.Flock / DO_NOTHING |  |
| `farm_name` | CharField | True |  | no |  |  |
| `farmer_name` | CharField | False |  | yes |  |  |
| `bird_age` | CharField | True |  | no |  |  |
| `breed` | CharField | True |  | no |  |  |
| `flock_count` | IntegerField | True |  | no |  |  |
| `mortality_count` | IntegerField | True |  | no |  |  |
| `feed_notes` | TextField | True |  | no |  |  |
| `vaccine_history` | TextField | True |  | no |  |  |
| `biosecurity_notes` | TextField | True |  | no |  |  |
| `symptoms_description` | TextField | True |  | no |  | Medical |
| `farmer_notes` | TextField | True |  | no |  |  |
| `disease_tags` | JSONField | False | list | no |  |  |
| `case_status` | CharField | False | open | no |  |  |
| `created_at` | DateTimeField | False | now | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### doctor.ClinicalPrescription

- **Used by APIs/views (source modules referencing the model):** prescription_pdf.py, views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `clinical_prescriptions` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** email_sent_at, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `consultation` | ForeignKey | False |  | yes | consultations.Consultation / DO_NOTHING |  |
| `doctor` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `dosage_notes` | TextField | True |  | no |  |  |
| `case_advice` | TextField | True |  | no |  |  |
| `follow_up_instructions` | TextField | True |  | no |  |  |
| `referred_to` | CharField | True |  | no |  |  |
| `email_sent_at` | DateTimeField | True |  | no |  | PII |
| `email_error` | TextField | True |  | no |  | PII |
| `created_at` | DateTimeField | False | now | no |  |  |

### doctor.ConsultationNote

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `consultation_notes` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `consultation` | ForeignKey | False |  | yes | consultations.Consultation / DO_NOTHING |  |
| `doctor` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `symptoms` | TextField | True |  | no |  | Medical |
| `diagnosis` | TextField | False |  | yes |  | Medical |
| `treatment_plan` | TextField | False |  | yes |  | Medical |
| `warnings` | TextField | True |  | no |  |  |
| `next_steps` | TextField | True |  | no |  |  |
| `created_at` | DateTimeField | False | now | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### doctor.ConsultationStatusHistory

- **Used by APIs/views (source modules referencing the model):** metrics.py, views.py, workflow.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_consultation_transitions_and_receipts.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `consultation_status_history` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** from_status, to_status
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `consultation` | ForeignKey | False |  | yes | consultations.Consultation / DO_NOTHING |  |
| `actor` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `from_status` | CharField | False |  | yes |  |  |
| `to_status` | CharField | False |  | yes |  |  |
| `reason` | TextField | True |  | no |  |  |
| `created_at` | DateTimeField | False | now | no |  |  |

### doctor.Conversation

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_feed_chat.py, admin_pharmacy.py, admin_pharmacy_chat.py, chat_views.py, owner_chat_views.py, realtime.py, views.py, workflow.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_consultation_chat_access.py, test_dashboard_integrity_and_seed_idempotency.py, test_doctor_flow.py, test_feed_owner_flow.py, test_pharmacy_admin.py, tests.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `conversations` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** pharmacy_chat_status
- **Audit fields:** last_message_at, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `participant_one` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `participant_two` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `consultation` | ForeignKey | True |  | no | consultations.Consultation / DO_NOTHING |  |
| `last_message_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | False | now | no |  |  |
| `pharmacy_chat_status` | CharField | True | open | no |  |  |
| `assigned_admin` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |

### doctor.DoctorEarning

- **Used by APIs/views (source modules referencing the model):** payments.py, views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_consultation_transitions_and_receipts.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `doctor_earnings` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** payout_status
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `doctor` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `consultation` | OneToOneField | False |  | yes | consultations.Consultation / DO_NOTHING |  |
| `gross_amount` | DecimalField | False |  | yes |  | Financial |
| `platform_fee` | DecimalField | False | 0 | no |  | Location |
| `net_amount` | DecimalField | False |  | yes |  | Financial |
| `payout_status` | CharField | False | pending | no |  |  |
| `payout_date` | DateField | True |  | no |  |  |
| `created_at` | DateTimeField | False | now | no |  |  |

### doctor.FollowUp

- **Used by APIs/views (source modules referencing the model):** booking.py, views.py, workflow.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `follow_ups` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `consultation` | ForeignKey | False |  | yes | consultations.Consultation / DO_NOTHING |  |
| `doctor` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `scheduled_date` | DateField | False |  | yes |  |  |
| `scheduled_time` | TimeField | True |  | no |  |  |
| `status` | CharField | False | pending | no |  |  |
| `notes` | TextField | True |  | no |  |  |
| `created_at` | DateTimeField | False | now | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### doctor.Message

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_feed_chat.py, admin_pharmacy_chat.py, chat_views.py, owner_chat_views.py, realtime.py, views.py
- **Tests referencing the model:** test_community.py, test_consultation_booking_rules.py, test_consultation_chat_access.py, test_dashboard_integrity_and_seed_idempotency.py, test_doctor_flow.py, test_feed_owner_flow.py, test_pharmacy_admin.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `messages` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** sent_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `conversation` | ForeignKey | False |  | yes | doctor.Conversation / DO_NOTHING |  |
| `sender` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `content` | TextField | True |  | no |  |  |
| `message_type` | CharField | False | text | no |  |  |
| `file_url` | TextField | True |  | no |  | Uploaded file, Uploaded file/URL |
| `is_read` | BooleanField | False | False | no |  |  |
| `sent_at` | DateTimeField | False | now | no |  |  |

### doctor.PayoutRequest

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `doctor_payout_requests` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** requested_at, processed_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `doctor` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `amount` | DecimalField | False |  | yes |  | Financial |
| `status` | CharField | False | requested | no |  |  |
| `requested_at` | DateTimeField | False | now | no |  |  |
| `processed_at` | DateTimeField | True |  | no |  |  |

### doctor.PrescriptionItem

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_doctor_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `clinical_prescription_items` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** —

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `prescription` | ForeignKey | False |  | yes | doctor.ClinicalPrescription / DO_NOTHING | Medical |
| `medicine_name` | CharField | False |  | yes |  |  |
| `dosage` | CharField | False |  | yes |  |  |
| `duration` | CharField | False |  | yes |  |  |
| `instructions` | TextField | True |  | no |  |  |

### expenses.Expense

- **Used by APIs/views (source modules referencing the model):** cost_views.py, dashboard_views.py, documents.py, services.py, views.py
- **Tests referencing the model:** test_cost_dashboard_charts.py, test_dashboard_integrity_and_seed_idempotency.py, test_farmer_panel.py, test_feed_order_delivery.py, test_feed_owner_flow.py, test_labour_payment.py, test_pharmacy_admin.py, test_pharmacy_flow.py, test_private_documents.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `expenses` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** payment_status
- **Audit fields:** paid_at, created_by, approved_by, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / CASCADE |  |
| `category` | ForeignKey | False |  | yes | expenses.ExpenseCategory / PROTECT |  |
| `flock_id` | UUIDField | True |  | no |  |  |
| `amount` | DecimalField | False |  | yes |  | Financial |
| `description` | TextField | False |  | no |  |  |
| `expense_date` | DateField | False |  | yes |  |  |
| `payment_status` | CharField | False | pending | no |  | Financial |
| `payment_method` | CharField | False |  | no |  | Financial |
| `supplier_name` | CharField | False |  | no |  |  |
| `receipt_url` | TextField | False |  | no |  | Uploaded file/URL |
| `paid_at` | DateTimeField | True |  | no |  |  |
| `payment_id` | UUIDField | True |  | no |  | Financial |
| `source_intent_id` | UUIDField | True |  | no |  |  |
| `source_pharmacy_order_id` | CharField | True |  | no |  |  |
| `source_feed_order_id` | CharField | True |  | no |  |  |
| `created_by` | ForeignKey | False |  | yes | users.User / PROTECT |  |
| `approved_by` | ForeignKey | True |  | no | users.User / PROTECT |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### expenses.ExpenseCategory

- **Used by APIs/views (source modules referencing the model):** cost_views.py, services.py, views.py
- **Tests referencing the model:** test_cost_dashboard_charts.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `expense_categories` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | BigAutoField | False |  | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `linked_module` | CharField | False |  | no |  |  |
| `icon` | CharField | False |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### expenses.Loan

- **Used by APIs/views (source modules referencing the model):** admin_farmer_loans.py, cost_views.py, dashboard_views.py, views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py, test_farmer_panel.py, test_private_documents.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `loans` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** requested_by, decided_by, decided_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / CASCADE |  |
| `lender_name` | CharField | False |  | yes |  |  |
| `loan_amount` | DecimalField | False |  | yes |  | Financial |
| `interest_rate` | DecimalField | True |  | no |  |  |
| `start_date` | DateField | True |  | no |  |  |
| `due_date` | DateField | True |  | no |  |  |
| `remaining_balance` | DecimalField | False |  | yes |  | Financial |
| `status` | CharField | False | active | no |  |  |
| `purpose` | TextField | False |  | no |  |  |
| `term_months` | PositiveIntegerField | True |  | no |  |  |
| `requested_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `decided_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `decided_at` | DateTimeField | True |  | no |  |  |
| `rejection_reason` | TextField | False |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### expenses.LoanInstallment

- **Used by APIs/views (source modules referencing the model):** admin_farmer_loans.py, cost_views.py
- **Tests referencing the model:** test_farmer_panel.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `loan_installments` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `loan` | ForeignKey | False |  | yes | expenses.Loan / CASCADE |  |
| `due_date` | DateField | False |  | yes |  |  |
| `amount` | DecimalField | False |  | yes |  | Financial |
| `paid_date` | DateField | True |  | no |  |  |
| `payment_id` | UUIDField | True |  | no |  | Financial |
| `status` | CharField | False | pending | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### expenses.Revenue

- **Used by APIs/views (source modules referencing the model):** cost_views.py, dashboard_views.py, views.py
- **Tests referencing the model:** test_cost_dashboard_charts.py, test_dashboard_integrity_and_seed_idempotency.py, test_farmer_panel.py, test_finance_admin.py, test_private_documents.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `revenues` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_by, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / CASCADE |  |
| `source` | ForeignKey | False |  | yes | expenses.RevenueSource / PROTECT |  |
| `flock_id` | UUIDField | True |  | no |  |  |
| `amount` | DecimalField | False |  | yes |  | Financial |
| `revenue_date` | DateField | False |  | yes |  |  |
| `description` | TextField | False |  | no |  |  |
| `payment_method` | CharField | False |  | no |  | Financial |
| `buyer_name` | CharField | False |  | no |  |  |
| `receipt_url` | TextField | False |  | no |  | Uploaded file/URL |
| `created_by` | ForeignKey | False |  | yes | users.User / PROTECT |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### expenses.RevenueSource

- **Used by APIs/views (source modules referencing the model):** cost_views.py, views.py
- **Tests referencing the model:** test_cost_dashboard_charts.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `revenue_sources` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | BigAutoField | False |  | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### expenses.TaxRecord

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `tax_records` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / CASCADE |  |
| `tax_year` | PositiveIntegerField | False |  | yes |  |  |
| `tax_month` | PositiveSmallIntegerField | True |  | no |  |  |
| `total_income` | DecimalField | False | 0 | no |  |  |
| `total_expense` | DecimalField | False | 0 | no |  |  |
| `taxable_amount` | DecimalField | False | 0 | no |  | Financial |
| `tax_due` | DecimalField | False | 0 | no |  |  |
| `tax_paid` | DecimalField | False | 0 | no |  |  |
| `payment_date` | DateField | True |  | no |  | Financial |
| `payment_id` | UUIDField | True |  | no |  | Financial |
| `status` | CharField | False | pending | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### farms.Farm

- **Used by APIs/views (source modules referencing the model):** booking.py, constants.py, dashboard_views.py, farm_views.py, farmer_views.py, prescription_pdf.py, profile_views.py, serializers.py, test_catalogue.py, views.py
- **Tests referencing the model:** _create_missing_admin_accounts.py, _create_pharmacy_admin.py, test_admin_panel.py, test_consultation_booking_rules.py, test_consultation_chat_access.py, test_consultation_transitions_and_receipts.py, test_cost_dashboard_charts.py, test_dashboard_integrity_and_seed_idempotency.py, test_data_integrity.py, test_delivery_multi_active.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `farms` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farmer` | ForeignKey | False |  | yes | profiles.FarmerProfile / DO_NOTHING |  |
| `farm_name` | CharField | False |  | yes |  |  |
| `farm_type` | CharField | True | mixed | no |  |  |
| `location` | TextField | False |  | yes |  |  |
| `address` | TextField | False |  | yes |  | PII/Location |
| `latitude` | DecimalField | True |  | no |  | Location |
| `longitude` | DecimalField | True |  | no |  | Location |
| `registration_number` | CharField | True |  | no |  |  |
| `total_sheds` | PositiveIntegerField | True | 0 | no |  |  |
| `is_active` | BooleanField | True | True | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### farms.Flock

- **Used by APIs/views (source modules referencing the model):** booking.py, cost_views.py, farm_views.py, feed_views.py, prescription_pdf.py, views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_dashboard_integrity_and_seed_idempotency.py, test_data_integrity.py, test_doctor_flow.py, test_farmer_panel.py, test_feed_stock_integrity.py, test_flock_feed_management.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `flocks` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `shed` | ForeignKey | True |  | no | farms.Shed / DO_NOTHING |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / DO_NOTHING |  |
| `batch_name` | CharField | False |  | yes |  |  |
| `bird_type` | CharField | True |  | no |  |  |
| `breed` | CharField | True |  | no |  |  |
| `quantity` | IntegerField | False |  | yes |  |  |
| `current_quantity` | IntegerField | False |  | yes |  |  |
| `start_date` | DateField | False |  | yes |  |  |
| `end_date` | DateField | True |  | no |  |  |
| `status` | CharField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### farms.FlockEvent

- **Used by APIs/views (source modules referencing the model):** farm_views.py
- **Tests referencing the model:** test_flock_feed_management.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `flock_events` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** recorded_by, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `flock` | ForeignKey | False |  | yes | farms.Flock / CASCADE |  |
| `event_type` | CharField | False |  | yes |  |  |
| `quantity` | IntegerField | True |  | no |  |  |
| `weight_kg` | DecimalField | True |  | no |  |  |
| `event_date` | DateField | False |  | yes |  |  |
| `notes` | TextField | True |  | no |  |  |
| `recorded_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### farms.Shed

- **Used by APIs/views (source modules referencing the model):** farm_views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py, test_farmer_panel.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `sheds` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / DO_NOTHING |  |
| `shed_name` | CharField | False |  | yes |  |  |
| `capacity` | IntegerField | False |  | yes |  |  |
| `current_bird_count` | IntegerField | True |  | no |  |  |
| `shed_type` | CharField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### feed.FeedConsumption

- **Used by APIs/views (source modules referencing the model):** feed_views.py
- **Tests referencing the model:** test_farmer_panel.py, test_feed_stock_integrity.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feed_consumption` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** recorded_by, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `flock` | ForeignKey | False |  | yes | farms.Flock / DO_NOTHING |  |
| `feed_type` | ForeignKey | False |  | yes | feed.FeedType / DO_NOTHING |  |
| `consumed_date` | DateField | False |  | yes |  |  |
| `quantity_consumed` | DecimalField | False |  | yes |  |  |
| `recorded_by` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `notes` | TextField | False |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### feed.FeedSchedule

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feed_schedules` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `flock` | ForeignKey | False |  | yes | farms.Flock / DO_NOTHING |  |
| `feed_type` | ForeignKey | False |  | yes | feed.FeedType / DO_NOTHING |  |
| `scheduled_time` | TimeField | False |  | yes |  |  |
| `quantity_per_feeding` | DecimalField | False |  | yes |  |  |
| `frequency` | CharField | True | daily | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### feed.FeedStock

- **Used by APIs/views (source modules referencing the model):** cost_views.py, feed_views.py, views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py, test_feed_stock_integrity.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feed_stock` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['farm', 'feed_type']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** last_restocked_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / DO_NOTHING |  |
| `feed_type` | ForeignKey | False |  | yes | feed.FeedType / DO_NOTHING |  |
| `quantity_available` | DecimalField | False | 0 | no |  |  |
| `last_restocked_at` | DateTimeField | True |  | no |  |  |
| `supplier_name` | CharField | True |  | no |  |  |
| `cost_per_unit` | DecimalField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### feed.FeedStockMovement

- **Used by APIs/views (source modules referencing the model):** feed_views.py, views.py
- **Tests referencing the model:** test_feed_stock_integrity.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feed_stock_movements` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_by, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / DO_NOTHING |  |
| `feed_type` | ForeignKey | False |  | yes | feed.FeedType / DO_NOTHING |  |
| `movement_type` | CharField | False |  | yes |  |  |
| `quantity_delta` | DecimalField | False |  | yes |  |  |
| `quantity_after` | DecimalField | False |  | yes |  |  |
| `unit_cost` | DecimalField | True |  | no |  |  |
| `note` | TextField | True |  | no |  |  |
| `created_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### feed.FeedType

- **Used by APIs/views (source modules referencing the model):** feed_views.py, views.py
- **Tests referencing the model:** test_feed_stock_integrity.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feed_types` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `brand` | CharField | True |  | no |  |  |
| `nutritional_info` | JSONField | True |  | no |  |  |
| `unit` | CharField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### feed.FeedingGuideline

- **Used by APIs/views (source modules referencing the model):** constants.py, feed_views.py
- **Tests referencing the model:** test_flock_feed_management.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feeding_guidelines` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `bird_type` | CharField | False |  | yes |  |  |
| `min_age_days` | IntegerField | False |  | yes |  |  |
| `max_age_days` | IntegerField | False |  | yes |  |  |
| `stage_label` | CharField | False |  | yes |  |  |
| `feed_type_label` | CharField | False |  | yes |  |  |
| `recommended_grams_per_bird_per_day` | DecimalField | True |  | no |  |  |
| `frequency_per_day` | IntegerField | False | 2 | no |  |  |
| `guidance_text` | TextField | False |  | yes |  |  |
| `is_active` | BooleanField | False | True | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### feed_catalogue.FeedCompany

- **Used by APIs/views (source modules referencing the model):** admin_views.py, order_admin_views.py
- **Tests referencing the model:** test_delivery_multi_active.py, test_feed_catalogue.py, test_feed_marketplace_ux.py, test_feed_order_delivery.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feed_companies` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_by, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `contact_person` | CharField | False |  | no |  |  |
| `contact_phone` | CharField | False |  | no |  | PII |
| `contact_email` | CharField | False |  | no |  | PII |
| `address` | TextField | False |  | no |  | PII/Location |
| `district` | CharField | False |  | no |  |  |
| `upazila` | CharField | False |  | no |  |  |
| `description` | TextField | True |  | no |  |  |
| `logo_url` | TextField | True |  | no |  | Uploaded file/URL |
| `cover_url` | TextField | True |  | no |  | Uploaded file/URL |
| `license_number` | CharField | True |  | no |  | ID document |
| `status` | CharField | False | active | no |  |  |
| `admin_notes` | TextField | True |  | no |  |  |
| `created_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### feed_catalogue.FeedProduct

- **Used by APIs/views (source modules referencing the model):** admin_views.py, constants.py, farmer_views.py, order_admin_views.py, services.py, views.py
- **Tests referencing the model:** test_delivery_multi_active.py, test_feed_catalogue.py, test_feed_marketplace_ux.py, test_feed_order_delivery.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feed_products` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** approval_status
- **Audit fields:** created_by, approved_by, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `company` | ForeignKey | False |  | yes | feed_catalogue.FeedCompany / CASCADE |  |
| `product_name` | CharField | False |  | yes |  |  |
| `brand` | CharField | False |  | no |  |  |
| `feed_type` | CharField | False | other | no |  |  |
| `bird_type` | CharField | False | other | no |  |  |
| `description` | TextField | True |  | no |  |  |
| `ingredients` | TextField | True |  | no |  |  |
| `nutritional_info` | JSONField | False | dict | no |  |  |
| `unit` | CharField | False | kg | no |  |  |
| `price` | DecimalField | False | 0 | no |  | Financial |
| `stock_quantity` | IntegerField | False | 0 | no |  |  |
| `min_order_quantity` | IntegerField | False | 1 | no |  |  |
| `image_url` | TextField | True |  | no |  | Uploaded file, Uploaded file/URL |
| `gallery_urls` | JSONField | False | list | no |  | Uploaded file/URL |
| `approval_status` | CharField | False | draft | no |  |  |
| `rejection_reason` | TextField | True |  | no |  |  |
| `created_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `approved_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `orders_count` | IntegerField | False | 0 | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### messaging.Conversation

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_feed_chat.py, admin_pharmacy.py, admin_pharmacy_chat.py, chat_views.py, owner_chat_views.py, realtime.py, views.py, workflow.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_consultation_chat_access.py, test_dashboard_integrity_and_seed_idempotency.py, test_doctor_flow.py, test_feed_owner_flow.py, test_pharmacy_admin.py, tests.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### messaging.Message

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_feed_chat.py, admin_pharmacy_chat.py, chat_views.py, owner_chat_views.py, realtime.py, views.py
- **Tests referencing the model:** test_community.py, test_consultation_booking_rules.py, test_consultation_chat_access.py, test_dashboard_integrity_and_seed_idempotency.py, test_doctor_flow.py, test_feed_owner_flow.py, test_pharmacy_admin.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### ml.DiseaseRef

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `diseases` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `description` | TextField | False |  | yes |  |  |
| `symptoms` | JSONField | False | list | no |  | Medical |
| `what_to_do` | TextField | False |  | yes |  |  |
| `what_not_to_do` | TextField | False |  | yes |  |  |
| `prevention_tips` | TextField | True |  | no |  |  |
| `severity_level` | CharField | True |  | no |  |  |
| `requires_immediate_vet` | BooleanField | False | False | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### ml.DiseaseScan

- **Used by APIs/views (source modules referencing the model):** admin.py, views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `disease_scans` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** image_quality_status, scan_status
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / CASCADE |  |
| `farm_id` | UUIDField | True |  | no |  |  |
| `flock_id` | UUIDField | True |  | no |  |  |
| `image_urls` | JSONField | False | list | no |  | Uploaded file, Uploaded file/URL |
| `image_quality_status` | CharField | True | good | no |  | Uploaded file |
| `detected_disease` | ForeignKey | True |  | no | ml.DiseaseRef / SET_NULL |  |
| `confidence_score` | DecimalField | True |  | no |  |  |
| `severity_level` | CharField | True |  | no |  |  |
| `scan_status` | CharField | True | processing | no |  |  |
| `is_free_scan` | BooleanField | False | True | no |  |  |
| `chatbot_session_id` | UUIDField | True |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### notifications.Notification

- **Used by APIs/views (source modules referencing the model):** admin_approvals.py, admin_cashouts.py, admin_extra.py, admin_farmer_loans.py, admin_feed_chat.py, admin_finance.py, admin_pharmacy.py, admin_shifts.py, admin_support.py, admin_views.py, catalogue_views.py, farmer_views.py, order_admin_views.py, owner_chat_views.py …
- **Tests referencing the model:** test_community.py, test_consultation_booking_rules.py, test_consultation_transitions_and_receipts.py, test_dashboard_integrity_and_seed_idempotency.py, test_doctor_flow.py, test_farmer_panel.py, test_feed_owner_flow.py, test_feed_stock_integrity.py, test_flock_feed_management.py, test_pharmacy_admin.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `notifications` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / CASCADE |  |
| `title` | CharField | False |  | yes |  |  |
| `body` | TextField | False |  | yes |  |  |
| `notification_type` | CharField | False | system | no |  |  |
| `reference_id` | UUIDField | True |  | no |  |  |
| `reference_type` | CharField | False |  | no |  |  |
| `is_read` | BooleanField | False | False | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### payments.Payment

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_approvals.py, admin_cashouts.py, admin_finance.py, admin_shifts.py, admin_views.py, catalogue_views.py, cost_views.py, dashboard_views.py, farmer_views.py, payments.py, services.py, urls.py, views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_consultation_transitions_and_receipts.py, test_doctor_flow.py, test_farmer_panel.py, test_finance_admin.py, test_private_documents.py, test_subscription_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `payments` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** confirmed_at, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `amount` | DecimalField | False |  | yes |  | Financial |
| `currency` | CharField | False | BDT | no |  |  |
| `payment_method` | CharField | True |  | no |  | Financial |
| `payment_type` | CharField | True |  | no |  | Financial |
| `reference_id` | UUIDField | True |  | no |  |  |
| `reference_type` | CharField | True |  | no |  |  |
| `status` | CharField | False | pending | no |  |  |
| `transaction_id` | CharField | True |  | no |  |  |
| `receipt_url` | TextField | True |  | no |  | Uploaded file/URL |
| `notes` | TextField | True |  | no |  |  |
| `platform_charge` | DecimalField | False | 0 | no |  | Location |
| `net_amount` | DecimalField | False | 0 | no |  | Financial |
| `confirmed_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### pharmacy.PharmacyAppeal

- **Used by APIs/views (source modules referencing the model):** admin_pharmacy.py, admin_pharmacy_metrics.py, appeal_views.py, services.py
- **Tests referencing the model:** test_pharmacy_admin.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_appeals` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** resolved_by, resolved_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `pharmacy_user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `suspension_log_id` | UUIDField | True |  | no |  |  |
| `reason` | TextField | False |  | no |  |  |
| `explanation` | TextField | False |  | no |  |  |
| `attachments` | JSONField | False | list | no |  |  |
| `status` | CharField | False | submitted | no |  |  |
| `admin_response` | TextField | True |  | no |  |  |
| `resolved_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `resolved_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### pharmacy.PharmacyCommission

- **Used by APIs/views (source modules referencing the model):** admin_pharmacy.py, admin_pharmacy_metrics.py, permissions_views.py, services.py, settings.py
- **Tests referencing the model:** test_pharmacy_admin.py, test_pharmacy_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_commissions` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `sale` | OneToOneField | False |  | yes | pharmacy.PharmacySale / DO_NOTHING |  |
| `rate` | DecimalField | False |  | yes |  |  |
| `gross_amount` | DecimalField | False |  | yes |  | Financial |
| `commission_amount` | DecimalField | False |  | yes |  | Financial |
| `pharmacy_amount` | DecimalField | False |  | yes |  | Financial |
| `created_at` | DateTimeField | True |  | no |  |  |

### pharmacy.PharmacyEmployee

- **Used by APIs/views (source modules referencing the model):** admin_pharmacy.py, admin_pharmacy_metrics.py
- **Tests referencing the model:** test_pharmacy_admin.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_employees` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** added_by, added_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `pharmacy_user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `name` | TextField | False |  | yes |  |  |
| `role_title` | CharField | False |  | no |  |  |
| `phone` | CharField | False |  | no |  | PII |
| `email` | CharField | False |  | no |  | PII |
| `license_number` | TextField | True |  | no |  | ID document |
| `access_level` | CharField | False | staff | no |  |  |
| `is_active` | BooleanField | False | True | no |  |  |
| `added_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `added_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### pharmacy.PharmacyExpiryAlert

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_pharmacy.py, catalogue_views.py, services.py, test_catalogue.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_expiry_alerts` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `pharmacy_user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `medicine` | OneToOneField | False |  | yes | pharmacy.PharmacyMedicine / DO_NOTHING |  |
| `expires_in_days` | IntegerField | False |  | yes |  |  |
| `alert_level` | CharField | False |  | yes |  |  |
| `is_acknowledged` | BooleanField | False | False | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### pharmacy.PharmacyMedicine

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_pharmacy.py, admin_pharmacy_metrics.py, catalogue_views.py, farmer_views.py, services.py, test_catalogue.py
- **Tests referencing the model:** test_pharmacy_admin.py, test_pharmacy_flow.py, test_pharmacy_marketplace_card_fields.py, test_pharmacy_medicine_edit.py, test_pharmacy_medicine_images.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_catalogue_medicines` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `pharmacy_user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `legacy_record_id` | CharField | True |  | no |  |  |
| `name` | TextField | False |  | yes |  |  |
| `generic_name` | TextField | True |  | no |  |  |
| `manufacturer` | TextField | False |  | no |  |  |
| `category` | CharField | False | other | no |  |  |
| `prescription_required` | BooleanField | False | False | no |  | Medical |
| `price` | DecimalField | False | 0 | no |  | Financial |
| `previous_price` | DecimalField | True |  | no |  | Financial |
| `stock_quantity` | IntegerField | False | 0 | no |  |  |
| `unit` | CharField | False | piece | no |  |  |
| `min_order_quantity` | PositiveIntegerField | False | 1 | no |  |  |
| `pack_size` | TextField | False |  | no |  |  |
| `description` | TextField | True |  | no |  |  |
| `dosage_instructions` | TextField | True |  | no |  |  |
| `storage_instructions` | TextField | True |  | no |  |  |
| `cold_chain_required` | BooleanField | False | False | no |  |  |
| `expiry_date` | DateField | False |  | yes |  |  |
| `batch_number` | TextField | True |  | no |  |  |
| `images` | JSONField | False | list | no |  | Uploaded file |
| `is_active` | BooleanField | False | True | no |  |  |
| `is_approved` | BooleanField | False | False | no |  |  |
| `approval_rejected_reason` | TextField | True |  | no |  |  |
| `views_count` | IntegerField | False | 0 | no |  |  |
| `orders_count` | IntegerField | False | 0 | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### pharmacy.PharmacyMedicineRecord

- **Used by APIs/views (source modules referencing the model):** admin.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### pharmacy.PharmacyOrganization

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_extra.py, admin_views.py, documents.py, serializers.py, services.py
- **Tests referencing the model:** test_pharmacy_admin.py, test_signup_flows.py, test_verification_flows.py, test_verification_status.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `backend_admin_records` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `module` | CharField | False |  | yes |  |  |
| `record_id` | CharField | False |  | yes |  |  |
| `payload` | JSONField | False | dict | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### pharmacy.PharmacySale

- **Used by APIs/views (source modules referencing the model):** admin_pharmacy.py, admin_pharmacy_metrics.py, permissions_views.py, services.py
- **Tests referencing the model:** test_pharmacy_admin.py, test_pharmacy_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_sales` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** completed_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `order_reference` | TextField | False |  | yes |  |  |
| `pharmacy_user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `gross_amount` | DecimalField | False | 0 | no |  | Financial |
| `status` | CharField | False | completed | no |  |  |
| `completed_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### pharmacy.PharmacySettlement

- **Used by APIs/views (source modules referencing the model):** admin_pharmacy.py, admin_pharmacy_metrics.py
- **Tests referencing the model:** test_pharmacy_admin.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_settlements` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** paid_at, created_by, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `pharmacy_user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `period_start` | DateField | False |  | yes |  |  |
| `period_end` | DateField | False |  | yes |  |  |
| `gross_sales` | DecimalField | False | 0 | no |  |  |
| `commission` | DecimalField | False | 0 | no |  |  |
| `payable_amount` | DecimalField | False | 0 | no |  | Financial |
| `status` | CharField | False | pending | no |  |  |
| `paid_at` | DateTimeField | True |  | no |  |  |
| `payment_reference` | TextField | True |  | no |  | Financial |
| `created_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### pharmacy.PharmacySupplier

- **Used by APIs/views (source modules referencing the model):** admin.py, catalogue_views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_suppliers` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `pharmacy_user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `supplier_name` | TextField | False |  | yes |  |  |
| `contact_person` | TextField | False |  | no |  |  |
| `phone` | CharField | False |  | no |  | PII |
| `email` | CharField | False |  | no |  | PII |
| `address` | TextField | False |  | no |  | PII/Location |
| `products_supplied` | TextField | False |  | no |  |  |
| `payment_terms` | TextField | True |  | no |  | Financial |
| `is_active` | BooleanField | False | True | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.AdminPayment

- **Used by APIs/views (source modules referencing the model):** admin_shifts.py
- **Tests referencing the model:** test_admin_panel.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `admin_payments` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['admin', 'period_start']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** payment_status
- **Audit fields:** generated_by, paid_by, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `admin` | ForeignKey | False |  | yes | profiles.AdminProfile / CASCADE |  |
| `period_start` | DateField | False |  | yes |  |  |
| `period_end` | DateField | False |  | yes |  |  |
| `total_hours` | DecimalField | False | 0 | no |  |  |
| `regular_hours` | DecimalField | False | 0 | no |  |  |
| `overtime_hours` | DecimalField | False | 0 | no |  |  |
| `hourly_rate` | DecimalField | False | 0 | no |  | Uploaded file/URL |
| `overtime_rate` | DecimalField | False | 0 | no |  |  |
| `total_payment` | DecimalField | False | 0 | no |  | Financial |
| `payment_status` | CharField | False | pending | no |  | Financial |
| `payment_date` | DateTimeField | True |  | no |  | Financial |
| `payment_method` | CharField | True |  | no |  | Financial |
| `payment_reference` | TextField | True |  | no |  | Financial |
| `notes` | TextField | True |  | no |  |  |
| `generated_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `paid_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.AdminProfile

- **Used by APIs/views (source modules referencing the model):** admin_extra.py, admin_shifts.py, admin_views.py, documents.py, serializers.py, status.py
- **Tests referencing the model:** _create_missing_admin_accounts.py, _create_pharmacy_admin.py, _create_pharmacy_admin_2.py, test_admin_dashboard_metrics.py, test_admin_earnings.py, test_admin_panel.py, test_community.py, test_doctor_flow.py, test_finance_admin.py, test_signup_flows.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `admin_profiles` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** approval_status
- **Audit fields:** suspended_at, suspended_by, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | OneToOneField | False |  | yes | users.User / DO_NOTHING |  |
| `account_id_number` | CharField | True |  | no |  |  |
| `job_title` | CharField | False |  | yes |  |  |
| `department` | CharField | False |  | yes |  |  |
| `reporting_manager` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `work_location` | CharField | True |  | no |  |  |
| `employment_type` | CharField | True |  | no |  |  |
| `start_date` | DateField | False |  | yes |  |  |
| `admin_sub_role` | CharField | True |  | no |  |  |
| `tech_skill_level` | CharField | True |  | no |  |  |
| `confidentiality_agreement_accepted` | BooleanField | False | False | no |  |  |
| `background_check_consent` | BooleanField | False | False | no |  |  |
| `cv_url` | TextField | True |  | no |  | Uploaded file/URL |
| `previous_experience` | TextField | True |  | no |  |  |
| `approved_by_admin` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `admin_role` | ForeignKey | True |  | no | users.Role / SET_NULL |  |
| `access_level_requested` | CharField | True |  | no |  |  |
| `prior_admin_operations_experience` | TextField | True |  | no |  |  |
| `internal_approval_by_founder_hr` | BooleanField | False | False | no |  |  |
| `strong_password_2fa_enabled` | BooleanField | False | False | no |  | Internal/secret |
| `is_active` | BooleanField | False | True | no |  |  |
| `is_suspended` | BooleanField | False | False | no |  |  |
| `suspended_at` | DateTimeField | True |  | no |  |  |
| `suspended_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `approval_status` | CharField | False | approved | no |  |  |
| `hourly_rate` | DecimalField | False | 0 | no |  | Uploaded file/URL |
| `max_hours_per_week` | IntegerField | True |  | no |  |  |
| `last_shift_start` | DateTimeField | True |  | no |  |  |
| `pending_hourly_rate` | DecimalField | True |  | no |  | Uploaded file/URL |
| `pending_rate_effective_from` | DateField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.AdminShift

- **Used by APIs/views (source modules referencing the model):** admin_shifts.py
- **Tests referencing the model:** test_admin_earnings.py, test_admin_panel.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `admin_shifts` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** ended_by, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `admin` | ForeignKey | False |  | yes | profiles.AdminProfile / CASCADE |  |
| `shift_date` | DateField | False |  | yes |  |  |
| `start_time` | DateTimeField | False |  | yes |  |  |
| `end_time` | DateTimeField | True |  | no |  |  |
| `break_start` | DateTimeField | True |  | no |  |  |
| `break_end` | DateTimeField | True |  | no |  |  |
| `break_duration_minutes` | IntegerField | False | 0 | no |  |  |
| `total_hours` | DecimalField | False | 0 | no |  |  |
| `is_active` | BooleanField | False | True | no |  |  |
| `auto_flagged` | BooleanField | False | False | no |  |  |
| `ended_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `ip_address` | CharField | True |  | no |  | PII/Location |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.DeliveryProfile

- **Used by APIs/views (source modules referencing the model):** admin_approvals.py, admin_extra.py, admin_pharmacy.py, admin_views.py, documents.py, order_admin_views.py, serializers.py, test_catalogue.py, views.py
- **Tests referencing the model:** test_admin_dashboard_metrics.py, test_admin_panel.py, test_admin_row_builder_performance.py, test_delivery_multi_active.py, test_delivery_proof_and_earnings.py, test_feed_order_delivery.py, test_pharmacy_admin.py, test_pharmacy_flow.py, test_private_documents.py, test_signup_flows.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `delivery_profiles` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** current_status
- **Audit fields:** location_updated_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | OneToOneField | False |  | yes | users.User / DO_NOTHING |  |
| `drivers_license_number` | CharField | False |  | yes |  | ID document |
| `license_class` | CharField | False |  | yes |  | ID document |
| `license_expiry_date` | DateField | False |  | yes |  | ID document |
| `license_photo_url` | TextField | False |  | yes |  | ID document, Uploaded file, Uploaded file/URL |
| `proof_of_work_url` | TextField | True |  | no |  | Uploaded file/URL |
| `prior_delivery_experience` | TextField | True |  | no |  |  |
| `area_coverage` | TextField | True |  | no |  |  |
| `availability_schedule` | JSONField | True |  | no |  |  |
| `is_online` | BooleanField | True | False | no |  |  |
| `current_status` | CharField | True | offline | no |  |  |
| `rating` | DecimalField | True | 0 | no |  |  |
| `total_deliveries` | IntegerField | True | 0 | no |  |  |
| `approved_by_admin` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `current_lat` | DecimalField | True |  | no |  | Location |
| `current_lng` | DecimalField | True |  | no |  | Location |
| `location_updated_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.DoctorProfile

- **Used by APIs/views (source modules referencing the model):** admin_approvals.py, admin_extra.py, admin_views.py, booking.py, documents.py, serializers.py, views.py
- **Tests referencing the model:** test_admin_dashboard_metrics.py, test_admin_panel.py, test_admin_row_builder_performance.py, test_consultation_booking_rules.py, test_consultation_chat_access.py, test_consultation_transitions_and_receipts.py, test_doctor_flow.py, test_find_vet_discovery.py, test_signup_flows.py, test_verification_flows.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `doctor_profiles` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** availability_status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | OneToOneField | False |  | yes | users.User / DO_NOTHING |  |
| `clinic_hospital_name` | CharField | False |  | yes |  |  |
| `practice_address` | TextField | False |  | yes |  | PII/Location |
| `latitude` | DecimalField | True |  | no |  | Location |
| `longitude` | DecimalField | True |  | no |  | Location |
| `veterinary_degree` | CharField | False |  | yes |  |  |
| `university_name` | CharField | False |  | yes |  |  |
| `graduation_year` | PositiveIntegerField | False |  | yes |  |  |
| `license_number` | CharField | False |  | yes |  | ID document |
| `license_issuing_authority` | CharField | False |  | yes |  | ID document |
| `license_expiry_date` | DateField | False |  | yes |  | ID document |
| `specialty` | CharField | False |  | yes |  |  |
| `poultry_focus_area` | TextField | True |  | no |  |  |
| `years_of_experience` | PositiveIntegerField | False |  | yes |  |  |
| `consultation_mode` | CharField | True |  | no |  |  |
| `cv_url` | TextField | True |  | no |  | Uploaded file/URL |
| `council_registration_proof_url` | TextField | False |  | yes |  | Uploaded file/URL |
| `prescription_authority` | BooleanField | True | False | no |  | Medical |
| `emergency_on_call_availability` | BooleanField | True | False | no |  |  |
| `service_fee` | DecimalField | True |  | no |  |  |
| `referral_network` | TextField | True |  | no |  |  |
| `consent_platform_guidelines` | BooleanField | False | False | no |  | Location |
| `is_verified` | BooleanField | True | False | no |  |  |
| `is_available` | BooleanField | True | True | no |  |  |
| `availability_status` | CharField | True | available | no |  |  |
| `rating` | DecimalField | True | 0 | no |  |  |
| `approved_by_admin` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.FarmerProfile

- **Used by APIs/views (source modules referencing the model):** dashboard_views.py, documents.py, profile_views.py, serializers.py, views.py
- **Tests referencing the model:** test_consultation_booking_rules.py, test_consultation_chat_access.py, test_consultation_transitions_and_receipts.py, test_cost_dashboard_charts.py, test_dashboard_integrity_and_seed_idempotency.py, test_data_integrity.py, test_delivery_proof_and_earnings.py, test_doctor_flow.py, test_farmer_panel.py, test_feed_stock_integrity.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `farmer_profiles` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | OneToOneField | False |  | yes | users.User / DO_NOTHING |  |
| `farm_name` | CharField | False |  | yes |  |  |
| `owner_name` | CharField | False |  | yes |  |  |
| `farm_location` | TextField | False |  | yes |  |  |
| `farm_address` | TextField | False |  | yes |  | PII/Location |
| `farm_type` | CharField | True |  | no |  |  |
| `number_of_birds` | IntegerField | True |  | no |  |  |
| `farm_registration_number` | CharField | True |  | no |  |  |
| `years_in_farming` | IntegerField | True |  | no |  |  |
| `experience_level` | CharField | True |  | no |  |  |
| `primary_diseases_faced` | TextField | True |  | no |  |  |
| `feed_type` | CharField | True |  | no |  |  |
| `feed_sourcing_method` | TextField | True |  | no |  |  |
| `existing_vet_consultant` | CharField | True |  | no |  |  |
| `farm_photos` | JSONField | True |  | no |  | Uploaded file |
| `number_of_active_workers` | IntegerField | True |  | no |  |  |
| `consent_data_collection` | BooleanField | False | False | no |  |  |
| `approved_by_admin` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.FeedOwnerProfile

- **Used by APIs/views (source modules referencing the model):** owner_views.py
- **Tests referencing the model:** test_feed_owner_flow.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feed_owner_profiles` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | OneToOneField | False |  | yes | users.User / DO_NOTHING |  |
| `business_name` | CharField | False |  | no |  |  |
| `inventory_location` | TextField | False |  | no |  |  |
| `assigned_categories` | JSONField | False | list | no |  |  |
| `profile_photo_url` | TextField | True |  | no |  | Uploaded file, Uploaded file/URL |
| `status` | CharField | False | active | no |  |  |
| `approved_by_admin` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.PharmacyOrganization

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_extra.py, admin_views.py, documents.py, serializers.py, services.py
- **Tests referencing the model:** test_pharmacy_admin.py, test_signup_flows.py, test_verification_flows.py, test_verification_status.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `pharmacy_organizations` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | OneToOneField | False |  | yes | users.User / DO_NOTHING |  |
| `business_name` | CharField | False |  | yes |  |  |
| `authorized_contact_person` | CharField | False |  | yes |  |  |
| `business_registration_number` | CharField | False |  | yes |  |  |
| `trade_license_url` | TextField | False |  | yes |  | ID document, Uploaded file/URL |
| `tax_vat_tin_number` | CharField | False |  | yes |  |  |
| `business_address` | TextField | False |  | yes |  | PII/Location |
| `warehouse_address` | TextField | True |  | no |  | PII/Location |
| `number_of_pharmacists` | IntegerField | True | 0 | no |  |  |
| `responsible_pharmacist_name` | CharField | True |  | no |  |  |
| `is_verified` | BooleanField | True | False | no |  |  |
| `approved_by_admin` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `review_state` | CharField | True | approved | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### profiles.ResearcherProfile

- **Used by APIs/views (source modules referencing the model):** admin_approvals.py, admin_extra.py, admin_views.py, documents.py, serializers.py, views.py
- **Tests referencing the model:** test_admin_row_builder_performance.py, test_signup_flows.py, test_verification_flows.py, test_verification_status.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `researcher_profiles` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | OneToOneField | False |  | yes | users.User / DO_NOTHING |  |
| `institution_name` | CharField | False |  | yes |  |  |
| `institutional_email` | CharField | False |  | yes |  | PII |
| `department` | CharField | False |  | yes |  |  |
| `highest_degree` | CharField | False |  | yes |  |  |
| `field_of_study` | CharField | False |  | yes |  |  |
| `university_name` | CharField | False |  | yes |  |  |
| `graduation_year` | IntegerField | False |  | yes |  |  |
| `cv_url` | TextField | False |  | yes |  | Uploaded file/URL |
| `publications_portfolio_url` | TextField | True |  | no |  | Uploaded file/URL |
| `areas_of_expertise` | JSONField | True | list | no |  |  |
| `years_of_research_experience` | IntegerField | False |  | yes |  |  |
| `poultry_specific_experience` | TextField | True |  | no |  |  |
| `research_role_type` | CharField | True |  | no |  |  |
| `ethics_certificate_url` | TextField | True |  | no |  | Uploaded file/URL |
| `conflict_of_interest_declaration` | BooleanField | False | False | no |  |  |
| `publication_consent` | BooleanField | False | False | no |  |  |
| `ip_agreement` | BooleanField | False | False | no |  |  |
| `reference_name` | CharField | True |  | no |  |  |
| `reference_title` | CharField | True |  | no |  |  |
| `reference_email` | CharField | True |  | no |  | PII |
| `is_verified` | BooleanField | True | False | no |  |  |
| `approved_by_admin` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### research.ArticleTag

- **Used by APIs/views (source modules referencing the model):** — (not referenced by any view module)
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `article_tags` (managed=False)
- **Primary key:** `pk`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** —

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `article` | ForeignKey | False |  | yes | articles.Article / CASCADE |  |
| `tag` | ForeignKey | False |  | yes | research.ResearchTag / CASCADE |  |

### research.ArticleVersionSnapshot

- **Used by APIs/views (source modules referencing the model):** views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `article_version_snapshots` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** changed_by, changed_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `article` | ForeignKey | False |  | yes | articles.Article / CASCADE |  |
| `version` | IntegerField | False |  | yes |  |  |
| `snapshot` | JSONField | False | dict | no |  |  |
| `changed_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `change_note` | CharField | True |  | no |  |  |
| `changed_at` | DateTimeField | True |  | no |  |  |

### research.ProfileChangeApplication

- **Used by APIs/views (source modules referencing the model):** admin_views.py, permissions.py, views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `profile_change_applications` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** reviewed_by, decided_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / CASCADE |  |
| `field_name` | CharField | False |  | yes |  |  |
| `old_value` | TextField | True |  | no |  |  |
| `new_value` | TextField | False |  | yes |  |  |
| `reason` | TextField | False |  | yes |  |  |
| `status` | CharField | False | pending | no |  |  |
| `reviewed_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `review_note` | TextField | True |  | no |  |  |
| `decided_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### research.ResearchTag

- **Used by APIs/views (source modules referencing the model):** admin_views.py, views.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `research_tags` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `slug` | SlugField | False |  | yes |  |  |
| `category` | CharField | False |  | yes |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### subscriptions.FeatureUsage

- **Used by APIs/views (source modules referencing the model):** validation.py
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `feature_usage` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** ['user', 'feature_name']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** last_used_at, reset_at, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `feature_name` | CharField | False |  | yes |  |  |
| `usage_count` | IntegerField | False | 0 | no |  |  |
| `limit_count` | IntegerField | False |  | yes |  |  |
| `last_used_at` | DateTimeField | True |  | no |  |  |
| `reset_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |

### subscriptions.Subscription

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_finance.py, admin_subscriptions.py, admin_views.py, permissions.py, services.py, urls.py, views.py
- **Tests referencing the model:** test_finance_admin.py, test_subscription_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `subscriptions` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** started_at, expires_at, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `plan` | ForeignKey | False |  | yes | subscriptions.SubscriptionPlan / DO_NOTHING |  |
| `status` | CharField | False | pending | no |  |  |
| `started_at` | DateTimeField | False |  | yes |  |  |
| `expires_at` | DateTimeField | True |  | no |  |  |
| `auto_renew` | BooleanField | False | False | no |  |  |
| `payment_id` | UUIDField | True |  | no |  | Financial |
| `created_at` | DateTimeField | True |  | no |  |  |

### subscriptions.SubscriptionPlan

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_finance.py, admin_subscriptions.py, admin_views.py, services.py, views.py
- **Tests referencing the model:** test_finance_admin.py, test_subscription_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `subscription_plans` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | AutoField | False |  | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `price` | DecimalField | False |  | yes |  | Financial |
| `currency` | CharField | False | BDT | no |  |  |
| `duration_days` | IntegerField | True |  | no |  |  |
| `features_unlocked` | JSONField | False | list | no |  |  |
| `disease_scan_limit` | IntegerField | True |  | no |  |  |
| `is_active` | BooleanField | False | True | no |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### tax.TaxPayment

- **Used by APIs/views (source modules referencing the model):** serializers.py, views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py, test_tax_calculator.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `tax_payments` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | False |  | yes | users.User / CASCADE |  |
| `tax_type` | CharField | False |  | yes |  |  |
| `amount` | DecimalField | False |  | yes |  | Financial |
| `payment_date` | DateField | False |  | yes |  | Financial |
| `reference_number` | CharField | False |  | no |  |  |
| `notes` | TextField | False |  | no |  |  |
| `receipt_url` | TextField | False |  | no |  | Uploaded file/URL |
| `expense_id` | UUIDField | True |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### tax.TaxProfile

- **Used by APIs/views (source modules referencing the model):** serializers.py, views.py
- **Tests referencing the model:** test_tax_calculator.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `tax_profiles` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | OneToOneField | False |  | yes | users.User / CASCADE |  |
| `land_area` | DecimalField | False | 0 | no |  |  |
| `land_unit` | CharField | False | katha | no |  |  |
| `land_use` | CharField | False | agricultural | no |  |  |
| `location` | CharField | False | rural | no |  |  |
| `vehicles` | JSONField | False | list | no |  |  |
| `income_type` | CharField | False | agricultural | no |  |  |
| `exemptions` | DecimalField | False | 0 | no |  |  |
| `rebates` | DecimalField | False | 0 | no |  |  |
| `is_senior` | BooleanField | False | False | no |  |  |
| `district` | CharField | False |  | no |  |  |
| `upazila` | CharField | False |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### token_blacklist.BlacklistedToken

- **Used by APIs/views (source modules referencing the model):** — (not referenced by any view module)
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `token_blacklist_blacklistedtoken` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** blacklisted_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | BigAutoField | False |  | no |  |  |
| `token` | OneToOneField | False |  | yes | token_blacklist.OutstandingToken / CASCADE |  |
| `blacklisted_at` | DateTimeField | False |  | no |  |  |

### token_blacklist.OutstandingToken

- **Used by APIs/views (source modules referencing the model):** — (not referenced by any view module)
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `token_blacklist_outstandingtoken` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, expires_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | BigAutoField | False |  | no |  |  |
| `user` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `jti` | CharField | False |  | yes |  |  |
| `token` | TextField | False |  | yes |  |  |
| `created_at` | DateTimeField | True |  | no |  |  |
| `expires_at` | DateTimeField | False |  | yes |  |  |

### users.Role

- **Used by APIs/views (source modules referencing the model):** admin_approvals.py, admin_extra.py, admin_rbac.py, admin_shifts.py, admin_views.py, serializers.py, test_catalogue.py
- **Tests referencing the model:** _create_missing_admin_accounts.py, _create_pharmacy_admin.py, _create_pharmacy_admin_2.py, test_admin_dashboard_metrics.py, test_admin_earnings.py, test_admin_panel.py, test_admin_row_builder_performance.py, test_articles_feed.py, test_community.py, test_community_feed_performance.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `roles` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | AutoField | False |  | no |  |  |
| `name` | CharField | False |  | yes |  |  |
| `panel_type` | CharField | True |  | no |  |  |
| `description` | TextField | True |  | no |  |  |
| `permissions` | JSONField | False | dict | no |  |  |
| `tier_level` | SmallIntegerField | True |  | no |  |  |
| `is_system` | BooleanField | False | False | no |  |  |
| `hourly_rate_range_min` | DecimalField | True |  | no |  | Uploaded file/URL |
| `hourly_rate_range_max` | DecimalField | True |  | no |  | Uploaded file/URL |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### users.User

- **Used by APIs/views (source modules referencing the model):** admin.py, admin_approvals.py, admin_cashouts.py, admin_extra.py, admin_feed_chat.py, admin_finance.py, admin_pharmacy.py, admin_pharmacy_chat.py, admin_pharmacy_metrics.py, admin_shifts.py, admin_support.py, admin_views.py, auth.py, catalogue_views.py …
- **Tests referencing the model:** _create_missing_admin_accounts.py, _create_pharmacy_admin.py, _create_pharmacy_admin_2.py, test_admin_dashboard_metrics.py, test_admin_earnings.py, test_admin_pagination_performance.py, test_admin_panel.py, test_admin_row_builder_performance.py, test_articles_feed.py, test_community.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `users` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** account_status
- **Audit fields:** email_verified_at, phone_verified_at, created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `email` | CharField | False |  | yes |  | PII |
| `phone` | CharField | False |  | yes |  | PII |
| `password` | CharField | False |  | yes |  | Internal/secret |
| `full_name` | CharField | False |  | yes |  |  |
| `profile_photo_url` | TextField | True |  | no |  | Uploaded file, Uploaded file/URL |
| `date_of_birth` | DateField | False |  | yes |  |  |
| `present_address` | TextField | False |  | yes |  | PII/Location |
| `national_id_number` | CharField | True |  | no |  | PII+ID document |
| `national_id_photo_url` | TextField | True |  | no |  | PII+ID document, Uploaded file, Uploaded file/URL |
| `government_id_type` | CharField | True |  | no |  |  |
| `selfie_verification_url` | TextField | True |  | no |  | ID document, Uploaded file/URL |
| `preferred_language` | CharField | True | en | no |  |  |
| `emergency_contact_name` | CharField | True |  | no |  |  |
| `emergency_contact_phone` | CharField | True |  | no |  | PII |
| `two_factor_secret` | CharField | True |  | no |  | Internal/secret |
| `two_factor_enabled` | BooleanField | True | False | no |  |  |
| `bank_mobile_payment_details` | JSONField | True |  | no |  | Financial |
| `location_service_area` | TextField | True |  | no |  |  |
| `consent_terms` | BooleanField | False | False | no |  |  |
| `consent_background_check` | BooleanField | True | False | no |  |  |
| `account_status` | CharField | True | pending | no |  |  |
| `is_verified` | BooleanField | True | False | no |  |  |
| `email_verified_at` | DateTimeField | True |  | no |  | PII |
| `phone_verified_at` | DateTimeField | True |  | no |  | PII |
| `created_at` | DateTimeField | True |  | no |  |  |
| `updated_at` | DateTimeField | True |  | no |  |  |

### users.UserRole

- **Used by APIs/views (source modules referencing the model):** admin_views.py
- **Tests referencing the model:** _create_missing_admin_accounts.py, _create_pharmacy_admin.py, _create_pharmacy_admin_2.py, test_articles_feed.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `user_roles` (managed=False)
- **Primary key:** `pk`
- **Unique constraints:** ['user', 'role']
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** assigned_at, assigned_by

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `user` | ForeignKey | False |  | yes | users.User / DO_NOTHING |  |
| `role` | ForeignKey | False |  | yes | users.Role / DO_NOTHING |  |
| `assigned_at` | DateTimeField | True |  | no |  |  |
| `assigned_by` | ForeignKey | True |  | no | users.User / DO_NOTHING |  |

### verification.SignupDocument

- **Used by APIs/views (source modules referencing the model):** documents.py, serializers.py, status.py, views.py
- **Tests referencing the model:** test_private_documents.py, test_profile_photo.py, test_signup_documents.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `signup_documents` (managed=True)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** signup_docu_user_id_83e539_idx
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** uploaded_at, claimed_at, verified_by, verified_at, created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `user` | ForeignKey | True |  | no | users.User / CASCADE |  |
| `document_type` | CharField | False | other | no |  | Uploaded file |
| `file_path` | CharField | False |  | yes |  | Uploaded file |
| `token` | TextField | False |  | yes |  |  |
| `content_type` | CharField | False |  | no |  |  |
| `original_filename` | CharField | False |  | no |  | Uploaded file |
| `uploaded_at` | DateTimeField | False |  | yes |  |  |
| `claimed_at` | DateTimeField | True |  | no |  |  |
| `is_verified` | BooleanField | False | False | no |  |  |
| `verified_by` | ForeignKey | True |  | no | users.User / SET_NULL |  |
| `verified_at` | DateTimeField | True |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### workers.Worker

- **Used by APIs/views (source modules referencing the model):** labor_views.py, services.py, views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py, test_labour_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `workers` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / CASCADE |  |
| `full_name` | CharField | False |  | yes |  |  |
| `phone` | CharField | False |  | no |  | PII |
| `job_role` | CharField | False |  | yes |  |  |
| `daily_wage` | DecimalField | False |  | yes |  | Financial |
| `join_date` | DateField | False |  | yes |  |  |
| `status` | CharField | False | active | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |

### workers.WorkerAttendance

- **Used by APIs/views (source modules referencing the model):** labor_views.py, views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py, test_labour_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `worker_attendance` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** unique_worker_attendance
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `worker` | ForeignKey | False |  | yes | workers.Worker / CASCADE |  |
| `attendance_date` | DateField | False |  | yes |  |  |
| `status` | CharField | False |  | yes |  |  |
| `check_in_time` | TimeField | True |  | no |  |  |
| `check_out_time` | TimeField | True |  | no |  |  |
| `notes` | TextField | False |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### workers.WorkerPayment

- **Used by APIs/views (source modules referencing the model):** labor_views.py, services.py, views.py
- **Tests referencing the model:** test_dashboard_integrity_and_seed_idempotency.py, test_labour_payment.py
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `worker_payments` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** —
- **Audit fields:** created_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `worker` | ForeignKey | False |  | yes | workers.Worker / CASCADE |  |
| `amount` | DecimalField | False |  | yes |  | Financial |
| `payment_date` | DateField | False |  | yes |  | Financial |
| `payment_method` | CharField | False |  | yes |  | Financial |
| `period_start` | DateField | False |  | yes |  |  |
| `period_end` | DateField | False |  | yes |  |  |
| `notes` | TextField | False |  | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |

### workers.WorkerTask

- **Used by APIs/views (source modules referencing the model):** — (not referenced by any view module)
- **Tests referencing the model:** none found
- **Used by Flutter screens:** via the APIs above (Flutter holds no model classes of its own; see FEATHERFLOW_FEATURE_MATRIX.md)
- **Deletion behaviour:** see FK table (on_delete column); `DO_NOTHING` on unmanaged tables means the database FK constraint decides (typically RESTRICT/NO ACTION unless the schema SQL declares CASCADE).

- **Table:** `worker_tasks` (managed=False)
- **Primary key:** `id`
- **Unique constraints:** —
- **Constraints:** —
- **Indexes:** —
- **Uploaded files:** none as FileField (URL/path text fields only)
- **Status fields:** status
- **Audit fields:** created_at, updated_at

| Field | Type | Null | Default | Required | FK target / on_delete | Sensitivity |
|---|---|---|---|---|---|---|
| `id` | UUIDField | False | uuid4 | no |  |  |
| `worker` | ForeignKey | False |  | yes | workers.Worker / CASCADE |  |
| `farm` | ForeignKey | False |  | yes | farms.Farm / CASCADE |  |
| `task_name` | CharField | False |  | yes |  |  |
| `description` | TextField | False |  | no |  |  |
| `assigned_date` | DateField | False |  | yes |  |  |
| `due_date` | DateField | True |  | no |  |  |
| `status` | CharField | False | pending | no |  |  |
| `created_at` | DateTimeField | False |  | no |  |  |
| `updated_at` | DateTimeField | False |  | no |  |  |


## Coverage map — required data areas vs. actual schema

Row counts are from the live dev DB (pre-seed snapshot unless stated).

| Domain | Data area | Table(s) found | Assessment |
|---|---|---|---|
| Identity & access | User/account | users, user_roles, roles | Present |
|  | Roles / permissions | roles.permissions (JSON), role_permissions, permissions (legacy, 0 rows) | Present (the JSON map is the source of truth; `permissions`/`role_permissions` tables unused) |
|  | Sessions / tokens | token_blacklist_outstandingtoken, token_blacklist_blacklistedtoken (django_session unused: 0) | Present — **4,784 outstanding tokens, no purge job** (growth) |
|  | Profiles | farmer_profiles, doctor_profiles, delivery_profiles, pharmacy_organizations, feed_owner_profiles, researcher_profiles, admin_profiles; `pharmacist_profiles` exists (0 rows, no Django model) | Present |
|  | Verification | signup_documents (223), admin_approval_queue, profile_change_applications; users.is_verified, email_verified_at, phone_verified_at | Present |
|  | Login history | activity_logs (module=auth "Login success/failed for ...") | Partial — no dedicated login-history table |
|  | Account status | users.account_status | Present |
|  | Two-factor | users.two_factor_secret / two_factor_enabled | Columns present; **no 2FA flow found in API or Flutter** |
|  | Audit logs | activity_logs (7.3k), admin_payments, backend_admin_records, django_admin_log (0) | Present |
| Farmer & farm | Farm profile / location / photos | farms, farmer_profiles (farm_location, farm_address, farm_photos) | Present |
|  | Flock/batch, bird counts, breed, age | flocks (11), sheds (8), flock_events (1) | Present |
|  | Mortality / vaccine history / biosecurity notes | flock_events (event type), farmer_profiles | **Partial** — no dedicated mortality, vaccine-history or biosecurity-notes tables |
|  | Workers / labour payments | workers, worker_attendance, worker_payments, worker_tasks (0) | Present |
|  | Feed / medicine records | feed_stock, feed_consumption, feed_schedules (0), expenses (category) | Present |
|  | Revenue / expenses / loans / tax / cashout | revenues (36), revenue_entries (0), revenue_sources, expenses (70), expense_categories, loans, loan_installments, tax_profiles, tax_payments, tax_records (0), cashout_reviews, payments | Present; `revenue_entries` and `tax_records` empty |
|  | Notifications | notifications (11,572 rows) | Present — unbounded growth |
| Pharmacy | Organization / owner / verification | pharmacy_organizations (5), profiles, signup_documents | Present |
|  | Employee roster | pharmacy_employees (0) | Present, empty |
|  | Medicines / categories / images / inventory | pharmacy_medicines (0), pharmacy_catalogue_medicines (13), pharmacy_expiry_alerts (0), JSON `backend_admin_records` bridge | Present but **pharmacy_medicines is empty; live catalogue is `pharmacy_catalogue_medicines` + JSON records** (dual model) |
|  | Orders / items / deliveries | medicine_orders (0), medicine_order_items (0), `backend_admin_records` (orders as JSON), delivery_orders | **Orders live in JSON bridge records; relational order tables are empty** |
|  | Sales / commission / settlements / appeals | pharmacy_sales (0), pharmacy_commissions (0), pharmacy_settlements (0), pharmacy_appeals (0) | Present, **all empty in the dev DB** -> Pharmacy Admin money screens show zeros |
|  | Chat / reports / audits | conversations, messages, activity_logs | Present |
| Feed marketplace | Products / images / categories / stock / suppliers | feed_products (26), feed_companies (4), feed_types, feed_stock (15), feed_stock_movements (3) | Present |
|  | Feed orders / items / revenue / delivery / proof | delivery_orders (+ JSON order records), expense/revenue mirrors (migration expenses/0003_source_order_mirrors), delivery_orders proof fields | Present (orders as bridge records; **no feed_order_items table**) |
|  | Feed owner / admin chat | feed_owner_profiles, conversations, messages | Present |
| Veterinary | Doctor profile / availability / verification | doctor_profiles (9), doctor_availability_slots (12), signup_documents | Present |
|  | Consultation / case / symptoms / diagnosis / treatment | consultations (29), consultation_case_details (1), consultation_notes (1), consultation_status_history (19) | Present |
|  | Prescription / follow-up | clinical_prescriptions (0), clinical_prescription_items (0), prescriptions (0), follow_ups (0) | Present, **empty — no live data** |
|  | Chat / video / ratings / payments | conversations, messages, video_calls (0), doctor_earnings (2), doctor_payout_requests (0), payments | Present; video_calls empty (Jitsi links are generated, not stored) |
| Research & content | Researcher profile / credentials | researcher_profiles (4), profile_change_applications (3) | Present |
|  | Papers/articles/news/innovation/documents | articles (22; content_type distinguishes), article_authors (0), article_tags (12), research_tags (26), article_version_snapshots (7) | Present; co-authors table empty |
|  | Review workflow / revisions / versions | articles.status (draft/pending_review/needs_revision/published), article_version_snapshots | Present |
|  | Bookmarks / views / downloads | bookmarks (17), articles.views_count | Partial — **no download counter** |
| Community | Posts / media / comments / reactions / reposts / hashtags / mentions | posts (31), comments (27), reactions (14), post_reposts (0), hashtags (0), post_hashtags (0), posts.media_urls/tags/mentions (JSON) | Present (hashtag tables unused: tags stored as JSON on posts) |
|  | Follows / bookmarks / reports / blocks / mutes / polls | follows (8), bookmarks, reports (1), user_blocks (0), community_mutes (0), poll_votes (0), posts.poll_options | Present |
|  | Moderation records / official posts | posts.status (active/removed), posts.is_official/is_pinned, reports, activity_logs | Present |
| Delivery | Profile / vehicle / license / availability / attendance | delivery_profiles (7), delivery_vehicle_details (0), delivery_attendance (6) | Present; vehicle details table empty |
|  | Assignments / location / status history / proof / OTP | delivery_orders (36; pickup/delivery lat/lng, proof), no status-history table, **no OTP/signature storage table** | Partial (SignaturePadScreen exists in Flutter) |
|  | Earnings / payouts / bonuses / penalties / ratings | delivery_earnings (9), admin payroll tables; no bonus/penalty table | Partial |
| Subscriptions & payments | Plans / subscriptions / payments / gateway / refunds / receipts | subscription_plans, subscriptions, billing_payment_intents (6), billing_webhook_events (0), payments (7; status `refunded` exists), consultation receipts generated on the fly | Present; **no dedicated refunds table** (status on payments), no stored receipts table |

### Sensitive data classification (summary)

| Class | Examples (table.column) | Exposure observed |
|---|---|---|
| PII | users.email/phone/present_address/date_of_birth/emergency_contact_*, workers.phone | `GET /api/auth/users/<id>/` is owner-only (verified); the farmer pharmacy list returns pharmacy email/phone to every farmer |
| ID documents | users.national_id_photo_url, selfie_verification_url, signup_documents.*, license/certificate URLs | served through signed, expiring `/api/auth/registration-documents/<token>/` URLs; private-media app |
| Financial | expenses.amount, revenues, loans, payments, admin_payments, delivery_earnings, pharmacy_settlements, users.bank_mobile_payment_details (JSON) | farmer finance endpoints ownership-checked (IDOR sweep clean); admin finance gated by `finance`/`cashouts` modules |
| Medical/veterinary | consultations.*, consultation_case_details, disease_scans, prescriptions | receipts/clinical results/video limited to participants (verified); scans owner-only |
| Location | farms/farmer_profiles.farm_location, doctor lat/lng, delivery_orders pickup/delivery lat/lng, pharmacy_location | vet lat/lng + address exposed to every farmer by design (Find Vet) |
| Internal/admin-only | users.two_factor_secret, password hash, admin_profiles.*, activity_logs.ip_address, roles.permissions | password hash never serialised; audit logs scoped per admin role; **dashboard recent-activity leaks auth events across roles (F-SEC-04)** |
| Public/community-visible | posts, comments, author name/role/badge, published articles (anonymous read) | published only; raw HTML not sanitised on write (F-SEC-05) |