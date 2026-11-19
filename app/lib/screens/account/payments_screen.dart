import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/payment.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/loader.dart';

class PaymentsScreen extends StatelessWidget {
  const PaymentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('Payment history')),
      body: Loader<List<PaymentRecord>>(
        reloadToken: session.version,
        load: () => PaymentApi(session.api).history(),
        builder: (context, payments, reload) => payments.isEmpty
            ? const EmptyView(
                icon: Icons.receipt_long_outlined,
                title: 'No payments yet',
                message: 'Course purchases and seat bookings you pay for will appear here.',
              )
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final payment = payments[index];
                    final date = payment.paidAt ?? payment.createdAt;
                    return CardBox(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.primarySoft,
                            child: Icon(
                              payment.purpose == 'booking' ? Icons.event_seat_outlined : Icons.menu_book_outlined,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(payment.description, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                if (date != null)
                                  Text(formatDateTime(date), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                if (payment.providerPaymentId != null)
                                  SelectableText('Payment ID: ${payment.providerPaymentId}',
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatPaise(payment.amountPaise),
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              const SizedBox(height: 6),
                              StatusChip(status: payment.status),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
