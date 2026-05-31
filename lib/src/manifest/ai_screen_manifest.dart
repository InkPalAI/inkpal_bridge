import 'ai_action_manifest.dart';
import 'ai_navigation_link.dart';
import 'ai_section_manifest.dart';

/// Rich description of a single screen in the app.
class AiScreenManifest {
  final String route;
  final String title;
  final String description;
  final List<AiSectionManifest> sections;
  final List<AiActionManifest> actions;
  final List<AiNavigationLink> linksTo;
  final List<String> notes;

  const AiScreenManifest({
    required this.route,
    required this.title,
    required this.description,
    this.sections = const [],
    this.actions = const [],
    this.linksTo = const [],
    this.notes = const [],
  });
}
