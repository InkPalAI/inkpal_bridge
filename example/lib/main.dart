/// inkpal_bridge example — bridge showcase.
///
/// A 9-zone Flutter app exercising every capability the bridge exposes to
/// an AI assistant. Each zone is built around realistic patterns an AI
/// would see in real apps: layout bugs, error-handling foot-guns, form
/// flows, scrollable lists, runtime state, visual-regression baselines.
///
/// Zones:
///   • Core Debug      — overflow, constraints, rebuild loops
///   • Visual Debug    — clipped text, contrast, tap-target sizing
///   • Auto-Fix        — patches the bridge can suggest + apply
///   • Runtime Intel   — live tree, state, timers, gesture conflicts
///   • Error Intel     — throw paths the catcher should map
///   • Visual Testing  — golden + regression + responsive
///   • Developer Exp.  — chat, inline hints, history surfaces
///   • Smart Assist    — a11y, responsive, animation suggestions
///   • Forms & Input   — fields, scroll, switches, sliders
///
/// Run with:
///   `flutter run -d <device>`
///   (optionally pass `--dart-define=INKPAL_LICENSE_KEY=ink_your_key`)
library;

import 'package:flutter/material.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

import 'test_zones/auto_fix_zone.dart';
import 'test_zones/core_debug_zone.dart';
import 'test_zones/dx_zone.dart';
import 'test_zones/error_intel_zone.dart';
import 'test_zones/forms_zone.dart';
import 'test_zones/runtime_zone.dart';
import 'test_zones/smart_assist_zone.dart';
import 'test_zones/visual_debug_zone.dart';
import 'test_zones/visual_testing_zone.dart';

int _appBootCount = 0;

void main() {
  _appBootCount++;
  inkpalRunApp(
    const BridgeShowcaseApp(),
    licenseKey: const String.fromEnvironment('INKPAL_LICENSE_KEY'),
    globalStateProvider: _showcaseStateProvider,
  );
}

/// Demo state provider so `state_capture` / `state_get` / `state_diff` have
/// something to introspect. A production app would surface its real store
/// here (Riverpod ProviderContainer, Bloc state map, etc.).
Future<Map<String, dynamic>> _showcaseStateProvider() async {
  return {
    'boot_count': _appBootCount,
    'wall_clock_ms': DateTime.now().millisecondsSinceEpoch,
  };
}

class BridgeShowcaseApp extends StatelessWidget {
  const BridgeShowcaseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InkPal Bridge Showcase',
      debugShowCheckedModeBanner: false,
      navigatorKey: inkpalNavigatorKey,
      navigatorObservers: [inkpalNavigatorObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class TestCategory {
  const TestCategory({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const List<TestCategory> _categories = [
    TestCategory(
      title: 'Core Debug',
      subtitle: 'Overflow, constraints, rebuilds',
      icon: Icons.bug_report,
      color: Color(0xFFEF5350),
      builder: _buildCoreDebug,
    ),
    TestCategory(
      title: 'Visual Debug',
      subtitle: 'Screenshot → issue detection',
      icon: Icons.center_focus_strong,
      color: Color(0xFFAB47BC),
      builder: _buildVisualDebug,
    ),
    TestCategory(
      title: 'Auto-Fix',
      subtitle: 'One-click safe patches',
      icon: Icons.auto_fix_high,
      color: Color(0xFF42A5F5),
      builder: _buildAutoFix,
    ),
    TestCategory(
      title: 'Runtime Intel',
      subtitle: 'Live tree, state, frame drops',
      icon: Icons.bolt,
      color: Color(0xFFFFA726),
      builder: _buildRuntime,
    ),
    TestCategory(
      title: 'Error Intel',
      subtitle: 'Root cause + plain English',
      icon: Icons.psychology,
      color: Color(0xFF26A69A),
      builder: _buildErrorIntel,
    ),
    TestCategory(
      title: 'Visual Testing',
      subtitle: 'Regression + multi-device',
      icon: Icons.compare,
      color: Color(0xFF66BB6A),
      builder: _buildVisualTesting,
    ),
    TestCategory(
      title: 'DX',
      subtitle: 'Setup, chat, history',
      icon: Icons.terminal,
      color: Color(0xFF8D6E63),
      builder: _buildDx,
    ),
    TestCategory(
      title: 'Smart Assist',
      subtitle: 'A11y, responsive, hints',
      icon: Icons.tips_and_updates,
      color: Color(0xFFEC407A),
      builder: _buildSmartAssist,
    ),
    TestCategory(
      title: 'Forms',
      subtitle: 'TextFields, scroll, controls',
      icon: Icons.text_fields,
      color: Color(0xFF7E57C2),
      builder: _buildForms,
    ),
  ];

  static Widget _buildCoreDebug(BuildContext _) => const CoreDebugZone();
  static Widget _buildVisualDebug(BuildContext _) => const VisualDebugZone();
  static Widget _buildAutoFix(BuildContext _) => const AutoFixZone();
  static Widget _buildRuntime(BuildContext _) => const RuntimeZone();
  static Widget _buildErrorIntel(BuildContext _) => const ErrorIntelZone();
  static Widget _buildVisualTesting(BuildContext _) =>
      const VisualTestingZone();
  static Widget _buildDx(BuildContext _) => const DxZone();
  static Widget _buildSmartAssist(BuildContext _) => const SmartAssistZone();
  static Widget _buildForms(BuildContext _) => const FormsZone();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: _Header()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _CategoryCard(category: _categories[i]),
                  childCount: _categories.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'InkPal Bridge Showcase',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pick a zone to see how an AI assistant sees, drives, and '
            'debugs your real Flutter app.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category});

  final TestCategory category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keySlug = category.title.toLowerCase().replaceAll(' ', '_');
    return Material(
      key: ValueKey('zone_card_$keySlug'),
      color: category.color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: category.builder,
            settings: RouteSettings(name: '/$keySlug'),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: category.color.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(category.icon, color: category.color, size: 24),
              ),
              const Spacer(),
              Text(
                category.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                category.subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
