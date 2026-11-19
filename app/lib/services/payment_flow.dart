import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../api/api_exception.dart';
import '../models/payment.dart';
import '../state/session.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'apis.dart';

/// Opens Razorpay checkout for an order created by the server and returns the
/// server-verified result, or null if the student closed the payment screen.
///
/// The app never decides the amount and never marks anything as paid itself:
/// the server checks Razorpay's signature first.
class PaymentFlow {
  PaymentFlow._();

  static Future<PaymentResult?> pay(BuildContext context, Checkout checkout) async {
    final payments = PaymentApi(context.read<Session>().api);
    if (checkout.isMock) {
      final confirmed = await _confirmTestPayment(context, checkout);
      if (confirmed != true) return null;
      return payments.mockComplete(checkout.orderId);
    }
    if (checkout.keyId.isEmpty) {
      throw ApiException(status: 0, code: 'payments_not_configured', message: 'Online payments are not set up yet.');
    }

    final completer = Completer<PaymentResult?>();
    final razorpay = Razorpay();

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
      try {
        final result = await payments.verify(
          orderId: response.orderId ?? checkout.orderId,
          paymentId: response.paymentId ?? '',
          signature: response.signature ?? '',
        );
        if (!completer.isCompleted) completer.complete(result);
      } catch (error) {
        if (!completer.isCompleted) completer.completeError(error);
      }
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
      if (completer.isCompleted) return;
      if (response.code == Razorpay.PAYMENT_CANCELLED) {
        completer.complete(null);
      } else {
        completer.completeError(ApiException(
          status: 0,
          code: 'payment_failed',
          message: (response.message == null || response.message!.isEmpty)
              ? 'Payment failed. No money was taken — please try again.'
              : 'Payment failed: ${response.message}',
        ));
      }
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
      // Wallet apps finish outside the app; Razorpay's webhook confirms later.
      if (!completer.isCompleted) completer.complete(null);
    });

    final options = <String, dynamic>{
      'key': checkout.keyId,
      'amount': checkout.amount,
      'currency': checkout.currency,
      'order_id': checkout.orderId,
      'name': checkout.name,
      'description': checkout.description,
      'prefill': <String, String>{
        'name': checkout.prefillName,
        'email': checkout.prefillEmail,
        'contact': checkout.prefillContact,
      },
      'theme': <String, String>{'color': '#4338CA'},
      if (checkout.timeoutSeconds != null) 'timeout': checkout.timeoutSeconds,
    };

    try {
      razorpay.open(options);
      return await completer.future;
    } finally {
      razorpay.clear();
    }
  }

  static Future<bool?> _confirmTestPayment(BuildContext context, Checkout checkout) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.science_outlined, color: AppColors.primary),
        title: const Text('Test payment'),
        content: Text(
          'The server is in test mode, so no money will be charged.\n\n'
          '${checkout.description}\nAmount: ${formatPaise(checkout.amount)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Simulate payment')),
        ],
      ),
    );
  }
}
