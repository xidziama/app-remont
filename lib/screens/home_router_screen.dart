import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../repositories/project_repository.dart';
import '../services/auth_service.dart';
import '../widgets/empty_state.dart';
import 'company_onboarding_screen.dart';
import 'email_verification_screen.dart';
import 'project_list_screen.dart';

class HomeRouterScreen extends StatefulWidget {
  const HomeRouterScreen({super.key});

  @override
  State<HomeRouterScreen> createState() => _HomeRouterScreenState();
}

class _HomeRouterScreenState extends State<HomeRouterScreen> {
  /// Изначальное значение берется из закэшированного SDK-статуса.
  ///
  /// Дальше обновляется только через [EmailVerificationScreen.onVerified],
  /// потому что emailVerified не приходит через authStateChanges.
  late bool _emailVerified = AuthService.instance.isEmailVerified;

  @override
  Widget build(BuildContext context) {
    if (!_emailVerified) {
      return EmailVerificationScreen(
        onVerified: () => setState(() => _emailVerified = true),
      );
    }

    final repository = context.read<ProjectRepository>();

    return StreamBuilder<List<CompanyMember>>(
      stream: repository.watchCurrentUserCompanyMemberships(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint(
            '[ACCESS] HomeRouter failed to load memberships: ${snapshot.error}',
          );
          return Scaffold(
            appBar: AppBar(
              title: const Text('Мои объекты'),
              actions: [
                IconButton(
                  tooltip: 'Выйти',
                  onPressed: AuthService.instance.signOut,
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            body: EmptyState(
              icon: Icons.error_outline,
              title: 'Не удалось загрузить доступы',
              subtitle: snapshot.error.toString(),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final companies = snapshot.data ?? const <CompanyMember>[];
        if (companies.isEmpty) {
          return const CompanyOnboardingScreen(
            key: ValueKey<String>('company_onboarding'),
          );
        }

        return ProjectListScreen(
          key: ValueKey<String>('project_list_${companies.first.companyId}'),
          company: companies.first,
        );
      },
    );
  }
}
