/// A notable UI element the agent should know about.
class AiElementManifest {
  final String label;
  final String type;
  final String? behaviorDescription;

  const AiElementManifest({
    required this.label,
    required this.type,
    this.behaviorDescription,
  });
}
