import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/study_center.dart';
import '../screens/studycenter/booking_detail_screen.dart';
import '../state/session.dart';
import '../utils/messenger.dart';
import 'payment_flow.dart';

/// After the server holds a seat: pay (if needed) and show the booking.
Future<void> completeBooking(BuildContext context, BookingResult result) async {
  final session = context.read<Session>();
  final navigator = Navigator.of(context);
  var booking = result.booking;
  final checkout = result.checkout;

  if (checkout != null) {
    final payment = await PaymentFlow.pay(context, checkout);
    if (payment == null) {
      session.dataChanged();
      showMessage('Payment not completed. Your seat is held for a few minutes — you can pay from My bookings.');
      return;
    }
    if (payment.refundDue) {
      session.dataChanged();
      showMessage(payment.message);
      return;
    }
    booking = payment.booking ?? booking;
  }

  session.dataChanged();
  await navigator.push(MaterialPageRoute(
    builder: (_) => BookingDetailScreen(bookingId: booking.id, justBooked: true),
  ));
}
