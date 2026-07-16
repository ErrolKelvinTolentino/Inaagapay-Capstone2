// lib/screens/mother/mother_child_stack.dart

import 'package:flutter/material.dart';
import 'mother_view_child.dart';
import 'mother_child_growth.dart';
import 'mother_child_vaccine.dart';

class MotherChildStack extends StatefulWidget {
  final int childId;
  final String childName;
  final String childAge;
  final String childGender;

  const MotherChildStack({
    super.key,
    required this.childId,
    required this.childName,
    required this.childAge,
    required this.childGender,
  });

  @override
  State<MotherChildStack> createState() => _MotherChildStackState();
}

class _MotherChildStackState extends State<MotherChildStack> {
  int _currentIndex = 0;

  void _goTo(int index) {
    setState(() => _currentIndex = index);
  }

  void _goBackToOverview() {
    setState(() => _currentIndex = 0);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _currentIndex,
      children: [
        // Overview
        MotherViewChildPage(
          childId: widget.childId,
          childName: widget.childName,
          childAge: widget.childAge,
          childGender: widget.childGender,
          onBackToChildren: () => Navigator.pop(context),
          onViewGrowth: () => _goTo(1),
          onViewVaccines: () => _goTo(2),
        ),
        // Growth
        MotherChildGrowthPage(
          onBack: _goBackToOverview,
          childId: widget.childId,
          childName: widget.childName,
          childAge: widget.childAge,
          childGender: widget.childGender,
        ),
        // Vaccines
        MotherChildVaccinePage(
          onBack: _goBackToOverview,
          childId: widget.childId,
          childName: widget.childName,
          childAge: widget.childAge,
          childGender: widget.childGender,
        ),
      ],
    );
  }
}