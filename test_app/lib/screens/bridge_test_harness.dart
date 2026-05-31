import 'package:flutter/material.dart';

class BridgeTestHarness extends StatelessWidget {
  const BridgeTestHarness({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bridge Test Harness')),
      body: ListView(
        children: <Widget>[
          ElevatedButton(
            key: const ValueKey('ext_tap_target'),
            onPressed: () {},
            child: const Text('Tap me'),
          ),
          const TextField(
            key: ValueKey('ext_text_field'),
            decoration: InputDecoration(hintText: 'Type here'),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            key: const ValueKey('ext_long_press'),
            onPressed: () {},
            onLongPress: () {},
            child: const Text('Long press'),
          ),
          GestureDetector(
            key: const ValueKey('ext_double_tap'),
            onDoubleTap: () {},
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              height: 48,
              child: Center(child: Text('Double tap')),
            ),
          ),
          Checkbox(
            key: const ValueKey('ext_checkbox'),
            value: false,
            onChanged: (_) {},
          ),
          Slider(
            key: const ValueKey('ext_slider'),
            value: 0.5,
            onChanged: (_) {},
          ),
          SizedBox(
            key: const ValueKey('ext_scroll_area'),
            height: 600,
            child: Container(color: Colors.grey.shade200),
          ),
          ElevatedButton(
            key: const ValueKey('ext_navigate'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _SecondScreen()),
            ),
            child: const Text('Push second screen'),
          ),
          ElevatedButton(
            key: const ValueKey('ext_throw'),
            onPressed: () => throw StateError('intentional: E2E'),
            child: const Text('Throw'),
          ),
          const Text(
            'ext_getScreenContent_target',
            key: ValueKey('ext_getScreenContent'),
          ),
          const Icon(Icons.favorite, key: ValueKey('ext_icon_marker')),
        ],
      ),
    );
  }
}

class _SecondScreen extends StatelessWidget {
  const _SecondScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Second screen')),
      body: const Center(child: Text('Pushed')),
    );
  }
}
