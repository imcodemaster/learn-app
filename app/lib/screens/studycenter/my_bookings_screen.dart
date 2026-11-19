import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/study_center.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/format.dart';
import '../../widgets/common.dart';
import '../../widgets/loader.dart';
import 'booking_detail_screen.dart';

class MyBookingsScreen extends StatelessWidget {
  const MyBookingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: const Text('My bookings')),
      body: Loader<List<Booking>>(
        reloadToken: session.version,
        load: () => StudyCenterApi(session.api).myBookings(),
        builder: (context, bookings, reload) => bookings.isEmpty
            ? const EmptyView(
                icon: Icons.event_seat_outlined,
                title: 'No bookings yet',
                message: 'Book a seat in a course batch or a library desk from the Study center tab.',
              )
            : RefreshIndicator(
                onRefresh: reload,
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: bookings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _BookingTile(booking: bookings[index]),
                ),
              ),
      ),
    );
  }
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final subtitle = booking.isLibrary
        ? 'Desk ${booking.seatLabel} · ${formatYmd(booking.periodStart)} – ${formatYmd(booking.validUntil)}'
        : 'Seat ${booking.seatLabel}'
            '${booking.batch != null ? ' · ${formatTimeRange(booking.batch!.startTime, booking.batch!.endTime)}' : ''}';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BookingDetailScreen(bookingId: booking.id),
        )),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: cardDecoration(),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: AppColors.primarySoft,
                child: Icon(booking.isLibrary ? Icons.chair_outlined : Icons.event_seat_outlined,
                    color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(booking.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 6),
                    Text(booking.code,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: AppColors.primaryDark)),
                  ],
                ),
              ),
              StatusChip(status: booking.status),
            ],
          ),
        ),
      ),
    );
  }
}
