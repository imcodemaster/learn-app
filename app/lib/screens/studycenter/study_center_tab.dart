import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/study_center.dart';
import '../../services/apis.dart';
import '../../state/session.dart';
import '../../theme.dart';
import '../../utils/auth_guard.dart';
import '../../utils/format.dart';
import '../../utils/links.dart';
import '../../widgets/common.dart';
import '../../widgets/loader.dart';
import 'batch_detail_screen.dart';
import 'library_booking_screen.dart';
import 'my_bookings_screen.dart';

class StudyCenterTab extends StatefulWidget {
  const StudyCenterTab({super.key});

  @override
  State<StudyCenterTab> createState() => _StudyCenterTabState();
}

class _StudyCenterData {
  _StudyCenterData(this.info, this.batches);

  final StudyCenterInfo info;
  final List<Batch> batches;
}

class _StudyCenterTabState extends State<StudyCenterTab> {
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final api = StudyCenterApi(session.api);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study center'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (!await ensureSignedIn(context, reason: 'Sign in to see your bookings.')) return;
              navigator.push(MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
            },
            icon: const Icon(Icons.confirmation_number_outlined),
            label: const Text('My bookings'),
          ),
        ],
      ),
      body: Loader<_StudyCenterData>(
        reloadToken: session.version,
        load: () async {
          final results = await Future.wait<Object>([api.info(), api.batches()]);
          return _StudyCenterData(results[0] as StudyCenterInfo, results[1] as List<Batch>);
        },
        builder: (context, data, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
            children: [
              _CenterCard(info: data.info),
              const SizedBox(height: 16),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, icon: Icon(Icons.groups_outlined), label: Text('Course batches')),
                  ButtonSegment(value: 1, icon: Icon(Icons.chair_outlined), label: Text('Library desks')),
                ],
                selected: {_segment},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => setState(() => _segment = selection.first),
              ),
              const SizedBox(height: 16),
              if (_segment == 0) ..._batches(context, data.batches) else _LibraryPlanner(info: data.info),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _batches(BuildContext context, List<Batch> batches) {
    if (batches.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 24),
          child: EmptyView(
            icon: Icons.event_busy_outlined,
            title: 'No batches open right now',
            message: 'New batches are announced regularly. Call us to know the next start date.',
          ),
        ),
      ];
    }
    return [
      const Text('Classroom courses at the center. Pick a batch, then choose your seat.',
          style: TextStyle(color: AppColors.muted, height: 1.4)),
      const SizedBox(height: 12),
      for (final batch in batches) _BatchCard(batch: batch),
    ];
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({required this.info});

  final StudyCenterInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(info.name, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          _line(Icons.place_outlined, info.address),
          _line(Icons.access_time, info.hours),
          const SizedBox(height: 12),
          Row(
            children: [
              if (info.phone.isNotEmpty)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: () => callPhone(info.phone),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call'),
                ),
              const SizedBox(width: 10),
              if (info.email.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: () => sendEmail(info.email),
                  icon: const Icon(Icons.mail_outline, size: 18),
                  label: const Text('Email'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFC7D2FE), size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Color(0xFFE0E7FF)))),
        ],
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  const _BatchCard({required this.batch});

  final Batch batch;

  @override
  Widget build(BuildContext context) {
    final (Color seatColor, Color seatBg, String seatText) = batch.isFull
        ? (AppColors.danger, AppColors.dangerSoft, 'Full')
        : batch.seatsLeft <= 3
            ? (AppColors.warning, AppColors.warningSoft, 'Only ${batch.seatsLeft} left')
            : (AppColors.success, AppColors.successSoft, '${batch.seatsLeft} seats left');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => BatchDetailScreen(batchId: batch.id, title: batch.title),
          )),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(batch.title,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: seatBg, borderRadius: BorderRadius.circular(20)),
                      child: Text(seatText, style: TextStyle(color: seatColor, fontWeight: FontWeight.w700, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _row(Icons.schedule, '${batch.daysLabel} · ${formatTimeRange(batch.startTime, batch.endTime)}'),
                _row(Icons.calendar_today_outlined,
                    'Starts ${formatYmd(batch.startDate)}${batch.durationLabel.isEmpty ? '' : ' · ${batch.durationLabel}'}'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Fee ${formatPaise(batch.feePaise)}',
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text(
                            batch.payAtCenter
                                ? 'Reserve free, pay at the center'
                                : batch.bookingAmountPaise < batch.feePaise
                                    ? 'Pay ${formatPaise(batch.bookingAmountPaise)} now to book'
                                    : 'Pay online to book',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    const Text('Choose seat', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                    const Icon(Icons.chevron_right, color: AppColors.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.muted),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: const TextStyle(color: AppColors.muted))),
          ],
        ),
      );
}

/// Pick a shift, start date and number of months, then choose a desk.
class _LibraryPlanner extends StatefulWidget {
  const _LibraryPlanner({required this.info});

  final StudyCenterInfo info;

  @override
  State<_LibraryPlanner> createState() => _LibraryPlannerState();
}

class _LibraryPlannerState extends State<_LibraryPlanner> {
  Shift? _shift;
  late DateTime _start;
  int _months = 1;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day);
    if (widget.info.shifts.isNotEmpty) _shift = widget.info.shifts.first;
  }

  @override
  Widget build(BuildContext context) {
    final library = widget.info.library;
    if (!library.enabled || widget.info.shifts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.only(top: 24),
        child: EmptyView(
          icon: Icons.chair_outlined,
          title: 'Library desks are not available right now',
          message: 'Please check again later or call the study center.',
        ),
      );
    }
    final shift = _shift ?? widget.info.shifts.first;
    final maxMonths = library.maxMonths < 1 ? 1 : library.maxMonths;
    if (_months > maxMonths) _months = maxMonths;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Rent a quiet self-study desk by the month.', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 14),
        const Text('1. Choose a shift', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        for (final option in widget.info.shifts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: option.id == shift.id ? AppColors.primarySoft : Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _shift = option),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: option.id == shift.id ? AppColors.primary : AppColors.border,
                      width: option.id == shift.id ? 1.6 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(option.id == shift.id ? Icons.check_circle : Icons.circle_outlined,
                          color: option.id == shift.id ? AppColors.primary : AppColors.muted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(option.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text(formatTimeRange(option.startTime, option.endTime),
                                style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                          ],
                        ),
                      ),
                      Text('${formatPaise(option.monthlyFeePaise)}/month',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 10),
        const Text('2. Start date', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        CardBox(
          padding: EdgeInsets.zero,
          child: ListTile(
            leading: const Icon(Icons.calendar_today_outlined, color: AppColors.primary),
            title: Text(formatDate(_start), style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: const Text('Change', style: TextStyle(color: AppColors.primary)),
            onTap: () => _pickDate(library.advanceDays),
          ),
        ),
        const SizedBox(height: 16),
        const Text('3. How many months?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var month = 1; month <= maxMonths; month++)
              ChoiceChip(
                label: Text(plural(month, 'month')),
                selected: _months == month,
                showCheckmark: false,
                onSelected: (_) => setState(() => _months = month),
              ),
          ],
        ),
        const SizedBox(height: 18),
        CardBox(
          child: Row(
            children: [
              const Expanded(child: Text('Total', style: TextStyle(fontSize: 16))),
              Text(formatPaise(shift.monthlyFeePaise * _months),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => LibraryBookingScreen(
              shift: shift,
              startDate: toYmd(_start),
              months: _months,
            ),
          )),
          icon: const Icon(Icons.chair_outlined),
          label: const Text('Choose a desk'),
        ),
      ],
    );
  }

  Future<void> _pickDate(int advanceDays) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _start.isBefore(today) ? today : _start,
      firstDate: today,
      lastDate: today.add(Duration(days: advanceDays < 0 ? 0 : advanceDays)),
      helpText: 'Desk booking starts on',
    );
    if (picked != null && mounted) setState(() => _start = picked);
  }
}
