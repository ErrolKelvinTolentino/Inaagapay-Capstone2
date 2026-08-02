import 'package:flutter/material.dart';
import 'add_lab_test_page.dart';

/// Compatibility wrapper forwarding to the streamlined AddLabTestPage
class LabTestAnalyzerScreen extends StatelessWidget {
  final int motherId;
  final int pregnancyId;

  const LabTestAnalyzerScreen({
    super.key,
    required this.motherId,
    required this.pregnancyId,
  });

  @override
  Widget build(BuildContext context) {
    return AddLabTestPage(
      motherId: motherId,
      pregnancyId: pregnancyId,
    );
  }
}
