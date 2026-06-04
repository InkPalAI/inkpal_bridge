/// inkpal_bridge example — multi-zone showcase.
///
/// Modelled on the InkPal "battlefield" battle-test app: each zone
/// exercises a specific bridge capability so an AI agent (or a human
/// reading this code) can immediately see what the bridge enables.
///
/// Zones:
///   • Counter zone     — basic state, taps, screenshot diff
///   • Forms zone       — text input + form validation
///   • List zone        — scroll, tap-by-text discovery
///   • Custom-widgets   — `walkerHooks` teaching the bridge to recognise a
///                         proprietary `BrandButton` widget
///
/// Run with:
///   `flutter run -d <device> --dart-define=INKPAL_LICENSE_KEY=ink_your_key_here`
library;

import 'package:flutter/material.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';

void main() {
  inkpalRunApp(
    const ExampleApp(),
    licenseKey: const String.fromEnvironment('INKPAL_LICENSE_KEY'),

    // Help the AI agent navigate by name
    knownRoutes: const ['/', '/forms', '/list', '/custom'],
    routeDescriptions: const {
      '/': 'Counter zone — basic stateful demo',
      '/forms': 'Forms zone — text input + validation',
      '/list': 'List zone — scrollable items',
      '/custom': 'Custom-widget zone — BrandButton demo',
    },

    // Expose state so /inkpal:state_capture has something to snapshot
    globalStateProvider: () async => {
      'time_ms': DateTime.now().millisecondsSinceEpoch,
      'theme': 'dark',
    },

    // Teach the semantics walker about proprietary widgets that don't
    // expose standard Material/Cupertino semantics. The AI agent can then
    // tap them by their human label without you adding `Semantics(label:)`
    // wrappers to every callsite.
    walkerHooks: InkPalWalkerHooks(
      isInteractiveWidget: (widget) => widget is BrandButton,
      extractTextFrom: (widget) =>
          widget is BrandButton ? widget.label : null,
    ),
  );
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'inkpal_bridge example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6750A4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      // `inkpalRunApp` already wraps the root in a RepaintBoundary tagged
      // with `inkpalRootRepaintKey` and installs the package-wide
      // `inkpalNavigatorObserver`, so no manual wiring is required here.
      navigatorObservers: [inkpalNavigatorObserver],
      home: const HomeShell(),
      routes: {
        '/forms': (_) => const FormsZone(),
        '/list': (_) => const ListZone(),
        '/custom': (_) => const CustomWidgetsZone(),
      },
    );
  }
}

// ─── Home shell with zone navigation ────────────────────────────────────

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _counter = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('inkpal_bridge example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Counter: $_counter',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: () => setState(() => _counter--),
                  child: const Text('Decrement'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => setState(() => _counter++),
                  child: const Text('Increment'),
                ),
              ],
            ),
            const Divider(height: 32),
            Text('Zones',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ZoneTile('Forms', '/forms', Icons.edit_note),
            _ZoneTile('List', '/list', Icons.list_alt),
            _ZoneTile('Custom widgets (walkerHooks)', '/custom',
                Icons.widgets),
          ],
        ),
      ),
    );
  }
}

class _ZoneTile extends StatelessWidget {
  const _ZoneTile(this.label, this.route, this.icon);
  final String label;
  final String route;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.pushNamed(context, route),
      ),
    );
  }
}

// ─── Forms zone ─────────────────────────────────────────────────────────

class FormsZone extends StatefulWidget {
  const FormsZone({super.key});

  @override
  State<FormsZone> createState() => _FormsZoneState();
}

class _FormsZoneState extends State<FormsZone> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  String? _result;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forms')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'you@example.com',
                ),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Invalid email' : null,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    setState(() => _result = 'Submitted: ${_emailCtrl.text}');
                  }
                },
                child: const Text('Submit'),
              ),
              if (_result != null) ...[
                const SizedBox(height: 24),
                Text(_result!, style: const TextStyle(color: Colors.green)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─── List zone ──────────────────────────────────────────────────────────

class ListZone extends StatelessWidget {
  const ListZone({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('List')),
      body: ListView.builder(
        itemCount: 50,
        itemBuilder: (_, i) => ListTile(
          leading: CircleAvatar(child: Text('${i + 1}')),
          title: Text('Item ${i + 1}'),
          subtitle: Text('Tap to see how the bridge resolves "Item ${i + 1}"'),
          onTap: () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Tapped Item ${i + 1}')),
          ),
        ),
      ),
    );
  }
}

// ─── Custom-widgets zone (the walkerHooks story) ────────────────────────

/// A proprietary widget that doesn't extend any standard Material widget.
/// Without `walkerHooks`, an AI agent walking the semantics tree would see
/// the inner GestureDetector but not know what this button is "called" or
/// that it's interactive. With `walkerHooks` (wired in main()), the agent
/// can ask "tap the Save button" and the bridge resolves it correctly.
class BrandButton extends StatelessWidget {
  const BrandButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6750A4), Color(0xFFB8A4E1)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class CustomWidgetsZone extends StatefulWidget {
  const CustomWidgetsZone({super.key});

  @override
  State<CustomWidgetsZone> createState() => _CustomWidgetsZoneState();
}

class _CustomWidgetsZoneState extends State<CustomWidgetsZone> {
  String _last = '(nothing yet)';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom widgets')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'These BrandButtons are proprietary widgets with no built-in '
              'Semantics. The walkerHooks wired in main() teach the AI '
              'agent to recognise them by label.',
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                BrandButton(
                  label: 'Save',
                  onPressed: () => setState(() => _last = 'Save'),
                ),
                const SizedBox(width: 12),
                BrandButton(
                  label: 'Cancel',
                  onPressed: () => setState(() => _last = 'Cancel'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Center(
              child: BrandButton(
                label: 'Submit Order',
                onPressed: () => setState(() => _last = 'Submit Order'),
              ),
            ),
            const SizedBox(height: 32),
            Text('Last tapped: $_last', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
