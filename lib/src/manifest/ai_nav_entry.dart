/// An entry in the app's global navigation (bottom nav bar, side menu, etc.).
class AiNavEntry {
  final String label;
  final String route;
  final String? iconDescription;

  const AiNavEntry({
    required this.label,
    required this.route,
    this.iconDescription,
  });
}
