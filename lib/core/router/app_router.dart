import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../network/auth_service.dart';
import '../network/user_updates_service.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/signup_screen.dart';
import '../../features/auth/presentation/screens/role_selection_screen.dart';
import '../../features/auth/presentation/screens/farmer_signup_screen.dart';
import '../../features/auth/presentation/screens/doctor_signup_screen.dart';
import '../../features/auth/presentation/screens/delivery_signup_screen.dart';
import '../../features/auth/presentation/screens/pharmacy_signup_screen.dart';
import '../../features/auth/presentation/screens/researcher_signup_screen.dart';
import '../../features/auth/presentation/screens/admin_signup_screen.dart';
import '../../features/auth/presentation/screens/otp_verification_screen.dart';
import '../../features/auth/presentation/screens/password_reset_screen.dart';
import '../../features/auth/presentation/widgets/signup_widgets.dart';
import '../../features/farmer/presentation/screens/farmer_dashboard_screen.dart';
import '../../features/farmer/presentation/screens/cost_management_screen.dart';
import '../../features/farmer/presentation/screens/expense_list_screen.dart';
import '../../features/farmer/presentation/screens/revenue_list_screen.dart';
import '../../features/farmer/presentation/screens/loan_screen.dart';
import '../../features/farmer/presentation/screens/inventory_screen.dart';
import '../../features/farmer/presentation/screens/reports_screen.dart';
import '../../features/farmer/presentation/screens/feed_management_screen.dart';
import '../../features/farmer/presentation/screens/flock_age_chart_screen.dart';
import '../../features/farmer/presentation/screens/flock_detail_screen.dart';
import '../../features/farmer/presentation/screens/tax_summary_screen.dart';
import '../../features/farmer/presentation/screens/tax_calculation_screen.dart';
import '../../features/farmer/presentation/screens/tax_profile_screen.dart';
import '../../features/farmer/presentation/screens/tax_payment_screen.dart';
import '../../features/farmer/presentation/screens/disease_detection_screen.dart';
import '../../features/farmer/presentation/screens/find_vet_screen.dart';
import '../../features/farmer/presentation/screens/labor_management_screen.dart';
import '../../features/farmer/presentation/screens/labour_payment_flow_screens.dart';
import '../../features/farmer/data/models/labour_payment_models.dart';
import '../../features/farmer/presentation/screens/farmer_profile_screen.dart';
import '../../features/doctor/presentation/screens/doctor_dashboard_screen.dart';
import '../../features/doctor/presentation/screens/doctor_appointments_screen.dart';
import '../../features/doctor/presentation/screens/doctor_messenger_screen.dart';
import '../../features/doctor/presentation/screens/doctor_case_notes_screen.dart';
import '../../features/doctor/presentation/screens/doctor_prescriptions_screen.dart';
import '../../features/doctor/presentation/screens/doctor_earnings_screen.dart';
import '../../features/doctor/presentation/screens/doctor_followups_screen.dart';
import '../../features/doctor/presentation/screens/doctor_video_screen.dart';
import '../../features/pharmacy/presentation/screens/pharmacy_dashboard_screen.dart';
import '../../features/pharmacy/presentation/screens/pharmacy_catalogue_screen.dart';
import '../../features/pharmacy/presentation/screens/pharmacy_inventory_screen.dart';
import '../../features/pharmacy/presentation/screens/pharmacy_orders_screen.dart';
import '../../features/pharmacy/presentation/screens/pharmacy_suppliers_screen.dart';
import '../../features/pharmacy/presentation/screens/pharmacy_analytics_screen.dart';
import '../../features/farmer/presentation/screens/farmer_pharmacy_screen.dart';
import '../../features/farmer/presentation/screens/farmer_feed_marketplace_screen.dart';
import '../../features/delivery/presentation/screens/delivery_dashboard_screen.dart';
import '../../features/delivery/presentation/screens/delivery_orders_screen.dart';
import '../../features/delivery/presentation/screens/delivery_map_screen.dart';
import '../../features/delivery/presentation/screens/delivery_earnings_screen.dart';
import '../../features/delivery/presentation/screens/delivery_attendance_screen.dart';
import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/admin/presentation/screens/admin_users_screen.dart';
import '../../features/admin/presentation/screens/admin_doctors_screen.dart';
import '../../features/admin/presentation/screens/admin_delivery_screen.dart';
import '../../features/admin/presentation/screens/admin_pharmacy_screen.dart';
import '../../features/admin/presentation/screens/admin_feed_screen.dart';
import '../../features/admin/presentation/screens/admin_feed_clients_screen.dart';
import '../../features/admin/presentation/screens/admin_content_screen.dart';
import '../../features/admin/presentation/screens/admin_finance_screen.dart';
import '../../features/admin/presentation/screens/admin_community_screen.dart';
import '../../features/admin/presentation/screens/admin_team_screen.dart';
import '../../features/admin/presentation/screens/admin_support_screen.dart';
import '../../features/admin/presentation/screens/admin_profile_screen.dart';
import '../../features/admin/presentation/screens/admin_admins_screen.dart';
import '../../features/admin/presentation/screens/admin_approvals_screen.dart';
import '../../features/admin/presentation/screens/admin_audit_screen.dart';
import '../../features/admin/presentation/screens/admin_oversight_screen.dart';
import '../../features/admin/presentation/screens/admin_payroll_screen.dart';
import '../../features/research/presentation/screens/research_dashboard_screen.dart';
import '../../features/research/presentation/screens/research_papers_screen.dart';
import '../../features/research/presentation/screens/new_paper_screen.dart';
import '../../features/research/presentation/screens/research_diseases_screen.dart';
import '../../features/research/presentation/screens/new_disease_update_screen.dart';
import '../../features/research/presentation/screens/researcher_profile_screen.dart';
import '../../features/research/presentation/screens/innovation_screen.dart';
import '../../features/research/presentation/screens/new_innovation_screen.dart';
import '../../features/research/presentation/screens/research_search_screen.dart';
import '../../features/research/presentation/screens/collaboration_screen.dart';
import '../../features/research/presentation/screens/research_analytics_screen.dart';
import '../../features/research/presentation/screens/review_area_screen.dart';
import '../../features/community/presentation/screens/community_feed_screen.dart';
import '../../features/community/presentation/screens/community_post_screen.dart';
import '../../features/community/presentation/screens/community_notifications_screen.dart';
import '../../features/community/presentation/screens/community_profile_screen.dart';
import '../../features/community/presentation/screens/community_search_screen.dart';
import '../../features/community/presentation/screens/create_post_screen.dart';
import '../../features/farmer/presentation/screens/subscription_screen.dart';
import '../../features/farmer/presentation/screens/subscription_flow_screens.dart';
import '../../features/farmer/data/models/subscription_models.dart'
    show SubPlan, PaymentIntent;
import '../../features/paper_portal/paper_portal_router.dart';

class AppRoutes {
  AppRoutes._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const signup = '/signup';
  static const roleSelection = '/role-selection';

  static const farmerSignup = '/signup/farmer';
  static const doctorSignup = '/signup/doctor';
  static const pharmacySignup = '/signup/pharmacy';
  static const deliverySignup = '/signup/delivery';
  static const researcherSignup = '/signup/researcher';
  static const adminSignup = '/signup/admin';
  static const registrationPending = '/signup/pending';
  static const verifyContact = '/verify';
  static const passwordReset = '/reset-password';

  static const farmerDashboard = '/farmer';
  static const costManagement = '/farmer/cost-management';
  static const costExpenses = '/farmer/cost-management/expenses';
  static const costRevenue = '/farmer/cost-management/revenue';
  static const costLoans = '/farmer/cost-management/loans';
  static const costInventory = '/farmer/cost-management/inventory';
  static const costReports = '/farmer/cost-management/reports';
  static const feedManagement = '/farmer/feed-management';
  static const tax = '/farmer/tax';
  static const taxCalculator = '/farmer/tax/calculator';
  static const taxProfile = '/farmer/tax/profile';
  static const taxPayments = '/farmer/tax/payments';
  static const diseaseDetection = '/farmer/disease-detection';
  // Unified "Find Vet" feature (merges the old separate "Find Vet" / vet-map
  // and "My Consultations" screens into Discover Vets + My Consultations
  // tabs). The old paths below still resolve — they redirect here.
  static const findVet = '/farmer/find-vet';
  static const findVetDiscover = '/farmer/find-vet/discover';
  static const findVetConsultations = '/farmer/find-vet/consultations';
  static const findVetChats = '/farmer/find-vet/chats';
  static const vetMap = '/farmer/vet-map';
  static const farmerConsultations = '/farmer/consultations';
  static const laborManagement = '/farmer/labor';
  static const farmerProfile = '/farmer/profile';

  static const doctorDashboard = '/doctor';
  static const doctorAppointments = '/doctor/appointments';
  static const doctorMessenger = '/doctor/messenger';
  static const doctorCaseNotes = '/doctor/case-notes';
  static const doctorPrescriptions = '/doctor/prescriptions';
  static const doctorEarnings = '/doctor/earnings';
  static const doctorFollowups = '/doctor/followups';
  static const doctorVideo = '/doctor/video';

  static const pharmacyDashboard = '/pharmacy';
  static const pharmacyCatalogue = '/pharmacy/catalogue';
  static const pharmacyInventory = '/pharmacy/inventory';
  static const pharmacyOrders = '/pharmacy/orders';
  static const pharmacySuppliers = '/pharmacy/suppliers';
  static const pharmacyAnalytics = '/pharmacy/analytics';

  static const deliveryDashboard = '/delivery';
  static const deliveryOrders = '/delivery/orders';
  static const deliveryMap = '/delivery/map';
  static const deliveryEarnings = '/delivery/earnings';
  static const deliveryAttendance = '/delivery/attendance';

  static const adminDashboard = '/admin';
  static const adminUsers = '/admin/users';
  static const adminDoctors = '/admin/doctors';
  static const adminDelivery = '/admin/delivery';
  static const adminPharmacy = '/admin/pharmacy';
  static const adminContent = '/admin/content';
  static const adminFinance = '/admin/finance';
  static const adminCommunity = '/admin/community';
  static const adminTeam = '/admin/team';
  static const adminSupport = '/admin/support';
  static const adminAdmins = '/admin/admins';
  static const adminApprovals = '/admin/approvals';
  static const adminAudit = '/admin/audit';
  static const adminOversight = '/admin/oversight';
  static const adminPayroll = '/admin/payroll';
  static const adminProfile = '/admin/profile';

  static const researchDashboard = '/research';
  static const researchPapers = '/research/papers';
  static const newPaper = '/research/new-paper';
  static const researchDiseases = '/research/diseases';
  static const newDiseaseUpdate = '/research/new-disease-update';
  static const researchProfile = '/research/profile';
  static const researchInnovations = '/research/innovations';
  static const newInnovation = '/research/new-innovation';
  static const researchSearch = '/research/search';
  static const researchCollaboration = '/research/collaboration';
  static const researchAnalytics = '/research/analytics';
  static const researchReview = '/research/review';

  static const communityFeed = '/community';
  static const communityPost = '/community/post/:postId';
  static const createPost = '/community/create';

  static const subscription = '/subscription';
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Page not found'),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The requested page could not be found.'),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => context.go(AppRoutes.splash),
              child: const Text('Go to home'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _redirect(BuildContext context, GoRouterState state) async {
  final location = state.matchedLocation;
  final isPublicRoute = location == AppRoutes.splash ||
      location == AppRoutes.onboarding ||
      location == AppRoutes.login ||
      location == AppRoutes.signup ||
      location == AppRoutes.roleSelection ||
      location == AppRoutes.verifyContact ||
      location == AppRoutes.passwordReset ||
      location.startsWith('/signup/');

  final isAuthenticated = await AuthService.instance.isAuthenticated();
  if (!isAuthenticated && !isPublicRoute) {
    return AppRoutes.login;
  }

  // An admin suspended/revoked a user mid-session — bounce them out.
  if (isAuthenticated &&
      !isPublicRoute &&
      UserUpdatesService.instance.accessRevoked) {
    await AuthService.instance.clearSession();
    return '${AppRoutes.login}?revoked=1';
  }

  if (isAuthenticated &&
      (location == AppRoutes.login ||
          location == AppRoutes.signup ||
          location == AppRoutes.roleSelection ||
          location == AppRoutes.splash ||
          location == AppRoutes.onboarding)) {
    final session = await AuthService.instance.getStoredSession();
    final role = session?.user.roles.isNotEmpty == true
        ? session!.user.roles.first
        : 'farmer';
    return await AuthService.instance.getRoleDestination(role);
  }

  return null;
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.login,
  debugLogDiagnostics: false,
  refreshListenable: UserUpdatesService.instance,
  redirect: _redirect,
  errorBuilder: (context, state) => const _NotFoundScreen(),
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      builder: (BuildContext context, GoRouterState state) =>
          const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (BuildContext context, GoRouterState state) =>
          const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      name: 'login',
      builder: (BuildContext context, GoRouterState state) =>
          const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.signup,
      name: 'signup',
      builder: (BuildContext context, GoRouterState state) =>
          const SignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.roleSelection,
      name: 'roleSelection',
      builder: (BuildContext context, GoRouterState state) =>
          const RoleSelectionScreen(),
    ),
    GoRoute(
      path: AppRoutes.farmerSignup,
      name: 'farmerSignup',
      builder: (BuildContext context, GoRouterState state) =>
          const FarmerSignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.doctorSignup,
      name: 'doctorSignup',
      builder: (BuildContext context, GoRouterState state) =>
          const DoctorSignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.pharmacySignup,
      name: 'pharmacySignup',
      builder: (BuildContext context, GoRouterState state) =>
          const PharmacySignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.deliverySignup,
      name: 'deliverySignup',
      builder: (BuildContext context, GoRouterState state) =>
          const DeliverySignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.researcherSignup,
      name: 'researcherSignup',
      builder: (BuildContext context, GoRouterState state) =>
          const ResearcherSignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.adminSignup,
      name: 'adminSignup',
      builder: (BuildContext context, GoRouterState state) =>
          const AdminSignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.registrationPending,
      name: 'registrationPending',
      builder: (BuildContext context, GoRouterState state) =>
          RegistrationPendingScreen(
        message: state.extra is String
            ? state.extra as String
            : 'Your account is pending approval. You will be able to sign in once it is approved.',
      ),
    ),
    GoRoute(
      path: AppRoutes.verifyContact,
      name: 'verifyContact',
      builder: (BuildContext context, GoRouterState state) {
        final args = state.extra is Map ? state.extra as Map : const {};
        return OtpVerificationScreen(
          email: args['email']?.toString() ?? '',
          channel: args['channel']?.toString() ?? 'email',
          initialMessage: args['message']?.toString() ?? '',
          debugCode: args['debug_code']?.toString() ?? '',
          devDelivery: args['dev_delivery'] == true,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.passwordReset,
      name: 'passwordReset',
      builder: (BuildContext context, GoRouterState state) {
        final args = state.extra is Map ? state.extra as Map : const {};
        return PasswordResetScreen(
          initialEmail: args['email']?.toString() ?? '',
        );
      },
    ),
    GoRoute(
      path: AppRoutes.farmerDashboard,
      name: 'farmerDashboard',
      builder: (BuildContext context, GoRouterState state) =>
          const FarmerDashboardScreen(),
      routes: [
        GoRoute(
          path: 'cost-management',
          name: 'costManagement',
          builder: (BuildContext context, GoRouterState state) =>
              const CostManagementScreen(),
          routes: [
            GoRoute(
              path: 'expenses',
              name: 'costExpenses',
              builder: (BuildContext context, GoRouterState state) =>
                  ExpenseListScreen(category: state.extra as String?),
            ),
            GoRoute(
              path: 'revenue',
              name: 'costRevenue',
              builder: (BuildContext context, GoRouterState state) =>
                  const RevenueListScreen(),
            ),
            GoRoute(
              path: 'loans',
              name: 'costLoans',
              builder: (BuildContext context, GoRouterState state) =>
                  const LoanScreen(),
            ),
            GoRoute(
              path: 'inventory',
              name: 'costInventory',
              builder: (BuildContext context, GoRouterState state) =>
                  const InventoryScreen(),
            ),
            GoRoute(
              path: 'reports',
              name: 'costReports',
              builder: (BuildContext context, GoRouterState state) =>
                  const ReportsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: 'feed-management',
          name: 'feedManagement',
          builder: (BuildContext context, GoRouterState state) =>
              const FeedManagementScreen(),
          routes: [
            GoRoute(
              path: 'flocks',
              name: 'flockAgeChart',
              builder: (context, state) => const FlockAgeChartScreen(),
              routes: [
                GoRoute(
                  path: ':flockId',
                  name: 'flockDetail',
                  builder: (context, state) => FlockDetailScreen(
                    flockId: state.pathParameters['flockId']!,
                    initial: state.extra is Map<String, dynamic>
                        ? state.extra as Map<String, dynamic>
                        : null,
                  ),
                ),
              ],
            ),
            // Farmers order feed only through this e-commerce section inside
            // Feed Management — the old standalone `/farmer/order-feed` tile
            // was removed and now redirects here (see below).
            GoRoute(
              path: 'marketplace',
              name: 'feedManagementMarketplace',
              builder: (BuildContext context, GoRouterState state) =>
                  const FarmerFeedMarketplaceScreen(),
            ),
          ],
        ),
        GoRoute(
          path: 'tax',
          name: 'tax',
          builder: (BuildContext context, GoRouterState state) =>
              const TaxSummaryScreen(),
          routes: [
            GoRoute(
              path: 'calculator',
              name: 'taxCalculator',
              builder: (BuildContext context, GoRouterState state) =>
                  const TaxCalculationScreen(),
            ),
            GoRoute(
              path: 'profile',
              name: 'taxProfile',
              builder: (BuildContext context, GoRouterState state) =>
                  const TaxProfileScreen(),
            ),
            GoRoute(
              path: 'payments',
              name: 'taxPayments',
              builder: (BuildContext context, GoRouterState state) =>
                  const TaxPaymentScreen(),
            ),
          ],
        ),
        GoRoute(
          path: 'disease-detection',
          name: 'diseaseDetection',
          builder: (BuildContext context, GoRouterState state) =>
              const DiseaseDetectionScreen(),
        ),
        GoRoute(
          path: 'find-vet',
          name: 'findVet',
          builder: (BuildContext context, GoRouterState state) =>
              const FindVetScreen(),
          routes: [
            GoRoute(
              path: 'discover',
              name: 'findVetDiscover',
              builder: (BuildContext context, GoRouterState state) =>
                  const FindVetScreen(),
            ),
            GoRoute(
              path: 'consultations',
              name: 'findVetConsultations',
              builder: (BuildContext context, GoRouterState state) =>
                  const FindVetScreen(initialTab: 1),
            ),
            GoRoute(
              path: 'chats',
              name: 'findVetChats',
              builder: (BuildContext context, GoRouterState state) =>
                  const FindVetScreen(initialTab: 2),
            ),
          ],
        ),
        // Legacy deep links from before the Find Vet / My Consultations
        // merge — old bookmarks, shared links and stored notification
        // targets still resolve, redirected to the unified feature instead
        // of 404ing (see CONSULTATION_INTEGRATION_AUDIT.md).
        GoRoute(
          path: 'vet-map',
          name: 'vetMap',
          redirect: (BuildContext context, GoRouterState state) {
            // Preserve `?disease=` from the old disease-detection deep link.
            final query = state.uri.query;
            return query.isEmpty
                ? AppRoutes.findVetDiscover
                : '${AppRoutes.findVetDiscover}?$query';
          },
        ),
        GoRoute(
          path: 'consultations',
          name: 'farmerConsultations',
          redirect: (BuildContext context, GoRouterState state) =>
              AppRoutes.findVetConsultations,
        ),
        GoRoute(
          path: 'labor',
          name: 'laborManagement',
          builder: (BuildContext context, GoRouterState state) =>
              const LaborManagementScreen(),
          routes: [
            GoRoute(
              path: 'pay-review',
              name: 'labourPayReview',
              builder: (context, state) => state.extra is List<LabourPaymentIntent>
                  ? LabourPayReviewScreen(intents: state.extra as List<LabourPaymentIntent>)
                  : labourPaymentExtraGuard(context),
            ),
            GoRoute(
              path: 'pay-method',
              name: 'labourPayMethod',
              builder: (context, state) => state.extra is List<LabourPaymentIntent>
                  ? LabourPaymentMethodScreen(intents: state.extra as List<LabourPaymentIntent>)
                  : labourPaymentExtraGuard(context),
            ),
            GoRoute(
              path: 'pay-checkout',
              name: 'labourPayCheckout',
              builder: (context, state) => state.extra is List<LabourPaymentIntent>
                  ? LabourCheckoutScreen(intents: state.extra as List<LabourPaymentIntent>)
                  : labourPaymentExtraGuard(context),
            ),
            GoRoute(
              path: 'pay-result',
              name: 'labourPayResult',
              builder: (context, state) => state.extra is List<LabourPaymentIntent>
                  ? LabourPaymentResultScreen(intents: state.extra as List<LabourPaymentIntent>)
                  : labourPaymentExtraGuard(context),
            ),
          ],
        ),
        GoRoute(
          path: 'profile',
          name: 'farmerProfile',
          builder: (BuildContext context, GoRouterState state) =>
              const FarmerProfileScreen(),
        ),
        GoRoute(
          path: 'pharmacy',
          name: 'farmerPharmacy',
          builder: (BuildContext context, GoRouterState state) =>
              const FarmerPharmacyScreen(),
        ),
        // Backward-compat: old deep links to the standalone "Order Feed"
        // tile now land on the same marketplace, nested inside Feed
        // Management, instead of breaking or duplicating the entry point.
        GoRoute(
          path: 'order-feed',
          redirect: (context, state) => '/farmer/feed-management/marketplace',
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.doctorDashboard,
      name: 'doctorDashboard',
      builder: (BuildContext context, GoRouterState state) =>
          const DoctorDashboardScreen(),
      routes: [
        GoRoute(
          path: 'appointments',
          name: 'doctorAppointments',
          builder: (BuildContext context, GoRouterState state) =>
              const DoctorAppointmentsScreen(),
        ),
        GoRoute(
          path: 'messenger',
          name: 'doctorMessenger',
          builder: (BuildContext context, GoRouterState state) =>
              const DoctorMessengerScreen(),
        ),
        GoRoute(
          path: 'case-notes',
          name: 'doctorCaseNotes',
          builder: (BuildContext context, GoRouterState state) =>
              const DoctorCaseNotesScreen(),
        ),
        GoRoute(
          path: 'prescriptions',
          name: 'doctorPrescriptions',
          builder: (BuildContext context, GoRouterState state) =>
              const DoctorPrescriptionsScreen(),
        ),
        GoRoute(
          path: 'earnings',
          name: 'doctorEarnings',
          builder: (BuildContext context, GoRouterState state) =>
              const DoctorEarningsScreen(),
        ),
        GoRoute(
          path: 'followups',
          name: 'doctorFollowups',
          builder: (BuildContext context, GoRouterState state) =>
              const DoctorFollowupsScreen(),
        ),
        GoRoute(
          path: 'video',
          name: 'doctorVideo',
          builder: (BuildContext context, GoRouterState state) =>
              const DoctorVideoScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.pharmacyDashboard,
      name: 'pharmacyDashboard',
      builder: (BuildContext context, GoRouterState state) =>
          const PharmacyDashboardScreen(),
      routes: [
        GoRoute(
          path: 'catalogue',
          name: 'pharmacyCatalogue',
          builder: (BuildContext context, GoRouterState state) =>
              const PharmacyCatalogueScreen(),
        ),
        GoRoute(
          path: 'inventory',
          name: 'pharmacyInventory',
          builder: (BuildContext context, GoRouterState state) =>
              const PharmacyInventoryScreen(),
        ),
        GoRoute(
          path: 'orders',
          name: 'pharmacyOrders',
          builder: (BuildContext context, GoRouterState state) =>
              const PharmacyOrdersScreen(),
        ),
        GoRoute(
          path: 'suppliers',
          name: 'pharmacySuppliers',
          builder: (BuildContext context, GoRouterState state) =>
              const PharmacySuppliersScreen(),
        ),
        GoRoute(
          path: 'analytics',
          name: 'pharmacyAnalytics',
          builder: (BuildContext context, GoRouterState state) =>
              const PharmacyAnalyticsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.deliveryDashboard,
      name: 'deliveryDashboard',
      builder: (BuildContext context, GoRouterState state) =>
          const DeliveryDashboardScreen(),
      routes: [
        GoRoute(
          path: 'orders',
          name: 'deliveryOrders',
          builder: (BuildContext context, GoRouterState state) =>
              const DeliveryOrdersScreen(),
        ),
        GoRoute(
          path: 'map',
          name: 'deliveryMap',
          builder: (BuildContext context, GoRouterState state) =>
              const DeliveryMapScreen(),
        ),
        GoRoute(
          path: 'earnings',
          name: 'deliveryEarnings',
          builder: (BuildContext context, GoRouterState state) =>
              const DeliveryEarningsScreen(),
        ),
        GoRoute(
          path: 'attendance',
          name: 'deliveryAttendance',
          builder: (BuildContext context, GoRouterState state) =>
              const DeliveryAttendanceScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.adminDashboard,
      name: 'adminDashboard',
      builder: (BuildContext context, GoRouterState state) =>
          const AdminDashboardScreen(),
      routes: [
        GoRoute(
          path: 'users',
          name: 'adminUsers',
          builder: (BuildContext context, GoRouterState state) =>
              AdminUsersScreen(
            initialFilter:
                state.extra is String ? state.extra as String : 'All',
          ),
        ),
        GoRoute(
          path: 'doctors',
          name: 'adminDoctors',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminDoctorsScreen(),
        ),
        GoRoute(
          path: 'delivery',
          name: 'adminDelivery',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminDeliveryScreen(),
        ),
        GoRoute(
          path: 'pharmacy',
          name: 'adminPharmacy',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminPharmacyScreen(),
        ),
        GoRoute(
          path: 'feed',
          name: 'adminFeed',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminFeedScreen(),
        ),
        GoRoute(
          path: 'feed-clients',
          name: 'adminFeedClients',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminFeedClientsScreen(),
        ),
        GoRoute(
          path: 'content',
          name: 'adminContent',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminContentScreen(),
        ),
        GoRoute(
          path: 'finance',
          name: 'adminFinance',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminFinanceScreen(),
        ),
        GoRoute(
          path: 'community',
          name: 'adminCommunity',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminCommunityScreen(),
        ),
        GoRoute(
          path: 'team',
          name: 'adminTeam',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminTeamScreen(),
        ),
        GoRoute(
          path: 'support',
          name: 'adminSupport',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminSupportScreen(),
        ),
        GoRoute(
          path: 'admins',
          name: 'adminAdmins',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminAdminsScreen(),
        ),
        GoRoute(
          path: 'approvals',
          name: 'adminApprovals',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminApprovalsScreen(),
        ),
        GoRoute(
          path: 'audit',
          name: 'adminAudit',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminAuditScreen(),
        ),
        GoRoute(
          path: 'oversight',
          name: 'adminOversight',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminOversightScreen(),
        ),
        GoRoute(
          path: 'payroll',
          name: 'adminPayroll',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminPayrollScreen(),
        ),
        GoRoute(
          path: 'profile',
          name: 'adminProfile',
          builder: (BuildContext context, GoRouterState state) =>
              const AdminProfileScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.researchDashboard,
      name: 'researchDashboard',
      builder: (BuildContext context, GoRouterState state) =>
          const ResearchDashboardScreen(),
      routes: [
        GoRoute(
          path: 'papers',
          name: 'researchPapers',
          builder: (BuildContext context, GoRouterState state) =>
              const ResearchPapersScreen(),
        ),
        GoRoute(
          path: 'new-paper',
          name: 'newPaper',
          builder: (BuildContext context, GoRouterState state) =>
              NewPaperScreen(
            paperId: state.extra is String ? state.extra as String : null,
          ),
        ),
        GoRoute(
          path: 'diseases',
          name: 'researchDiseases',
          builder: (BuildContext context, GoRouterState state) =>
              const ResearchDiseasesScreen(),
        ),
        GoRoute(
          path: 'new-disease-update',
          name: 'newDiseaseUpdate',
          builder: (BuildContext context, GoRouterState state) =>
              NewDiseaseUpdateScreen(
            updateId: state.extra is String ? state.extra as String : null,
          ),
        ),
        GoRoute(
          path: 'profile',
          name: 'researchProfile',
          builder: (BuildContext context, GoRouterState state) =>
              const ResearcherProfileScreen(),
        ),
        GoRoute(
          path: 'innovations',
          name: 'researchInnovations',
          builder: (BuildContext context, GoRouterState state) =>
              const InnovationScreen(),
        ),
        GoRoute(
          path: 'new-innovation',
          name: 'newInnovation',
          builder: (BuildContext context, GoRouterState state) =>
              NewInnovationScreen(
            innovationId: state.extra is String ? state.extra as String : null,
          ),
        ),
        GoRoute(
          path: 'search',
          name: 'researchSearch',
          builder: (BuildContext context, GoRouterState state) =>
              const ResearchSearchScreen(),
        ),
        GoRoute(
          path: 'collaboration',
          name: 'researchCollaboration',
          builder: (BuildContext context, GoRouterState state) =>
              const CollaborationScreen(),
        ),
        GoRoute(
          path: 'analytics',
          name: 'researchAnalytics',
          builder: (BuildContext context, GoRouterState state) =>
              const ResearchAnalyticsScreen(),
        ),
        GoRoute(
          path: 'review',
          name: 'researchReview',
          builder: (BuildContext context, GoRouterState state) =>
              const ReviewAreaScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.communityFeed,
      name: 'communityFeed',
      builder: (BuildContext context, GoRouterState state) =>
          const CommunityFeedScreen(),
      routes: [
        GoRoute(
          path: 'post/:postId',
          name: 'communityPost',
          builder: (BuildContext context, GoRouterState state) =>
              CommunityPostScreen(
            postId: state.pathParameters['postId']!,
          ),
        ),
        GoRoute(
          path: 'create',
          name: 'createPost',
          builder: (BuildContext context, GoRouterState state) =>
              const CreatePostScreen(),
        ),
        GoRoute(
          path: 'search',
          name: 'communitySearch',
          builder: (BuildContext context, GoRouterState state) =>
              CommunitySearchScreen(initialTag: state.uri.queryParameters['tag']),
        ),
        GoRoute(
          path: 'notifications',
          name: 'communityNotifications',
          builder: (BuildContext context, GoRouterState state) =>
              const CommunityNotificationsScreen(),
        ),
        GoRoute(
          path: 'user/:userId',
          name: 'communityProfile',
          builder: (BuildContext context, GoRouterState state) =>
              CommunityProfileScreen(userId: state.pathParameters['userId']!),
        ),
      ],
    ),
    ...paperPortalRoutes,
    GoRoute(
      path: AppRoutes.subscription,
      name: 'subscription',
      builder: (BuildContext context, GoRouterState state) =>
          const SubscriptionScreen(),
      routes: [
        GoRoute(
          path: 'review',
          name: 'subscriptionReview',
          builder: (context, state) {
            final e = state.extra;
            if (e is ({SubPlan plan, bool isDevMode})) {
              return PlanReviewScreen(plan: e.plan, isDevMode: e.isDevMode);
            }
            return subscriptionExtraGuard(context);
          },
        ),
        GoRoute(
          path: 'pay',
          name: 'subscriptionPay',
          builder: (context, state) => state.extra is PaymentIntent
              ? PaymentMethodScreen(intent: state.extra as PaymentIntent)
              : subscriptionExtraGuard(context),
        ),
        GoRoute(
          path: 'checkout',
          name: 'subscriptionCheckout',
          builder: (context, state) => state.extra is PaymentIntent
              ? CheckoutScreen(intent: state.extra as PaymentIntent)
              : subscriptionExtraGuard(context),
        ),
        GoRoute(
          path: 'result',
          name: 'subscriptionResult',
          builder: (context, state) => state.extra is PaymentIntent
              ? PaymentResultScreen(intent: state.extra as PaymentIntent)
              : subscriptionExtraGuard(context),
        ),
      ],
    ),
  ],
);
