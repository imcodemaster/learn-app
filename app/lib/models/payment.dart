import 'json.dart';
import 'study_center.dart';

/// Everything needed to open Razorpay checkout for one order.
class Checkout {
  const Checkout({
    required this.paymentId,
    required this.mode,
    required this.keyId,
    required this.orderId,
    required this.amount,
    required this.currency,
    required this.name,
    required this.description,
    required this.prefillName,
    required this.prefillEmail,
    required this.prefillContact,
    required this.timeoutSeconds,
  });

  final int paymentId;

  /// razorpay | mock (test mode on the server)
  final String mode;
  final String keyId;
  final String orderId;

  /// Amount in paise.
  final int amount;
  final String currency;
  final String name;
  final String description;
  final String prefillName;
  final String prefillEmail;
  final String prefillContact;
  final int? timeoutSeconds;

  bool get isMock => mode == 'mock';

  factory Checkout.fromJson(Map<String, dynamic> json) {
    final prefill = jMap(json['prefill']);
    return Checkout(
      paymentId: jInt(json['payment_id']),
      mode: jStr(json['mode'], 'razorpay'),
      keyId: jStr(json['key_id']),
      orderId: jStr(json['order_id']),
      amount: jInt(json['amount']),
      currency: jStr(json['currency'], 'INR'),
      name: jStr(json['name'], 'LearnInCreation'),
      description: jStr(json['description']),
      prefillName: jStr(prefill['name']),
      prefillEmail: jStr(prefill['email']),
      prefillContact: jStr(prefill['contact']),
      timeoutSeconds: jIntOrNull(json['timeout_seconds']),
    );
  }
}

class PaymentResult {
  const PaymentResult({
    required this.status,
    required this.purpose,
    required this.courseId,
    required this.booking,
    required this.message,
  });

  final String status;
  final String purpose;
  final int? courseId;
  final Booking? booking;
  final String message;

  bool get isPaid => status == 'paid';
  bool get refundDue => status == 'refund_due';

  factory PaymentResult.fromJson(Map<String, dynamic> json) {
    final booking = json['booking'];
    return PaymentResult(
      status: jStr(json['status']),
      purpose: jStr(json['purpose']),
      courseId: jIntOrNull(json['course_id']),
      booking: booking is Map ? Booking.fromJson(jMap(booking)) : null,
      message: jStr(json['message'], 'Payment recorded.'),
    );
  }
}

class PaymentRecord {
  const PaymentRecord({
    required this.id,
    required this.description,
    required this.amountPaise,
    required this.status,
    required this.purpose,
    required this.providerPaymentId,
    required this.createdAt,
    required this.paidAt,
  });

  final int id;
  final String description;
  final int amountPaise;
  final String status;
  final String purpose;
  final String? providerPaymentId;
  final DateTime? createdAt;
  final DateTime? paidAt;

  factory PaymentRecord.fromJson(Map<String, dynamic> json) => PaymentRecord(
        id: jInt(json['id']),
        description: jStr(json['description']),
        amountPaise: jInt(json['amount_paise']),
        status: jStr(json['status']),
        purpose: jStr(json['purpose']),
        providerPaymentId: jStrOrNull(json['provider_payment_id']),
        createdAt: jDate(json['created_at']),
        paidAt: jDate(json['paid_at']),
      );
}
