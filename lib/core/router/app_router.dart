import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../network/auth_service.dart';
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
import '../../features/farmer/presentation/screens/farmer_dashboard_screen.dart';
import '../../features/farmer/presentation/screens/cost_management_screen.dart';
import '../../features/farmer/presentation/screens/feed_management_screen.dart';
import '../../features/farmer/presentation/screens/disease_detection_screen.dart';
import '../../features/farmer/presentation/screens/vet_map_screen.dart';
import '../../features/farmer/presentation/screens/labor_management_screen.dart';
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
import '../../features/pharmacy/presentation/screens/pharmacy_inventory_screen.dart';
import '../../features/pharmacy/presentation/screens/pharmacy_orders_screen.dart';
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
import '../../features/admin/presentation/screens/admin_content_screen.dart';
import '../../features/admin/presentation/screens/admin_finance_screen.dart';
import '../../features/admin/presentation/screens/admin_community_screen.dart';
import '../../features/admin/presentation/screens/admin_team_screen.dart';
import '../../features/admin/presentation/screens/admin_support_screen.dart';
import '../../features/admin/presentation/screens/admin_profile_screen.dart';
import '../../features/research/presentation/screens/research_dashboard_screen.dart';
import '../../features/research/presentation/screens/research_papers_screen.dart';
import '../../features/research/presentation/screens/new_paper_screen.dart';
import '../../features/research/presentation/screens/research_diseases_screen.dart';
import '../../features/research/presentation/screens/researcher_profile_screen.dart';
import '../../features/research/presentation/screens/innovation_screen.dart';
import '../../features/research/presentation/screens/research_search_screen.dart';
import '../../features/research/presentation/screens/collaboration_screen.dart';
import '../../features/research/presentation/screens/research_analytics_screen.dart';
import '../../features/research/presentation/screens/review_area_screen.dart';
import '../../features/community/presentation/screens/community_feed_screen.dart';
import '../../features/community/presentation/screens/community_post_screen.dart';
import '../../features/community/presentation/screens/create_post_screen.dart';
import '../../features/farmer/presentation/screens/subscription_screen.dart';
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

  static const farmerDashboard = '/farmer';
  static const costManagement = '/farmer/cost-management';
  static const feedManagement = '/farmer/feed-management';
  static const diseaseDetection = '/farmer/disease-detection';
  static const vetMap = '/farmer/vet-map';
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
  static const pharmacyInventory = '/pharmacy/inventory';
  static const pharmacyOrders = '/pharmacy/orders';

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
  static const adminProfile = '/admin/profile';

  static const researchDashboard = '/research';
  static const researchPapers = '/research/papers';
  static const newPaper = '/research/new-paper';
  static const researchDiseases = '/research/diseases';
  static const researchProfile = '/research/profile';
  static const researchInnovations = '/research/innovations';
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
      appBar: AppBar(title: const Text('Page not found')),
      body: const Center(
        child: Text('The requested page could not be found.'),
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
      location.startsWith('/signup/');

  final isAuthenticated = await AuthService.instance.isAuthenticated();
  if (!isAuthenticated && !isPublicRoute) {
    return AppRoutes.login;
  }

  if (isAuthenticated && (location == AppRoutes.login || location == AppRoutes.signup || location == AppRoutes.roleSelection || location == AppRoutes.splash || location == AppRoutes.onboarding)) {
    final session = await AuthService.instance.getStoredSession();
    final role = session?.user.roles.isNotEmpty == true ? session!.user.roles.first : 'farmer';
    return await AuthService.instance.getRoleDestination(role);
  }

  return null;
}

final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.login,
  debugLogDiagnostics: false,
  redirect: _redirect,
  errorBuilder: (context, state) => const _NotFoundScreen(),
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      name: 'splash',
      builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      name: 'onboarding',
      builder: (BuildContext context, GoRouterState state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      name: 'login',
      builder: (BuildContext context, GoRouterState state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.signup,
      name: 'signup',
      builder: (BuildContext context, GoRouterState state) => const SignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.roleSelection,
      name: 'roleSelection',
      builder: (BuildContext context, GoRouterState state) => const RoleSelectionScreen(),
    ),
    GoRoute(
      path: AppRoutes.farmerSignup,
      name: 'farmerSignup',
      builder: (BuildContext context, GoRouterState state) => const FarmerSignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.doctorSignup,
      name: 'doctorSignup',
      builder: (BuildContext context, GoRouterState state) => const DoctorSignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.pharmacySignup,
      name: 'pharmacySignup',
      builder: (BuildContext context, GoRouterState state) => const PharmacySignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.deliverySignup,
      name: 'deliverySignup',
      builder: (BuildContext context, GoRouterState state) => const DeliverySignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.researcherSignup,
      name: 'researcherSignup',
      builder: (BuildContext context, GoRouterState state) => const ResearcherSignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.adminSignup,
      name: 'adminSignup',
      builder: (BuildContext context, GoRouterState state) => const AdminSignupScreen(),
    ),
    GoRoute(
      path: AppRoutes.farmerDashboard,
      name: 'farmerDashboard',
      builder: (BuildContext context, GoRouterState state) => const FarmerDashboardScreen(),
      routes: [
        GoRoute(
          path: 'cost-management',
          name: 'costManagement',
          builder: (BuildContext context, GoRouterState state) => const CostManagementScreen(),
        ),
        GoRoute(
          path: 'feed-management',
          name: 'feedManagement',
          builder: (BuildContext context, GoRouterState state) => const FeedManagementScreen(),
        ),
        GoRoute(
          path: 'disease-detection',
          name: 'diseaseDetection',
          builder: (BuildContext context, GoRouterState state) => const DiseaseDetectionScreen(),
        ),
        GoRoute(
          path: 'vet-map',
          name: 'vetMap',
          builder: (BuildContext context, GoRouterState state) => const VetMapScreen(),
        ),
        GoRoute(
          path: 'labor',
          name: 'laborManagement',
          builder: (BuildContext context, GoRouterState state) => const LaborManagementScreen(),
        ),
        GoRoute(
          path: 'profile',
          name: 'farmerProfile',
          builder: (BuildContext context, GoRouterState state) => const FarmerProfileScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.doctorDashboard,
      name: 'doctorDashboard',
      builder: (BuildContext context, GoRouterState state) => const DoctorDashboardScreen(),
      routes: [
        GoRoute(
          path: 'appointments',
          name: 'doctorAppointments',
          builder: (BuildContext context, GoRouterState state) => const DoctorAppointmentsScreen(),
        ),
        GoRoute(
          path: 'messenger',
          name: 'doctorMessenger',
          builder: (BuildContext context, GoRouterState state) => const DoctorMessengerScreen(),
        ),
        GoRoute(
          path: 'case-notes',
          name: 'doctorCaseNotes',
          builder: (BuildContext context, GoRouterState state) => const DoctorCaseNotesScreen(),
        ),
        GoRoute(
          path: 'prescriptions',
          name: 'doctorPrescriptions',
          builder: (BuildContext context, GoRouterState state) => const DoctorPrescriptionsScreen(),
        ),
        GoRoute(
          path: 'earnings',
          name: 'doctorEarnings',
          builder: (BuildContext context, GoRouterState state) => const DoctorEarningsScreen(),
        ),
        GoRoute(
          path: 'followups',
          name: 'doctorFollowups',
          builder: (BuildContext context, GoRouterState state) => const DoctorFollowupsScreen(),
        ),
        GoRoute(
          path: 'video',
          name: 'doctorVideo',
          builder: (BuildContext context, GoRouterState state) => const DoctorVideoScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.pharmacyDashboard,
      name: 'pharmacyDashboard',
      builder: (BuildContext context, GoRouterState state) => const PharmacyDashboardScreen(),
      routes: [
        GoRoute(
          path: 'inventory',
          name: 'pharmacyInventory',
          builder: (BuildContext context, GoRouterState state) => const PharmacyInventoryScreen(),
        ),
        GoRoute(
          path: 'orders',
          name: 'pharmacyOrders',
          builder: (BuildContext context, GoRouterState state) => const PharmacyOrdersScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.deliveryDashboard,
      name: 'deliveryDashboard',
      builder: (BuildContext context, GoRouterState state) => const DeliveryDashboardScreen(),
      routes: [
        GoRoute(
          path: 'orders',
          name: 'deliveryOrders',
          builder: (BuildContext context, GoRouterState state) => const DeliveryOrdersScreen(),
        ),
        GoRoute(
          path: 'map',
          name: 'deliveryMap',
          builder: (BuildContext context, GoRouterState state) => const DeliveryMapScreen(),
        ),
        GoRoute(
          path: 'earnings',
          name: 'deliveryEarnings',
          builder: (BuildContext context, GoRouterState state) => const DeliveryEarningsScreen(),
        ),
        GoRoute(
          path: 'attendance',
          name: 'deliveryAttendance',
          builder: (BuildContext context, GoRouterState state) => const DeliveryAttendanceScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.adminDashboard,
      name: 'adminDashboard',
      builder: (BuildContext context, GoRouterState state) => const AdminDashboardScreen(),
      routes: [
        GoRoute(
          path: 'users',
          name: 'adminUsers',
          builder: (BuildContext context, GoRouterState state) => AdminUsersScreen(
            initialFilter: state.extra is String ? state.extra as String : 'All',
          ),
        ),
        GoRoute(
          path: 'doctors',
          name: 'adminDoctors',
          builder: (BuildContext context, GoRouterState state) => const AdminDoctorsScreen(),
        ),
        GoRoute(
          path: 'delivery',
          name: 'adminDelivery',
          builder: (BuildContext context, GoRouterState state) => const AdminDeliveryScreen(),
        ),
        GoRoute(
          path: 'pharmacy',
          name: 'adminPharmacy',
          builder: (BuildContext context, GoRouterState state) => const AdminPharmacyScreen(),
        ),
        GoRoute(
          path: 'content',
          name: 'adminContent',
          builder: (BuildContext context, GoRouterState state) => const AdminContentScreen(),
        ),
        GoRoute(
          path: 'finance',
          name: 'adminFinance',
          builder: (BuildContext context, GoRouterState state) => const AdminFinanceScreen(),
        ),
        GoRoute(
          path: 'community',
          name: 'adminCommunity',
          builder: (BuildContext context, GoRouterState state) => const AdminCommunityScreen(),
        ),
        GoRoute(
          path: 'team',
          name: 'adminTeam',
          builder: (BuildContext context, GoRouterState state) => const AdminTeamScreen(),
        ),
        GoRoute(
          path: 'support',
          name: 'adminSupport',
          builder: (BuildContext context, GoRouterState state) => const AdminSupportScreen(),
        ),
        GoRoute(
          path: 'profile',
          name: 'adminProfile',
          builder: (BuildContext context, GoRouterState state) => const AdminProfileScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.researchDashboard,
      name: 'researchDashboard',
      builder: (BuildContext context, GoRouterState state) => const ResearchDashboardScreen(),
      routes: [
        GoRoute(
          path: 'papers',
          name: 'researchPapers',
          builder: (BuildContext context, GoRouterState state) => const ResearchPapersScreen(),
        ),
        GoRoute(
          path: 'new-paper',
          name: 'newPaper',
          builder: (BuildContext context, GoRouterState state) => NewPaperScreen(
            paperId: state.extra is String ? state.extra as String : null,
          ),
        ),
        GoRoute(
          path: 'diseases',
          name: 'researchDiseases',
          builder: (BuildContext context, GoRouterState state) => const ResearchDiseasesScreen(),
        ),
        GoRoute(
          path: 'profile',
          name: 'researchProfile',
          builder: (BuildContext context, GoRouterState state) => const ResearcherProfileScreen(),
        ),
        GoRoute(
          path: 'innovations',
          name: 'researchInnovations',
          builder: (BuildContext context, GoRouterState state) => const InnovationScreen(),
        ),
        GoRoute(
          path: 'search',
          name: 'researchSearch',
          builder: (BuildContext context, GoRouterState state) => const ResearchSearchScreen(),
        ),
        GoRoute(
          path: 'collaboration',
          name: 'researchCollaboration',
          builder: (BuildContext context, GoRouterState state) => const CollaborationScreen(),
        ),
        GoRoute(
          path: 'analytics',
          name: 'researchAnalytics',
          builder: (BuildContext context, GoRouterState state) => const ResearchAnalyticsScreen(),
        ),
        GoRoute(
          path: 'review',
          name: 'researchReview',
          builder: (BuildContext context, GoRouterState state) => const ReviewAreaScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.communityFeed,
      name: 'communityFeed',
      builder: (BuildContext context, GoRouterState state) => const CommunityFeedScreen(),
      routes: [
        GoRoute(
          path: 'post/:postId',
          name: 'communityPost',
          builder: (BuildContext context, GoRouterState state) => CommunityPostScreen(
            postId: state.pathParameters['postId']!,
          ),
        ),
        GoRoute(
          path: 'create',
          name: 'createPost',
          builder: (BuildContext context, GoRouterState state) => const CreatePostScreen(),
        ),
      ],
    ),
    ...paperPortalRoutes,
    GoRoute(
      path: AppRoutes.subscription,
      name: 'subscription',
      builder: (BuildContext context, GoRouterState state) =>
          const SubscriptionScreen(),
    ),
  ],
);
