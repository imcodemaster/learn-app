import '../api/api_client.dart';
import '../models/app_info.dart';
import '../models/course.dart';
import '../models/json.dart';
import '../models/payment.dart';
import '../models/study_center.dart';
import '../models/user.dart';

Map<String, dynamic> _data(Map<String, dynamic> body) => jMap(body['data']);
List<Map<String, dynamic>> _items(Map<String, dynamic> body) => jList(body['data']);

class AuthApi {
  AuthApi(this.api);

  final ApiClient api;

  Future<AuthResult> register({required String name, required String email, required String password}) async =>
      AuthResult.fromJson(_data(await api.post('/api/auth/register', {
        'name': name,
        'email': email,
        'password': password,
      })));

  Future<AuthResult> login({required String email, required String password}) async =>
      AuthResult.fromJson(_data(await api.post('/api/auth/login', {'email': email, 'password': password})));

  Future<OtpSent> sendOtp(String phone) async =>
      OtpSent.fromJson(_data(await api.post('/api/auth/otp/send', {'phone': phone})));

  Future<AuthResult> verifyOtp({required String phone, required String code, String name = ''}) async =>
      AuthResult.fromJson(_data(await api.post('/api/auth/otp/verify', {
        'phone': phone,
        'code': code,
        'name': name,
      })));

  Future<AuthResult> google(String idToken) async =>
      AuthResult.fromJson(_data(await api.post('/api/auth/google', {'id_token': idToken})));

  Future<void> forgotPassword(String email) async {
    await api.post('/api/auth/password/forgot', {'email': email});
  }

  Future<AuthResult> resetPassword({required String email, required String code, required String password}) async =>
      AuthResult.fromJson(_data(await api.post('/api/auth/password/reset', {
        'email': email,
        'code': code,
        'password': password,
      })));

  Future<void> logout() async {
    await api.post('/api/auth/logout');
  }

  Future<AppUser> me() async => AppUser.fromJson(_data(await api.get('/api/me')));

  Future<AppUser> updateName(String name) async => AppUser.fromJson(_data(await api.patch('/api/me', {'name': name})));

  Future<AppUser> changePassword({String? currentPassword, required String newPassword}) async =>
      AppUser.fromJson(_data(await api.post('/api/me/password', {
        if (currentPassword != null) 'current_password': currentPassword,
        'new_password': newPassword,
      })));

  Future<void> deleteAccount() async {
    await api.post('/api/me/delete', {'confirm': 'DELETE'});
  }
}

class CatalogApi {
  CatalogApi(this.api);

  final ApiClient api;

  Future<AppInfo> appInfo() async => AppInfo.fromJson(_data(await api.get('/api/app/info')));

  Future<List<CourseCategory>> categories() async =>
      _items(await api.get('/api/categories')).map(CourseCategory.fromJson).toList();

  Future<CoursePage> courses({
    String? search,
    String? category,
    String sort = 'recommended',
    String? price,
    bool featured = false,
    int page = 1,
    int perPage = 20,
  }) async {
    final query = <String, String>{'sort': sort, 'page': '$page', 'per_page': '$perPage'};
    if (search != null && search.trim().isNotEmpty) query['search'] = search.trim();
    if (category != null && category.isNotEmpty) query['category'] = category;
    if (price != null) query['price'] = price;
    if (featured) query['featured'] = '1';
    final body = await api.get('/api/courses', query: query);
    return CoursePage(
      items: _items(body).map(CourseSummary.fromJson).toList(),
      meta: PageMeta.fromJson(jMap(body['meta'])),
    );
  }

  Future<CourseDetail> course(int courseId) async =>
      CourseDetail.fromJson(_data(await api.get('/api/courses/$courseId')));

  Future<LessonDetail> lesson(int courseId, int lessonId) async =>
      LessonDetail.fromJson(_data(await api.get('/api/courses/$courseId/lessons/$lessonId')));

  Future<void> enroll(int courseId) async {
    await api.post('/api/courses/$courseId/enroll');
  }

  Future<void> setBookmark(int courseId, bool saved) async {
    if (saved) {
      await api.post('/api/courses/$courseId/bookmark');
    } else {
      await api.delete('/api/courses/$courseId/bookmark');
    }
  }

  Future<Progress> setCompleted(int lessonId, bool completed) async {
    final body = completed
        ? await api.post('/api/lessons/$lessonId/complete')
        : await api.delete('/api/lessons/$lessonId/complete');
    return Progress.fromJson(jMap(_data(body)['progress']));
  }

  Future<List<EnrollmentItem>> myEnrollments() async =>
      _items(await api.get('/api/me/enrollments')).map(EnrollmentItem.fromJson).toList();

  Future<List<CourseSummary>> myBookmarks() async =>
      _items(await api.get('/api/me/bookmarks')).map(CourseSummary.fromJson).toList();
}

class StudyCenterApi {
  StudyCenterApi(this.api);

  final ApiClient api;

  Future<StudyCenterInfo> info() async => StudyCenterInfo.fromJson(_data(await api.get('/api/study-center')));

  Future<List<Batch>> batches() async =>
      _items(await api.get('/api/study-center/batches')).map(Batch.fromJson).toList();

  Future<Batch> batch(int batchId) async => Batch.fromJson(_data(await api.get('/api/study-center/batches/$batchId')));

  Future<BookingResult> bookBatch(int batchId, int seatNo) async =>
      BookingResult.fromJson(_data(await api.post('/api/study-center/batches/$batchId/book', {'seat_no': seatNo})));

  Future<LibraryAvailability> libraryAvailability({
    required int shiftId,
    required String startDate,
    required int months,
  }) async =>
      LibraryAvailability.fromJson(_data(await api.get('/api/study-center/library/availability', query: {
        'shift_id': '$shiftId',
        'start_date': startDate,
        'months': '$months',
      })));

  Future<BookingResult> bookLibrary({
    required int shiftId,
    required String startDate,
    required int months,
    required int seatNo,
  }) async =>
      BookingResult.fromJson(_data(await api.post('/api/study-center/library/book', {
        'shift_id': shiftId,
        'start_date': startDate,
        'months': months,
        'seat_no': seatNo,
      })));

  Future<List<Booking>> myBookings() async => _items(await api.get('/api/me/bookings')).map(Booking.fromJson).toList();

  Future<Booking> booking(int bookingId) async => Booking.fromJson(_data(await api.get('/api/me/bookings/$bookingId')));

  Future<Booking> cancel(int bookingId) async =>
      Booking.fromJson(_data(await api.post('/api/me/bookings/$bookingId/cancel')));
}

class PaymentApi {
  PaymentApi(this.api);

  final ApiClient api;

  Future<Checkout> courseOrder(int courseId) async =>
      Checkout.fromJson(_data(await api.post('/api/payments/course-order', {'course_id': courseId})));

  Future<Checkout> bookingOrder(int bookingId) async =>
      Checkout.fromJson(_data(await api.post('/api/payments/booking-order', {'booking_id': bookingId})));

  Future<PaymentResult> verify({required String orderId, required String paymentId, required String signature}) async =>
      PaymentResult.fromJson(_data(await api.post('/api/payments/verify', {
        'order_id': orderId,
        'payment_id': paymentId,
        'signature': signature,
      })));

  Future<PaymentResult> mockComplete(String orderId) async =>
      PaymentResult.fromJson(_data(await api.post('/api/payments/mock-complete', {'order_id': orderId})));

  Future<List<PaymentRecord>> history() async =>
      _items(await api.get('/api/me/payments')).map(PaymentRecord.fromJson).toList();
}
