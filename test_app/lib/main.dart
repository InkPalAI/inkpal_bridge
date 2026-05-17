import 'package:flutter/material.dart';
import 'package:inkpal_bridge/inkpal_bridge.dart';
import 'screens/bridge_test_harness.dart';

void main() => inkpalRunApp(
      const MaterialApp(
        title: 'InkPal Bridge Test Harness',
        home: BridgeTestHarness(),
      ),
      serverUrl: 'ws://localhost:8765',
    );
