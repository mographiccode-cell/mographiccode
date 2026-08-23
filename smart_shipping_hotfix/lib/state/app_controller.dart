import 'package:flutter/foundation.dart';

import '../data/app_database.dart';
import '../models/domain.dart';
import '../services/auth_service.dart';
import '../services/recommendation_engine.dart';
import '../services/shipping_repository.dart';
import '../services/shipment_validator.dart';

class AppController extends ChangeNotifier {
  AppController(this.database)
      : auth = AuthService(database),
        shipping = ShippingRepository(database);

  final AppDatabase database;
  final AuthService auth;
  final ShippingRepository shipping;
  final RecommendationEngine recommender = RecommendationEngine();
  final ShipmentValidator validator = const ShipmentValidator();

  AppUser? currentUser;
  bool busy = false;
  String? error;
  ComparisonResult? lastComparison;
  List<SavedQuoteItem> saved = const [];
  List<HistoryItem> history = const [];
  String dataNotice = '';
  List<DestinationCountry> countries = const [];

  Future<void> initialize() async {
    await auth.ensureDefaultAccount();
    currentUser = await auth.restoreSession();
    dataNotice = await shipping.dataNotice();
    countries = await shipping.countries();
    if (currentUser != null) await refreshPersonalData();
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    return _guard(() async {
      currentUser = await auth.login(email: email, password: password);
      await refreshPersonalData();
    });
  }

  Future<bool> register(String name, String email, String password) async {
    return _guard(() async {
      currentUser = await auth.register(
        fullName: name,
        email: email,
        password: password,
      );
      await refreshPersonalData();
    });
  }

  Future<void> logout() async {
    await auth.logout();
    currentUser = null;
    lastComparison = null;
    saved = const [];
    history = const [];
    notifyListeners();
  }

  Future<ComparisonResult?> compare(ShipmentDraft draft) async {
    ComparisonResult? result;
    await _guard(() async {
      final validationErrors = validator.validate(draft);
      if (validationErrors.isNotEmpty) {
        throw StateError(validationErrors.join('\n'));
      }
      final quotes = await shipping.retrieveServices(draft);
      result = recommender.build(draft, quotes);
      lastComparison = result;
      await shipping.saveComparison(
        userId: currentUser!.id,
        result: result!,
      );
      history = await shipping.history(currentUser!.id);
    });
    return result;
  }

  Future<void> saveQuote(ShippingQuote quote) async {
    await shipping.saveOption(currentUser!.id, quote);
    saved = await shipping.savedOptions(currentUser!.id);
    notifyListeners();
  }

  Future<void> deleteSaved(int id) async {
    await shipping.deleteSaved(id, currentUser!.id);
    saved = await shipping.savedOptions(currentUser!.id);
    notifyListeners();
  }

  Future<void> refreshPersonalData() async {
    final user = currentUser;
    if (user == null) return;
    saved = await shipping.savedOptions(user.id);
    history = await shipping.history(user.id);
  }

  Future<bool> _guard(Future<void> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await action();
      return true;
    } on AuthException catch (e) {
      error = e.message;
      return false;
    } catch (e) {
      error = 'حدث خطأ غير متوقع: $e';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
