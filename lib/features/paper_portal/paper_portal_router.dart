import 'package:go_router/go_router.dart';
import 'screens/paper_portal_screen.dart';

final paperPortalRoutes = <GoRoute>[
  GoRoute(
    path: '/paper-portal',
    name: 'paperPortal',
    builder: (context, state) => const PaperPortalScreen(),
  ),
];
