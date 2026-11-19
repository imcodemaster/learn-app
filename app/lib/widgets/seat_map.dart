import 'package:flutter/material.dart';

import '../models/study_center.dart';
import '../theme.dart';

/// Grid of seats/desks. Free seats can be tapped to select them.
class SeatMap extends StatelessWidget {
  const SeatMap({
    super.key,
    required this.seats,
    required this.perRow,
    required this.frontLabel,
    this.selectedNo,
    this.onSelect,
  });

  final List<Seat> seats;
  final int perRow;
  final String frontLabel;
  final int? selectedNo;
  final ValueChanged<Seat>? onSelect;

  @override
  Widget build(BuildContext context) {
    final columns = perRow < 1 ? 1 : perRow;
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(10)),
          child: Text(frontLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final double size = ((constraints.maxWidth - gap * (columns - 1)) / columns).clamp(34.0, 64.0).toDouble();
            final rows = <Widget>[];
            for (var start = 0; start < seats.length; start += columns) {
              final end = (start + columns) > seats.length ? seats.length : start + columns;
              rows.add(Padding(
                padding: const EdgeInsets.only(bottom: gap),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = start; i < end; i++) ...[
                      if (i > start) const SizedBox(width: gap),
                      _SeatBox(
                        seat: seats[i],
                        size: size,
                        selected: seats[i].no == selectedNo,
                        onTap: onSelect == null || !seats[i].isAvailable ? null : () => onSelect!(seats[i]),
                      ),
                    ],
                  ],
                ),
              ));
            }
            return Column(children: rows);
          },
        ),
        const SizedBox(height: 8),
        const Wrap(
          spacing: 14,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            _Legend(color: Colors.white, border: AppColors.primary, label: 'Available'),
            _Legend(color: AppColors.primary, border: AppColors.primary, label: 'Selected'),
            _Legend(color: AppColors.success, border: AppColors.success, label: 'Yours'),
            _Legend(color: Color(0xFFE5E7EB), border: Color(0xFFD1D5DB), label: 'Taken'),
          ],
        ),
      ],
    );
  }
}

class _SeatBox extends StatelessWidget {
  const _SeatBox({required this.seat, required this.size, required this.selected, required this.onTap});

  final Seat seat;
  final double size;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Color background;
    Color border;
    Color text;
    if (selected) {
      background = AppColors.primary;
      border = AppColors.primary;
      text = Colors.white;
    } else if (seat.status == 'mine') {
      background = AppColors.success;
      border = AppColors.success;
      text = Colors.white;
    } else if (seat.isAvailable) {
      background = Colors.white;
      border = AppColors.primary;
      text = AppColors.primaryDark;
    } else {
      background = const Color(0xFFE5E7EB);
      border = const Color(0xFFD1D5DB);
      text = AppColors.muted;
    }
    return Semantics(
      button: onTap != null,
      label: 'Seat ${seat.label}, ${seat.status}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: border, width: 1.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(seat.label, style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.border, required this.label});

  final Color color;
  final Color border;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: border, width: 1.4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
      ],
    );
  }
}
