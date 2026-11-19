import 'json.dart';
import 'payment.dart';

class Seat {
  const Seat({required this.no, required this.label, required this.status});

  final int no;
  final String label;

  /// available | held | booked | mine
  final String status;

  bool get isAvailable => status == 'available';

  factory Seat.fromJson(Map<String, dynamic> json) => Seat(
        no: jInt(json['no']),
        label: jStr(json['label']),
        status: jStr(json['status'], 'available'),
      );
}

class CourseRef {
  const CourseRef({required this.id, required this.title, required this.slug});

  final int id;
  final String title;
  final String slug;

  factory CourseRef.fromJson(Map<String, dynamic> json) =>
      CourseRef(id: jInt(json['id']), title: jStr(json['title']), slug: jStr(json['slug']));
}

class Batch {
  Batch({
    required this.id,
    required this.title,
    required this.description,
    required this.course,
    required this.daysLabel,
    required this.startTime,
    required this.endTime,
    required this.startDate,
    required this.durationLabel,
    required this.totalSeats,
    required this.seatsPerRow,
    required this.seatsLeft,
    required this.feePaise,
    required this.bookingAmountPaise,
    required this.isActive,
    required this.seats,
    required this.myBooking,
  });

  final int id;
  final String title;
  final String description;
  final CourseRef? course;
  final String daysLabel;
  final String startTime;
  final String endTime;
  final String startDate;
  final String durationLabel;
  final int totalSeats;
  final int seatsPerRow;
  final int seatsLeft;
  final int feePaise;
  final int bookingAmountPaise;
  final bool isActive;
  final List<Seat> seats;
  final Booking? myBooking;

  factory Batch.fromJson(Map<String, dynamic> json) {
    final course = json['course'];
    final mine = json['my_booking'];
    return Batch(
      id: jInt(json['id']),
      title: jStr(json['title']),
      description: jStr(json['description']),
      course: course is Map ? CourseRef.fromJson(jMap(course)) : null,
      daysLabel: jStr(json['days_label']),
      startTime: jStr(json['start_time']),
      endTime: jStr(json['end_time']),
      startDate: jStr(json['start_date']),
      durationLabel: jStr(json['duration_label']),
      totalSeats: jInt(json['total_seats']),
      seatsPerRow: jInt(json['seats_per_row'], 5),
      seatsLeft: jInt(json['seats_left']),
      feePaise: jInt(json['fee_paise']),
      bookingAmountPaise: jInt(json['booking_amount_paise']),
      isActive: json['is_active'] != false,
      seats: jList(json['seats']).map(Seat.fromJson).toList(),
      myBooking: mine is Map ? Booking.fromJson(jMap(mine)) : null,
    );
  }

  bool get isFull => seatsLeft <= 0;
  bool get payAtCenter => bookingAmountPaise == 0;
}

class Shift {
  const Shift({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    required this.monthlyFeePaise,
  });

  final int id;
  final String name;
  final String startTime;
  final String endTime;
  final int monthlyFeePaise;

  factory Shift.fromJson(Map<String, dynamic> json) => Shift(
        id: jInt(json['id']),
        name: jStr(json['name']),
        startTime: jStr(json['start_time']),
        endTime: jStr(json['end_time']),
        monthlyFeePaise: jInt(json['monthly_fee_paise']),
      );
}

class LibraryConfig {
  const LibraryConfig({
    required this.enabled,
    required this.totalDesks,
    required this.desksPerRow,
    required this.maxMonths,
    required this.advanceDays,
  });

  final bool enabled;
  final int totalDesks;
  final int desksPerRow;
  final int maxMonths;
  final int advanceDays;

  factory LibraryConfig.fromJson(Map<String, dynamic> json) => LibraryConfig(
        enabled: jBool(json['enabled']),
        totalDesks: jInt(json['total_desks']),
        desksPerRow: jInt(json['desks_per_row'], 6),
        maxMonths: jInt(json['max_months'], 1),
        advanceDays: jInt(json['advance_days'], 30),
      );
}

class StudyCenterInfo {
  const StudyCenterInfo({
    required this.name,
    required this.address,
    required this.hours,
    required this.phone,
    required this.email,
    required this.holdMinutes,
    required this.library,
    required this.shifts,
  });

  final String name;
  final String address;
  final String hours;
  final String phone;
  final String email;
  final int holdMinutes;
  final LibraryConfig library;
  final List<Shift> shifts;

  factory StudyCenterInfo.fromJson(Map<String, dynamic> json) => StudyCenterInfo(
        name: jStr(json['name'], 'Study Center'),
        address: jStr(json['address']),
        hours: jStr(json['hours']),
        phone: jStr(json['phone']),
        email: jStr(json['email']),
        holdMinutes: jInt(json['hold_minutes'], 10),
        library: LibraryConfig.fromJson(jMap(json['library'])),
        shifts: jList(json['shifts']).map(Shift.fromJson).toList(),
      );
}

class LibraryAvailability {
  const LibraryAvailability({
    required this.shift,
    required this.startDate,
    required this.endDate,
    required this.validUntil,
    required this.months,
    required this.amountPaise,
    required this.desksPerRow,
    required this.seats,
  });

  final Shift shift;
  final String startDate;
  final String endDate;
  final String validUntil;
  final int months;
  final int amountPaise;
  final int desksPerRow;
  final List<Seat> seats;

  factory LibraryAvailability.fromJson(Map<String, dynamic> json) => LibraryAvailability(
        shift: Shift.fromJson(jMap(json['shift'])),
        startDate: jStr(json['start_date']),
        endDate: jStr(json['end_date']),
        validUntil: jStr(json['valid_until']),
        months: jInt(json['months'], 1),
        amountPaise: jInt(json['amount_paise']),
        desksPerRow: jInt(json['desks_per_row'], 6),
        seats: jList(json['seats']).map(Seat.fromJson).toList(),
      );
}

class Booking {
  Booking({
    required this.id,
    required this.code,
    required this.type,
    required this.status,
    required this.seatNo,
    required this.seatLabel,
    required this.amountPaise,
    required this.holdExpiresAt,
    required this.periodStart,
    required this.periodEnd,
    required this.validUntil,
    required this.months,
    required this.batch,
    required this.shift,
    required this.description,
    required this.cancelReason,
    required this.createdAt,
    required this.confirmedAt,
  });

  final int id;
  final String code;

  /// batch | library
  final String type;

  /// held | confirmed | cancelled | expired
  final String status;
  final int seatNo;
  final String seatLabel;
  final int amountPaise;
  final DateTime? holdExpiresAt;
  final String? periodStart;
  final String? periodEnd;
  final String? validUntil;
  final int? months;
  final Batch? batch;
  final Shift? shift;
  final String description;
  final String? cancelReason;
  final DateTime? createdAt;
  final DateTime? confirmedAt;

  factory Booking.fromJson(Map<String, dynamic> json) {
    final batch = json['batch'];
    final shift = json['shift'];
    return Booking(
      id: jInt(json['id']),
      code: jStr(json['code']),
      type: jStr(json['type'], 'batch'),
      status: jStr(json['status']),
      seatNo: jInt(json['seat_no']),
      seatLabel: jStr(json['seat_label']),
      amountPaise: jInt(json['amount_paise']),
      holdExpiresAt: jDate(json['hold_expires_at']),
      periodStart: jStrOrNull(json['period_start']),
      periodEnd: jStrOrNull(json['period_end']),
      validUntil: jStrOrNull(json['valid_until']),
      months: jIntOrNull(json['months']),
      batch: batch is Map ? Batch.fromJson(jMap(batch)) : null,
      shift: shift is Map ? Shift.fromJson(jMap(shift)) : null,
      description: jStr(json['description']),
      cancelReason: jStrOrNull(json['cancel_reason']),
      createdAt: jDate(json['created_at']),
      confirmedAt: jDate(json['confirmed_at']),
    );
  }

  bool get isHeld => status == 'held';
  bool get isConfirmed => status == 'confirmed';
  bool get isLibrary => type == 'library';

  String get title {
    if (isLibrary) return 'Library desk ${shift != null ? '· ${shift!.name}' : ''}'.trim();
    return batch?.title ?? 'Course batch';
  }
}

class BookingResult {
  const BookingResult({required this.booking, required this.checkout});

  final Booking booking;
  final Checkout? checkout;

  factory BookingResult.fromJson(Map<String, dynamic> json) {
    final checkout = json['checkout'];
    return BookingResult(
      booking: Booking.fromJson(jMap(json['booking'])),
      checkout: checkout is Map ? Checkout.fromJson(jMap(checkout)) : null,
    );
  }
}
