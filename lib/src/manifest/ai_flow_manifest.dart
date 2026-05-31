/// A multi-step user task that spans multiple screens.
class AiFlowManifest {
  final String name;
  final String description;
  final List<AiFlowStep> steps;

  const AiFlowManifest({
    required this.name,
    required this.description,
    required this.steps,
  });
}

/// A single step in a multi-screen flow.
class AiFlowStep {
  final String route;
  final String instruction;
  final String? expectedOutcome;

  const AiFlowStep({
    required this.route,
    required this.instruction,
    this.expectedOutcome,
  });
}
