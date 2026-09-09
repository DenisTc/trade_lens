import 'package:features_insights/features_insights.dart' as insights;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tradelens/router.dart';

/// Route wrapper: server-driven buttons navigate through go_router, limited
/// to the app's own routes.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) => insights.InsightsScreen(
    allowedRoutes: AppRoutes.sduiAllowed,
    onRoute: context.go,
  );
}
