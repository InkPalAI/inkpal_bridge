import 'ai_element_manifest.dart';

/// A logical section within a screen (e.g., "Balance Card", "Transaction List").
class AiSectionManifest {
  final String title;
  final String description;
  final List<AiElementManifest> elements;

  const AiSectionManifest({
    required this.title,
    required this.description,
    this.elements = const [],
  });
}
