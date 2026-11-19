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

/// Desk map for one library shift and period; pick a desk and pay.
class LibraryBookingScreen extends StatefulWidget {
  const LibraryBookingScreen({super.key, required this.shift, required this.startDate, required this.months});

  final Shift shift;
  final String startDate;
  final int months;

  @override
  State<LibraryBookingScreen> createState() => _LibraryBookingScreenState();
}

class _LibraryBookingScreenState extends State<LibraryBookingScreen> {
  Seat? _selected;
  bool _busy = false;
  int _localReload = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: Text('${widget.shift.name} desk')),
      body: Loader<LibraryAvailability>(
        reloadToken: Object.hash(session.version, _localReload),
        load: () => StudyCenterApi(session.api).libraryAvailability(
          shiftId: widget.shift.id,
          startDate: widget.startDate,
          months: widget.months,
        ),
        builder: (context, availability, reload) {
          final selected = _selected;
          if (selected != null && !availability.seats.any((s) => s.no == selected.no && s.isAvailable)) {
            _selected = null;
          }
          final free = availability.seats.where((s) => s.isAvailable).length;
          return Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      CardBox(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(availability.shift.name,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(formatTimeRange(availability.shift.startTime, availability.shift.endTime),
                                style: const TextStyle(color: AppColors.muted)),
                            const Divider(height: 24),
                            _row('Period',
                                '${formatYmd(availability.startDate)} – ${formatYmd(availability.validUntil)}'),
                            _row('Duration', plural(availability.months, 'month')),
                            _row('Desks free', '$free of ${availability.seats.length}'),
                            _row('Total', formatPaise(availability.amountPaise), bold: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Choose your desk', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      CardBox(
                        child: SeatMap(
                          seats: availability.seats,
                          perRow: availability.desksPerRow,
                          frontLabel: 'ENTRANCE',
                          selectedNo: _selected?.no,
                          onSelect: (seat) => setState(() => _selected = seat),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: FilledButton(
                    onPressed: _selected == null || _busy ? null : () => _book(availability),
                    child: _busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(_selected == null
                            ? (free == 0 ? 'No desks free for these dates' : 'Select a free desk')
                            : 'Book desk ${_selected!.label} · Pay ${formatPaise(availability.amountPaise)}'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: AppColors.muted))),
            Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 17 : 14)),
          ],
        ),
      );

  Future<void> _book(LibraryAvailability availability) async {
    final seat = _selected;
    if (seat == null) return;
    if (!await ensureSignedIn(context, reason: 'Sign in to book a library desk.')) return;
    if (!mounted) return;
    final session = context.read<Session>();
    setState(() => _busy = true);
    try {
      final result = await StudyCenterApi(session.api).bookLibrary(
        shiftId: availability.shift.id,
        startDate: availability.startDate,
        months: availability.months,
        seatNo: seat.no,
      );
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
