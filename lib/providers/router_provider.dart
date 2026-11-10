import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../screens/assign_screen.dart';
import 'auth_provider.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/people_screen.dart';
import '../screens/receipt_detail_screen.dart';
import '../screens/review_screen.dart';
import '../screens/scan_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/summary_screen.dart';

/// Route paths in one place so screens never hard-code strings twice.
abstract final class Routes {
  static const home = '/';
  static const login = '/login';
  static const signup = '/signup';
  static const scan = '/scan';
  static const review = '/review';
  static const assign = '/assign';
  static const summary = '/summary';
  static const history = '/history';
  static const people = '/people';
}

/// Turns a Stream into a Listenable so GoRouter re-runs `redirect`
/// every time the auth state changes.
class _StreamListenable extends ChangeNotifier {
  late final StreamSubscription<void> _sub;
  _StreamListenable(Stream<void> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// The app's router, exposed through Riverpod.
///
/// Auth guard: `redirect` runs before every navigation (and on every auth
/// change via refreshListenable). Signed-out users can only see /login and
/// /signup; signed-in users are sent away from them. So screens never
/// navigate after sign in/out – they just change the auth state.
final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authServiceProvider);
  final refresh = _StreamListenable(auth.userIdChanges);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final onAuthPage =
          state.matchedLocation == Routes.login || state.matchedLocation == Routes.signup;
      if (!auth.isSignedIn) return onAuthPage ? null : Routes.login;
      if (onAuthPage) return Routes.home;
      return null; // no redirect
    },
    routes: [
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      GoRoute(path: Routes.signup, builder: (_, _) => const SignupScreen()),
      // Everything else is NESTED under Home ('/'). With nested routes,
      // context.go('/history/123') builds the stack Home → History → Receipt,
      // so Back always leads home instead of closing the app.
      // Child paths are relative ('scan' = '/scan').
      GoRoute(
        path: Routes.home,
        builder: (_, _) => const HomeScreen(),
        routes: [
          GoRoute(path: 'scan', builder: (_, _) => const ScanScreen()),
          GoRoute(path: 'review', builder: (_, _) => const ReviewScreen()),
          GoRoute(path: 'assign', builder: (_, _) => const AssignScreen()),
          GoRoute(path: 'summary', builder: (_, _) => const SummaryScreen()),
          GoRoute(path: 'people', builder: (_, _) => const PeopleScreen()),
          GoRoute(
            path: 'history',
            builder: (_, _) => const HistoryScreen(),
            routes: [
              // Path parameter: /history/<id>
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    ReceiptDetailScreen(receiptId: state.pathParameters['id']!),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
