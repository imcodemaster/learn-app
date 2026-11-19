import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/study_center.dart';
import '../../services/apis.dart';
import '../../services/payment_flow.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../utils/messenger.dart';
import '../../widgets/common.dart';
import '../../widgets/loader.dart';

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId, this.justBooked = false});

  final int bookingId;
  final bool justBooked;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  bool _busy = false;
  int _localReload = 0;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresh the "pay within" countdown every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('Booking')),
      body: Loader<Booking>(
        reloadToken: Object.hash(session.version, _localReload),
        load: () => StudyCenterApi(session.api).booking(widget.bookingId),
        builder: (context, booking, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (widget.justBooked && booking.isConfirmed) const _SuccessBanner(),
              _codeCard(booking),
              const SizedBox(height: 14),
              _detailsCard(booking),
              const SizedBox(height: 14),
              if (booking.isHeld) _holdCard(booking),
              if (booking.isConfirmed)
                const CardBox(
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.primary),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('Show this booking code at the study center reception on your first day.',
                            style: TextStyle(height: 1.4)),
                      ),
                    ],
                  ),
                ),
              if (booking.status == 'expired' || booking.status == 'cancelled')
                CardBox(
                  child: Text(
                    booking.status == 'expired'
                        ? 'This booking expired because the payment was not completed in time. You can book again.'
                        : 'This booking was cancelled${booking.cancelReason != null ? ' (${booking.cancelReason})' : ''}.',
                    style: const TextStyle(height: 1.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _codeCard(Booking booking) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          const Text('BOOKING CODE', style: TextStyle(color: Color(0xFFC7D2FE), letterSpacing: 1.5, fontSize: 12)),
          const SizedBox(height: 6),
          SelectableText(
            booking.code,
            style: const TextStyle(
                color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, fontFamily: 'monospace', letterSpacing: 2),
          ),
          const SizedBox(height: 10),
          StatusChip(status: booking.status),
        ],
      ),
    );
  }

  Widget _detailsCard(Booking booking) {
    final batch = booking.batch;
    final shift = booking.shift;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(booking.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const Divider(height: 24),
          _row(booking.isLibrary ? 'Desk' : 'Seat', booking.seatLabel),
          if (batch != null) ...[
            _row('Timing', '${batch.daysLabel}, ${formatTimeRange(batch.startTime, batch.endTime)}'),
            _row('Starts', formatYmd(batch.startDate)),
          ],
          if (shift != null) _row('Hours', formatTimeRange(shift.startTime, shift.endTime)),
          if (booking.isLibrary) _row('Period', '${formatYmd(booking.periodStart)} – ${formatYmd(booking.validUntil)}'),
          _row(booking.isHeld ? 'To pay' : 'Paid online', booking.amountPaise == 0 ? 'Pay at the center' : formatPaise(booking.amountPaise)),
          if (booking.createdAt != null) _row('Booked on', formatDateTime(booking.createdAt!)),
        ],
      ),
    );
  }

  Widget _holdCard(Booking booking) {
    final expires = booking.holdExpiresAt;
    final remaining = expires == null ? Duration.zero : expires.difference(DateTime.now());
    final expired = remaining.isNegative || remaining == Duration.zero;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(color: AppColors.warningSoft, border: const Color(0xFFFDE68A)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_bottom, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  expired ? 'The seat hold has run out.' : 'Seat held for you — pay within ${countdown(remaining)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy || expired ? null : () => _pay(booking),
            child: _busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : Text('Pay ${formatPaise(booking.amountPaise)} now'),
          ),
          TextButton(
            onPressed: _busy ? null : () => _cancel(booking),
            child: const Text('Cancel this booking', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 100, child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Future<void> _pay(Booking booking) async {
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      final checkout = await PaymentApi(session.api).bookingOrder(booking.id);
      if (!mounted) return;
      final result = await PaymentFlow.pay(context, checkout);
      if (result == null) {
        showMessage('Payment not completed.');
      } else {
        showMessage(result.isPaid ? 'Payment successful — your seat is confirmed!' : result.message);
      }
      session.dataChanged();
    } catch (error) {
      showMessage(errorText(error));
      if (mounted) setState(() => _localReload++);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Booking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel booking?'),
        content: Text('Seat ${booking.seatLabel} will be released for other students.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Cancel booking')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      await StudyCenterApi(session.api).cancel(booking.id);
      showMessage('Booking cancelled.');
      session.dataChanged();
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SuccessBanner extends StatelessWidget {
  const _SuccessBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(color: AppColors.successSoft, border: const Color(0xFFA7F3D0)),
      child: const Row(
        children: [
          Icon(Icons.celebration_outlined, color: AppColors.success, size: 30),
          SizedBox(width: 12),
          Expanded(
            child: Text('Your seat is booked! See you at the study center.',
                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
