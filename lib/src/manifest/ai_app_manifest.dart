import 'ai_flow_manifest.dart';
import 'ai_nav_entry.dart';
import 'ai_screen_manifest.dart';

/// Complete hierarchical description of the app for AI navigation.
class AiAppManifest {
  final String appName;
  final String appDescription;
  final Map<String, AiScreenManifest> screens;
  final List<AiFlowManifest> flows;
  final List<AiNavEntry> globalNavigation;

  const AiAppManifest({
    required this.appName,
    required this.appDescription,
    required this.screens,
    this.flows = const [],
    this.globalNavigation = const [],
  });

  AiScreenManifest? screenFor(String route) => screens[route];

  /// Format the full app map as an LLM-readable prompt section.
  String toAppMapPrompt() {
    final buffer = StringBuffer();

    buffer.writeln('APP OVERVIEW:');
    buffer.writeln(appDescription);
    buffer.writeln();

    if (globalNavigation.isNotEmpty) {
      buffer.writeln('GLOBAL NAVIGATION:');
      final navItems =
          globalNavigation.map((n) => '${n.label} (${n.route})').join(', ');
      buffer.writeln('  $navItems');
      buffer.writeln();
    }

    buffer.writeln(
      'APP SCREENS (navigate with exact route name including "/"):',
    );
    for (final screen in screens.values) {
      buffer.writeln(
        '  ${screen.route} — ${screen.title} — ${screen.description}',
      );
      if (screen.linksTo.isNotEmpty) {
        final links = screen.linksTo
            .map((l) => '${l.targetRoute} (${l.trigger})')
            .join(', ');
        buffer.writeln('    Links to: $links');
      }
    }
    buffer.writeln();

    if (flows.isNotEmpty) {
      buffer.writeln('COMMON TASKS (multi-step flows):');
      for (int i = 0; i < flows.length; i++) {
        final flow = flows[i];
        final steps =
            flow.steps.map((s) => '${s.route}: ${s.instruction}').join(' -> ');
        buffer.writeln('  ${i + 1}. ${flow.name}: $steps');
      }
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }

  /// Format a screen's manifest detail.
  String? toScreenDetailPrompt(String route) {
    final screen = screens[route];
    if (screen == null) return null;

    final buffer = StringBuffer();
    buffer.writeln('SCREEN KNOWLEDGE (from app manifest):');
    buffer.writeln('  Title: ${screen.title}');
    buffer.writeln('  Description: ${screen.description}');

    if (screen.sections.isNotEmpty) {
      buffer.writeln('  Sections:');
      for (final section in screen.sections) {
        buffer.writeln('    — ${section.title}: ${section.description}');
        for (final elem in section.elements) {
          final behavior = elem.behaviorDescription != null
              ? ' -> ${elem.behaviorDescription}'
              : '';
          buffer.writeln('      [${elem.type}] "${elem.label}"$behavior');
        }
      }
    }

    if (screen.actions.isNotEmpty) {
      buffer.writeln('  Available Actions:');
      for (final action in screen.actions) {
        final destructive = action.isDestructive ? ' [DESTRUCTIVE]' : '';
        buffer.writeln('    — ${action.name}: ${action.howTo}$destructive');
      }
    }

    if (screen.notes.isNotEmpty) {
      buffer.writeln('  Notes: ${screen.notes.join('; ')}');
    }

    return buffer.toString().trimRight();
  }
}
