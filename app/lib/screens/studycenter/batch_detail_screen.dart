import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/api_exception.dart';
import '../../models/study_center.dart';
import '../../services/apis.dart';
import '../../services/booking_flow.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/auth_guard.dart';
import '../../utils/format.dart';
import '../../utils/messenger.dart';
import '../../widgets/common.dart';
import '../../widgets/loader.dart';
import '../../widgets/seat_map.dart';
import 'booking_detail_screen.dart';

class BatchDetailScreen extends StatefulWidget {
  const BatchDetailScreen({super.key, required this.batchId, required this.title});

  final int batchId;
  final String title;

  @override
  State<BatchDetailScreen> createState() => _BatchDetailScreenState();
}

class _BatchDetailScreenState extends State<BatchDetailScreen> {
  Seat? _selected;
  bool _busy = false;
  int _localReload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Loader<Batch>(
        reloadToken: Object.hash(session.version, _localReload),
        load: () => StudyCenterApi(session.api).batch(widget.batchId),
        builder: (context, batch, reload) {
          final selected = _selected;
          final stillFree = selected != null && batch.seats.any((s) => s.no == selected.no && s.isAvailable);
          if (selected != null && !stillFree) _selected = null;
          final mine = batch.myBooking;
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _InfoCard(batch: batch),
                      const SizedBox(height: 16),
                      if (mine != null) _MyBookingCard(booking: mine),
                      if (!batch.isActive)
                        const CardBox(
                          child: Text('Bookings for this batch are closed.',
                              style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w600)),
                        ),
                      const SizedBox(height: 8),
                      const Text('Choose your seat', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      CardBox(
                        child: SeatMap(
                          seats: batch.seats,
                          perRow: batch.seatsPerRow,
                          frontLabel: 'TRAINER / BOARD',
                          selectedNo: _selected?.no,
                          onSelect: mine != null || !batch.isActive ? null : (seat) => setState(() => _selected = seat),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (mine == null && batch.isActive) _bookBar(batch),
            ],
          );
        },
      ),
    );
  }

  Widget _bookBar(Batch batch) {
    final seat = _selected;
    final String label;
    if (seat == null) {
      label = batch.isFull ? 'Batch is full' : 'Select a free seat';
    } else if (batch.payAtCenter) {
      label = 'Reserve seat ${seat.label}';
    } else {
      label = 'Book seat ${seat.label} · Pay ${formatPaise(batch.bookingAmountPaise)}';
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.border))),
        child: FilledButton(
          onPressed: seat == null || _busy ? null : () => _book(batch, seat),
          child: _busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(label),
        ),
      ),
    );
  }

  Future<void> _book(Batch batch, Seat seat) async {
    if (!await ensureSignedIn(context, reason: 'Sign in to book your seat.')) return;
    if (!mounted) return;
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      final result = await StudyCenterApi(session.api).bookBatch(batch.id, seat.no);
      if (!mounted) return;
      await completeBooking(context, result);
    } on ApiException catch (error) {
      showMessage(error.message);
      if (mounted) setState(() => _localReload++);
    } catch (error) {
      showMessage(errorText(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _selected = null;
        });
      }
    }
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(batch.title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          if (batch.course != null) ...[
            const SizedBox(height: 2),
            Text('Classroom batch for “${batch.course!.title}”', style: const TextStyle(color: AppColors.muted)),
          ],
          if (batch.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(batch.description, style: const TextStyle(height: 1.4)),
          ],
          const Divider(height: 24),
          _row(Icons.schedule, 'Timing', '${batch.daysLabel}, ${formatTimeRange(batch.startTime, batch.endTime)}'),
          _row(Icons.calendar_today_outlined, 'Starts', formatYmd(batch.startDate)),
          if (batch.durationLabel.isNotEmpty) _row(Icons.hourglass_bottom, 'Duration', batch.durationLabel),
          _row(Icons.event_seat_outlined, 'Seats', '${batch.seatsLeft} of ${batch.totalSeats} free'),
          _row(Icons.payments_outlined, 'Course fee', formatPaise(batch.feePaise)),
          _row(
            Icons.receipt_long_outlined,
            'To book',
            batch.payAtCenter ? 'Reserve now, pay at the center' : 'Pay ${formatPaise(batch.bookingAmountPaise)} online',
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: 10),
            SizedBox(width: 90, child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}

class _MyBookingCard extends StatelessWidget {
  const _MyBookingCard({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: cardDecoration(
          color: booking.isConfirmed ? AppColors.successSoft : AppColors.warningSoft,
          border: booking.isConfirmed ? const Color(0xFFA7F3D0) : const Color(0xFFFDE68A),
        ),
        child: Row(
          children: [
            Icon(booking.isConfirmed ? Icons.event_available : Icons.hourglass_bottom,
                color: booking.isConfirmed ? AppColors.success : AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                booking.isConfirmed
                    ? 'You have seat ${booking.seatLabel} in this batch.'
                    : 'Seat ${booking.seatLabel} is held for you. Complete the payment to confirm it.',
                style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => BookingDetailScreen(bookingId: booking.id),
              )),
              child: Text(booking.isConfirmed ? 'View' : 'Pay now'),
            ),
          ],
        ),
      ),
    );
  }
}
