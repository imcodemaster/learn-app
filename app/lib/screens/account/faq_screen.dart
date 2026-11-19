import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final faq = context.watch<Session>().info.faq;
    return Scaffold(
      appBar: AppBar(title: const Text('Frequently asked questions')),
      body: faq.isEmpty
          ? const EmptyView(icon: Icons.help_outline, title: 'No questions yet')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: faq.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => Container(
                decoration: cardDecoration(),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: Text(faq[index].question, style: const TextStyle(fontWeight: FontWeight.w700)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(faq[index].answer, style: const TextStyle(height: 1.5))],
                ),
              ),
            ),
    );
  }
}
