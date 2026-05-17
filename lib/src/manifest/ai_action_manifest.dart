/// A meaningful action available on a screen.
class AiActionManifest {
  final String name;
  final String howTo;
  final bool isDestructive;

  const AiActionManifest({
    required this.name,
    required this.howTo,
    this.isDestructive = false,
  });
}
