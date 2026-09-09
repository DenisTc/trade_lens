import 'package:flutter/material.dart';

/// Placeholder until the chart (day 4) and order book (day 3) arrive.
class PairScreen extends StatelessWidget {
  const PairScreen({required this.symbol, super.key});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(symbol)),
      body: const Center(child: Text('Chart coming soon')),
    );
  }
}
