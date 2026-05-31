/// Describes a navigation link from one screen to another.
class AiNavigationLink {
  final String targetRoute;
  final String trigger;

  const AiNavigationLink({required this.targetRoute, required this.trigger});
}
