import 'package:flutter/material.dart';
import '../pages/agent_work_page.dart';
import '../pages/verification_report_page.dart';

/// Static navigation helpers for agent work pages.
class AgentWorkNav {
  /// Open the main agent work hub page.
  static void openAgentWork(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AgentWorkPage()),
    );
  }

  /// Open the verification report for a specific checklist item.
  static void openVerificationReport(BuildContext context, String itemId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerificationReportPage(itemId: itemId),
      ),
    );
  }
}
