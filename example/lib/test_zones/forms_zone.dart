import 'package:flutter/material.dart';

import 'zone_scaffold.dart';

class FormsZone extends StatelessWidget {
  const FormsZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ZoneScaffold(
      title: 'Forms & Input',
      intent:
          'Drive enter_text, tap, and scroll against real text fields, scrollable lists, and toggles.',
      tests: [
        TestTile(
          label: 'Login form',
          description:
              'Two text fields + sign-in button. Test enter_text + tap.',
          builder: (_) => const _LoginForm(),
        ),
        TestTile(
          label: 'Long scrolling list',
          description: '500-item ListView.builder. Test scroll + scroll_to.',
          builder: (_) => const _LongList(),
        ),
        TestTile(
          label: 'Switches & sliders',
          description: 'State controls. Test tap + double_tap + value reads.',
          builder: (_) => const _Controls(),
        ),
      ],
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm();
  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final _email = TextEditingController();
  final _pwd = TextEditingController();
  String _result = '';

  @override
  void dispose() {
    _email.dispose();
    _pwd.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('email_field'),
            controller: _email,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('password_field'),
            controller: _pwd,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('signin_button'),
            onPressed: () =>
                setState(() => _result = 'Signed in as ${_email.text}'),
            child: const Text('Sign In'),
          ),
          const SizedBox(height: 16),
          Text(_result, key: const ValueKey('result_text')),
        ],
      ),
    );
  }
}

class _LongList extends StatelessWidget {
  const _LongList();
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const ValueKey('long_list'),
      itemCount: 500,
      itemBuilder: (_, i) => ListTile(
        key: ValueKey('row_$i'),
        leading: CircleAvatar(child: Text('$i')),
        title: Text('Item $i'),
        subtitle: Text(i == 250 ? 'midpoint marker' : 'tap to select'),
      ),
    );
  }
}

class _Controls extends StatefulWidget {
  const _Controls();
  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  bool _on = false;
  double _v = 0.5;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey('feature_switch'),
            title: const Text('Enable feature'),
            value: _on,
            onChanged: (v) => setState(() => _on = v),
          ),
          const SizedBox(height: 24),
          Text('Slider: ${(_v * 100).round()}%'),
          Slider(
            key: const ValueKey('volume_slider'),
            value: _v,
            onChanged: (v) => setState(() => _v = v),
          ),
        ],
      ),
    );
  }
}
