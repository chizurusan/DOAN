import 'dart:async';
import 'dart:io' as import_io;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:panorama/panorama.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'src/firebase_options.dart';
import 'src/auth_service.dart';
import 'src/chat_screen.dart';
import 'src/firestore_service.dart';
import 'src/image_upload_service.dart';
import 'src/matterport_embed.dart';
import 'src/member_chat_screen.dart';
import 'src/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {
    // Firebase chưa được cấu hình – chạy ở chế độ demo (không cần database).
  }
  runApp(const RoomifyApp());
}

const Color roomifyNavy = Color(0xFF0A1931);
const Color roomifyGold = Color(0xFFD2A941);
const Color roomifyCream = Color(0xFFF7F2E8);
const Color roomifyMist = Color(0xFFE9EFF7);
const Color roomifyText = Color(0xFF13233D);
const Color roomifyMuted = Color(0xFF68758B);

enum AppTab { home, listings, messages, post }

enum ConnectMode { book, contact }

enum DetailAction { book, contact }

enum AuthMode { login, register }

enum MembershipTier { monthly, quarterly, yearly }

enum PaymentMethod { qr, card }

typedef AuthFlow = Future<bool> Function(AuthMode mode);
typedef MembershipFlow = Future<bool> Function(
    MembershipTier tier, PaymentMethod method);

class MembershipCheckoutResult {
  const MembershipCheckoutResult({required this.tier, required this.method});

  final MembershipTier tier;
  final PaymentMethod method;
}

class MembershipPlanInfo {
  const MembershipPlanInfo({
    required this.tier,
    required this.title,
    required this.price,
    required this.benefit,
    required this.label,
  });

  final MembershipTier tier;
  final String title;
  final String price;
  final String benefit;
  final String label;
}

const List<MembershipPlanInfo> membershipPlans = [
  MembershipPlanInfo(
    tier: MembershipTier.monthly,
    title: 'Gói tháng',
    price: '300.000đ',
    benefit: 'Miễn phí đăng bài trong 1 tháng',
    label: 'Phù hợp để bắt đầu',
  ),
  MembershipPlanInfo(
    tier: MembershipTier.quarterly,
    title: 'Gói 3 tháng',
    price: '700.000đ',
    benefit: 'Miễn phí đăng bài trong 3 tháng',
    label: 'Tiết kiệm hơn đăng lẻ',
  ),
  MembershipPlanInfo(
    tier: MembershipTier.yearly,
    title: 'Gói 1 năm',
    price: '2.100.000đ',
    benefit: 'Miễn phí đăng bài trong 12 tháng',
    label: 'Tối ưu cho người đăng thường xuyên',
  ),
];

MembershipPlanInfo membershipPlanInfo(MembershipTier tier) {
  return membershipPlans.firstWhere((plan) => plan.tier == tier);
}

String paymentMethodLabel(PaymentMethod method) {
  return switch (method) {
    PaymentMethod.qr => 'QR chuyển khoản',
    PaymentMethod.card => 'thẻ thanh toán',
  };
}

int membershipPlanAmount(MembershipPlanInfo plan) {
  final digits = plan.price.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(digits) ?? 0;
}

String membershipPaymentReference(MembershipPlanInfo plan) {
  return 'ROOMIFY-${plan.tier.name.toUpperCase()}';
}

String membershipPaymentPayload(MembershipPlanInfo plan) {
  return [
    'bank=Roomify Bank',
    'account=1020304050',
    'amount=${membershipPlanAmount(plan)}',
    'memo=${membershipPaymentReference(plan)}',
    'plan=${plan.title}',
  ].join(';');
}

class RoomifyApp extends StatefulWidget {
  const RoomifyApp({super.key});

  @override
  State<RoomifyApp> createState() => _RoomifyAppState();
}

class _RoomifyAppState extends State<RoomifyApp> {
  bool _showSplash = true;
  bool _isAuthenticated = false;
  MembershipTier? _membershipTier;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    // Lắng nghe trạng thái đăng nhập từ Firebase (bỏ qua khi chạy demo).
    if (Firebase.apps.isEmpty) return;
    AuthService.instance.authStateChanges.listen((user) async {
      if (!mounted) return;
      if (user != null) {
        // Tạo profile nếu chưa có (đăng nhập lần đầu).
        await FirestoreService.instance.upsertUserProfile(user);
        // Đọc membership từ Firestore.
        final profile = await FirestoreService.instance.getUserProfile(
          user.uid,
        );
        final tierStr = profile?['membershipTier'] as String?;
        final tier = tierStr == null
            ? null
            : MembershipTier.values.firstWhere(
                (t) => t.name == tierStr,
                orElse: () => MembershipTier.monthly,
              );
        if (!mounted) return;
        setState(() {
          _isAuthenticated = true;
          _membershipTier = tier;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _isAuthenticated = false;
          _membershipTier = null;
        });
      }
    });
  }

  void _enterApp() {
    if (_showSplash) {
      setState(() {
        _showSplash = false;
      });
    }
  }

  Future<bool> _openAuthSheet(AuthMode mode) async {
    final modalContext = _navigatorKey.currentContext;
    if (modalContext == null) {
      return false;
    }

    final result = await showModalBottomSheet<bool>(
      context: modalContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AuthSheet(initialMode: mode),
    );

    if (!mounted || result != true) {
      return false;
    }

    _enterApp();
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          mode == AuthMode.login
              ? 'Đăng nhập thành công.'
              : 'Tạo tài khoản thành công.',
        ),
      ),
    );
    return true;
  }

  Future<bool> _purchaseMembership(
    MembershipTier tier,
    PaymentMethod method,
  ) async {
    if (!_isAuthenticated) {
      final authenticated = await _openAuthSheet(AuthMode.login);
      if (!authenticated) {
        return false;
      }
    }

    final plan = membershipPlanInfo(tier);
    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null && Firebase.apps.isNotEmpty) {
      await FirestoreService.instance.updateMembershipTier(uid, tier.name);
    }
    setState(() {
      _membershipTier = tier;
    });

    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          'Đã kích hoạt ${plan.title.toLowerCase()} với giá ${plan.price} qua ${paymentMethodLabel(method)}.',
        ),
      ),
    );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Roomify',
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: roomifyCream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: roomifyNavy,
          brightness: Brightness.light,
          primary: roomifyNavy,
          secondary: roomifyGold,
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: roomifyText,
            fontSize: 30,
            fontWeight: FontWeight.w700,
            height: 1.05,
          ),
          headlineSmall: TextStyle(
            color: roomifyText,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: TextStyle(
            color: roomifyText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          titleMedium: TextStyle(
            color: roomifyText,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
          bodyLarge: TextStyle(color: roomifyText, fontSize: 15, height: 1.55),
          bodyMedium: TextStyle(color: roomifyMuted, fontSize: 14, height: 1.5),
        ),
      ),
      home: _showSplash
          ? SplashScreen(
              onEnter: _enterApp,
              onLogin: () async {
                await _openAuthSheet(AuthMode.login);
              },
              onRegister: () async {
                await _openAuthSheet(AuthMode.register);
              },
            )
          : RoomifyShell(
              onOpenAuth: _openAuthSheet,
              onPurchaseMembership: _purchaseMembership,
              isAuthenticated: _isAuthenticated,
              membershipTier: _membershipTier,
            ),
    );
  }
}

class RoomifyShell extends StatefulWidget {
  const RoomifyShell({
    super.key,
    required this.onOpenAuth,
    required this.onPurchaseMembership,
    required this.isAuthenticated,
    required this.membershipTier,
  });

  final AuthFlow onOpenAuth;
  final MembershipFlow onPurchaseMembership;
  final bool isAuthenticated;
  final MembershipTier? membershipTier;

  @override
  State<RoomifyShell> createState() => _RoomifyShellState();
}

class _RoomifyShellState extends State<RoomifyShell> {
  AppTab _currentTab = AppTab.home;
  PropertyItem _selectedProperty = mockProperties.first;
  final Set<int> _savedPropertyIds = <int>{};
  final List<PropertyItem> _firestoreProperties = [];
  StreamSubscription<List<Map<String, dynamic>>>? _postedSub;
  Offset? _fabPosition;

  @override
  void initState() {
    super.initState();
    _subscribePostedProperties();
  }

  void _subscribePostedProperties() {
    _postedSub =
        FirestoreService.instance.getPostedPropertiesStream().listen((list) {
      if (!mounted) return;
      setState(() {
        _firestoreProperties
          ..clear()
          ..addAll(list.map(_docToProperty));
      });
    });
  }

  PropertyItem _docToProperty(Map<String, dynamic> data) {
    final vrUrl = data['vrUrl'] as String?;
    final panorama = (vrUrl?.isNotEmpty == true) ? vrUrl : null;
    // Chọn Matterport demo xoay vòng dựa theo hash của doc id
    final docId = data['_id'] as String? ?? '';
    final demoMatterport =
        matterportDemos[docId.hashCode.abs() % matterportDemos.length].url;
    final bedroomsRaw = data['bedrooms'];
    final bedroomsVal = (bedroomsRaw is int)
        ? bedroomsRaw
        : int.tryParse(bedroomsRaw?.toString() ?? '') ?? 0;
    final areaRaw = data['area'] as String?;
    final floorsRaw = data['floors'] as String?;
    final descRaw = data['description'] as String?;

    String areaDisplay = 'Đang cập nhật';
    if (areaRaw != null && areaRaw.isNotEmpty) {
      // Nếu đã có đơn vị m² thì giữ nguyên, ngược lại thêm
      areaDisplay = areaRaw.contains('m²') ? areaRaw : '$areaRaw m²';
    }

    return PropertyItem(
      id: docId.hashCode.abs(),
      title: data['title'] as String? ?? 'Không có tiêu đề',
      location: data['location'] as String? ?? 'Không xác định',
      type: data['type'] as String? ?? 'Căn hộ',
      price: data['price'] as String? ?? 'Thương lượng',
      numericPrice: 0,
      bedrooms: bedroomsVal,
      bathrooms: 0,
      area: areaDisplay,
      description: descRaw?.isNotEmpty == true
          ? descRaw!
          : 'Tin đăng từ chủ nhà trên Roomify.',
      vrCopy: vrUrl?.isNotEmpty == true
          ? 'Chủ nhà đã cung cấp link tham quan 360 riêng.'
          : 'Tour VR 360 mẫu – Chủ nhà có thể cập nhật link thực tế sau.',
      tags: [
        'Mới đăng',
        'Chủ nhà',
        if (floorsRaw != null && floorsRaw.isNotEmpty) '$floorsRaw tầng',
      ],
      featured: false,
      colors: const [Color(0xFF19365D), roomifyGold, Color(0xFFE7EEF8)],
      ownerName: data['ownerName'] as String? ?? 'Chủ nhà',
      ownerRole: 'Chủ nhà',
      ownerPhone: data['ownerPhone'] as String? ?? '',
      imageUrl: data['imageUrl'] as String?,
      panoramaUrl: panorama,
      matterportUrl: (vrUrl?.isNotEmpty == true) ? demoMatterport : null,
      ownerId: data['userId'] as String?,
    );
  }

  @override
  void dispose() {
    _postedSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RoomifyShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Khi người dùng đăng nhập, tải danh sách yêu thích từ Firestore.
    if (!oldWidget.isAuthenticated && widget.isAuthenticated) {
      _loadSavedIds();
    }
    // Khi đăng xuất, xóa danh sách yêu thích local.
    if (oldWidget.isAuthenticated && !widget.isAuthenticated) {
      setState(() => _savedPropertyIds.clear());
    }
  }

  Future<void> _loadSavedIds() async {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return;
    final ids = await FirestoreService.instance.getSavedPropertyIds(uid);
    if (!mounted) return;
    setState(() {
      _savedPropertyIds
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _handleProfileTap() async {
    if (widget.isAuthenticated) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            onLogout: () {
              // Logout được xử lý bởi AuthService, state sẽ tự cập nhật
              // qua authStateChanges stream ở cấp độ RoomifyApp.
            },
          ),
        ),
      );
      return;
    }
    await widget.onOpenAuth(AuthMode.login);
  }

  void _showNotifications() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.isAuthenticated
              ? 'Bạn chưa có thông báo mới.'
              : 'Đăng nhập để nhận thông báo về tin phù hợp.',
        ),
      ),
    );
  }

  Future<void> _toggleSaved(PropertyItem property) async {
    if (!widget.isAuthenticated) {
      final authenticated = await widget.onOpenAuth(AuthMode.login);
      if (!mounted || !authenticated) {
        return;
      }
    }

    setState(() {
      if (_savedPropertyIds.contains(property.id)) {
        _savedPropertyIds.remove(property.id);
      } else {
        _savedPropertyIds.add(property.id);
      }
    });

    // Đồng bộ lên Firestore.
    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null) {
      await FirestoreService.instance.toggleSavedProperty(uid, property.id);
    }

    if (!mounted) return;
    final saved = _savedPropertyIds.contains(property.id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Đã lưu ${property.title} vào danh sách yêu thích.'
              : 'Đã bỏ lưu ${property.title}.',
        ),
      ),
    );
  }

  void _openProperty(PropertyItem property) async {
    setState(() {
      _selectedProperty = property;
    });

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PropertyDetailPage(
          property: property,
          isSaved: _savedPropertyIds.contains(property.id),
          onToggleSaved: () => _toggleSaved(property),
          isAuthenticated: widget.isAuthenticated,
          onOpenAuth: widget.onOpenAuth,
        ),
      ),
    );
  }

  void _openVr(PropertyItem property) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VrTourPage(property: property)));
  }

  void _showChatBotDialog(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      barrierColor: Colors.transparent,
      builder: (_) => const _DraggableChatDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mqSize = MediaQuery.of(context).size;
    _fabPosition ??= Offset(mqSize.width - 64, mqSize.height - 160);
    final allProperties = [...mockProperties, ..._firestoreProperties];
    final pages = <Widget>[
      HomeScreen(
        featured:
            mockProperties.where((property) => property.featured).toList(),
        onOpenProperty: _openProperty,
        onOpenVr: _openVr,
        onProfileTap: _handleProfileTap,
        onNotificationTap: _showNotifications,
        onToggleSaved: _toggleSaved,
        savedPropertyIds: _savedPropertyIds,
        isAuthenticated: widget.isAuthenticated,
        membershipTier: widget.membershipTier,
      ),
      ListingsScreen(
        properties: allProperties,
        onOpenProperty: _openProperty,
        onToggleSaved: _toggleSaved,
        savedPropertyIds: _savedPropertyIds,
      ),
      const MemberConversationsScreen(),
      PostPropertyScreen(
        isAuthenticated: widget.isAuthenticated,
        membershipTier: widget.membershipTier,
        onPurchaseMembership: widget.onPurchaseMembership,
        onPreviewCreated: (draft) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã tạo bản xem trước tin đăng.')),
          );
          setState(() {
            _selectedProperty = draft;
          });
        },
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(index: _currentTab.index, children: pages),
          // Nút Chat Bot — kéo được
          Positioned(
            left: _fabPosition!.dx,
            top: _fabPosition!.dy,
            child: GestureDetector(
              onPanUpdate: (details) {
                setState(() {
                  _fabPosition = Offset(
                    (_fabPosition!.dx + details.delta.dx)
                        .clamp(0.0, mqSize.width - 48),
                    (_fabPosition!.dy + details.delta.dy)
                        .clamp(0.0, mqSize.height - 48),
                  );
                });
              },
              child: FloatingActionButton(
                heroTag: 'chatbot_fab',
                onPressed: () {
                  if (defaultTargetPlatform == TargetPlatform.windows ||
                      defaultTargetPlatform == TargetPlatform.macOS ||
                      defaultTargetPlatform == TargetPlatform.linux) {
                    _showChatBotDialog(context);
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ChatBotScreen()),
                    );
                  }
                },
                backgroundColor: roomifyNavy,
                foregroundColor: roomifyGold,
                mini: true,
                elevation: 4,
                tooltip: 'Chat Bot AI',
                child: const Icon(CupertinoIcons.chat_bubble_text_fill),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        height: 72,
        selectedIndex: _currentTab.index,
        backgroundColor: roomifyNavy,
        indicatorColor: roomifyGold.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white);
          }
          return const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white60);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(CupertinoIcons.house, color: Colors.white60),
            selectedIcon: Icon(CupertinoIcons.house_fill, color: Colors.white),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.square_grid_2x2, color: Colors.white60),
            selectedIcon: Icon(
              CupertinoIcons.square_grid_2x2_fill,
              color: Colors.white,
            ),
            label: 'Khám phá',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.chat_bubble_2, color: Colors.white60),
            selectedIcon: Icon(
              CupertinoIcons.chat_bubble_2_fill,
              color: Colors.white,
            ),
            label: 'Tin nhắn',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.add_circled, color: Colors.white60),
            selectedIcon: Icon(
              CupertinoIcons.add_circled_solid,
              color: Colors.white,
            ),
            label: 'Đăng tin',
          ),
        ],
        onDestinationSelected: (index) {
          setState(() {
            _currentTab = AppTab.values[index];
          });
        },
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({
    super.key,
    required this.onEnter,
    required this.onLogin,
    required this.onRegister,
  });

  final VoidCallback onEnter;
  final Future<void> Function() onLogin;
  final Future<void> Function() onRegister;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [roomifyNavy, Color(0xFF102B53), Color(0xFF071524)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              children: [
                const Spacer(),
                Container(
                  width: 122,
                  height: 122,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(34),
                    gradient: const LinearGradient(
                      colors: [roomifyGold, Color(0xFFF2E3B0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: roomifyGold.withValues(alpha: 0.28),
                        blurRadius: 32,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'R',
                    style: TextStyle(
                      color: roomifyNavy,
                      fontSize: 52,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const LabelText('Nền tảng bất động sản số'),
                const SizedBox(height: 14),
                Text(
                  'Xem nhà bằng VR, chốt nhu cầu nhanh hơn.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(
                  'Khám phá nhà ở cao cấp từ xa, xem mức giá ngay lập tức và chuyển thẳng sang đặt lịch hoặc liên hệ tư vấn viên.',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          await onLogin();
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.28),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Đăng nhập'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () async {
                          await onRegister();
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                          backgroundColor: Colors.white,
                          foregroundColor: roomifyNavy,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text('Đăng ký'),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton(
                  onPressed: onEnter,
                  style: FilledButton.styleFrom(
                    backgroundColor: roomifyGold,
                    foregroundColor: roomifyNavy,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Vào Roomify'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.featured,
    required this.onOpenProperty,
    required this.onOpenVr,
    required this.onProfileTap,
    required this.onNotificationTap,
    required this.onToggleSaved,
    required this.savedPropertyIds,
    required this.isAuthenticated,
    required this.membershipTier,
  });

  final List<PropertyItem> featured;
  final ValueChanged<PropertyItem> onOpenProperty;
  final ValueChanged<PropertyItem> onOpenVr;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationTap;
  final ValueChanged<PropertyItem> onToggleSaved;
  final Set<int> savedPropertyIds;
  final bool isAuthenticated;
  final MembershipTier? membershipTier;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final categories = <String, int>{};
    for (final property in mockProperties) {
      categories[property.type] = (categories[property.type] ?? 0) + 1;
    }

    final filtered = mockProperties.where((property) {
      final query = _search.trim().toLowerCase();
      if (query.isEmpty) {
        return true;
      }
      return property.title.toLowerCase().contains(query) ||
          property.location.toLowerCase().contains(query) ||
          property.type.toLowerCase().contains(query);
    }).toList();
    final heroProperty = widget.featured.first;
    final suggested = filtered.take(4).toList();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [roomifyCream, roomifyMist],
        ),
      ),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ProfileAvatarButton(
                        isAuthenticated: widget.isAuthenticated,
                        membershipTier: widget.membershipTier,
                        onTap: widget.onProfileTap,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LabelText(
                              widget.isAuthenticated
                                  ? 'Xin chào trở lại'
                                  : 'Khám phá tự do',
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.isAuthenticated
                                  ? 'Bạn muốn xem căn nào hôm nay?'
                                  : 'Roomify đang mở sẵn để bạn khám phá.',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ],
                        ),
                      ),
                      HeaderIconButton(
                        icon: CupertinoIcons.bell,
                        onPressed: widget.onNotificationTap,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const LabelText('Roomify Mobile'),
                  const SizedBox(height: 8),
                  Text(
                    'Tìm nơi phù hợp với bạn',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 34,
                          height: 1.04,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Ưu tiên trải nghiệm khám phá như một app mobile thật: tìm kiếm nhanh, xem VR ngay và chỉ đăng nhập khi bạn muốn đặt lịch hoặc lưu tin.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  NativeSearchField(
                    hintText: 'Tìm theo tên dự án, khu vực hoặc loại hình',
                    onChanged: (value) {
                      setState(() {
                        _search = value;
                      });
                    },
                  ),
                  const SizedBox(height: 20),
                  PremiumHeroCard(
                    property: heroProperty,
                    onLaunchVr: () => widget.onOpenVr(heroProperty),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const LabelText('Danh mục nhanh'),
                            const SizedBox(height: 8),
                            Text(
                              'Lướt theo nhu cầu của bạn',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      InfoPill('${filtered.length} lựa chọn phù hợp'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SectionHeading(
                    title: 'Danh mục',
                    trailing: TextButton(
                      onPressed: () {},
                      child: const Text('Xem tất cả'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 110,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: categories.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final entry = categories.entries.elementAt(index);
                        return CategoryCard(
                          label: entry.key,
                          count: entry.value,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 26),
                  SectionHeading(
                    title: 'Gợi ý cho bạn',
                    trailing: TextButton(
                      onPressed: () {},
                      child: const Text('Xem thêm'),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (suggested.isEmpty)
                    const EmptyStateCard(
                      title: 'Chưa có kết quả phù hợp.',
                      message:
                          'Hãy đổi từ khóa để khám phá thêm bất động sản có hỗ trợ tour VR.',
                    )
                  else
                    Column(
                      children: [
                        for (final property in suggested) ...[
                          PropertyCard(
                            property: property,
                            compact: true,
                            isSaved: widget.savedPropertyIds.contains(
                              property.id,
                            ),
                            onToggleSaved: () => widget.onToggleSaved(property),
                            onTap: () => widget.onOpenProperty(property),
                          ),
                          if (property != suggested.last)
                            const SizedBox(height: 14),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ListingsScreen extends StatefulWidget {
  const ListingsScreen({
    super.key,
    required this.properties,
    required this.onOpenProperty,
    required this.onToggleSaved,
    required this.savedPropertyIds,
  });

  final List<PropertyItem> properties;
  final ValueChanged<PropertyItem> onOpenProperty;
  final ValueChanged<PropertyItem> onToggleSaved;
  final Set<int> savedPropertyIds;

  @override
  State<ListingsScreen> createState() => _ListingsScreenState();
}

class _ListingsScreenState extends State<ListingsScreen> {
  String _search = '';
  String _price = 'Tất cả';
  String _location = 'Tất cả';
  String _type = 'Tất cả';

  @override
  Widget build(BuildContext context) {
    final districts = [
      'Tất cả',
      ...{for (final property in widget.properties) property.district},
    ];
    final types = [
      'Tất cả',
      ...{for (final property in widget.properties) property.type},
    ];
    const prices = [
      'Tất cả',
      'Dưới 700 nghìn USD',
      '700 nghìn - 1,2 triệu USD',
      'Trên 1,2 triệu USD',
    ];

    final visible = widget.properties.where((property) {
      final query = _search.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          property.title.toLowerCase().contains(query) ||
          property.location.toLowerCase().contains(query) ||
          property.type.toLowerCase().contains(query);
      final matchesLocation =
          _location == 'Tất cả' || property.district == _location;
      final matchesType = _type == 'Tất cả' || property.type == _type;
      final matchesPrice = switch (_price) {
        'Dưới 700 nghìn USD' => property.numericPrice < 700000,
        '700 nghìn - 1,2 triệu USD' =>
          property.numericPrice >= 700000 && property.numericPrice <= 1200000,
        'Trên 1,2 triệu USD' => property.numericPrice > 1200000,
        _ => true,
      };
      return matchesSearch && matchesLocation && matchesType && matchesPrice;
    }).toList();

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [roomifyCream, roomifyMist],
        ),
      ),
      child: CustomScrollView(
        slivers: [
          const NativeSliverHeader(
            title: 'Danh sách bất động sản',
            subtitle: 'Khám phá',
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LabelText('Danh sách'),
                  const SizedBox(height: 8),
                  Text(
                    'Lọc nhanh để ra quyết định dễ hơn.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 18),
                  NativeSearchField(
                    hintText: 'Tìm theo khu vực hoặc loại hình nhà ở',
                    onChanged: (value) {
                      setState(() {
                        _search = value;
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  FilterGroup(
                    title: 'Mức giá',
                    options: prices,
                    selected: _price,
                    onSelected: (value) => setState(() => _price = value),
                  ),
                  const SizedBox(height: 16),
                  FilterGroup(
                    title: 'Khu vực',
                    options: districts,
                    selected: _location,
                    onSelected: (value) => setState(() => _location = value),
                  ),
                  const SizedBox(height: 16),
                  FilterGroup(
                    title: 'Loại hình',
                    options: types,
                    selected: _type,
                    onSelected: (value) => setState(() => _type = value),
                  ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
          if (visible.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: EmptyStateCard(
                  title: 'Hãy thử mở rộng bộ lọc.',
                  message:
                      'Điều chỉnh bộ lọc hoặc xóa từ khóa tìm kiếm để xem thêm các tin có hỗ trợ VR.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList.separated(
                itemCount: visible.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final property = visible[index];
                  return PropertyCard(
                    property: property,
                    compact: true,
                    isSaved: widget.savedPropertyIds.contains(property.id),
                    onToggleSaved: () => widget.onToggleSaved(property),
                    onTap: () => widget.onOpenProperty(property),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ── Draggable Chat Bot Dialog (Desktop) ──────────────────────────────────────
class _DraggableChatDialog extends StatefulWidget {
  const _DraggableChatDialog();

  @override
  State<_DraggableChatDialog> createState() => _DraggableChatDialogState();
}

class _DraggableChatDialogState extends State<_DraggableChatDialog> {
  Offset _position = const Offset(60, 60);
  Size _size = const Size(420, 600);

  static const _minW = 320.0;
  static const _minH = 400.0;
  static const _maxW = 700.0;
  static const _maxH = 900.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    return Stack(
      children: [
        Positioned(
          left: _position.dx.clamp(0, screen.width - _size.width),
          top: _position.dy.clamp(0, screen.height - _size.height),
          child: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: _size.width,
              height: _size.height,
              child: Column(
                children: [
                  // ── Drag handle bar ─────────────────────────────────────
                  GestureDetector(
                    onPanUpdate: (d) {
                      setState(() {
                        _position = Offset(
                          (_position.dx + d.delta.dx)
                              .clamp(0, screen.width - _size.width),
                          (_position.dy + d.delta.dy)
                              .clamp(0, screen.height - _size.height),
                        );
                      });
                    },
                    child: Container(
                      height: 44,
                      decoration: const BoxDecoration(
                        color: roomifyNavy,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: roomifyGold,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(CupertinoIcons.sparkles,
                                size: 16, color: roomifyNavy),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Roomify Bot',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          const Icon(CupertinoIcons.arrow_up_down,
                              color: Colors.white38, size: 14),
                          const SizedBox(width: 4),
                          const Text(
                            'Kéo để di chuyển',
                            style:
                                TextStyle(color: Colors.white38, fontSize: 11),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: const Icon(CupertinoIcons.xmark_circle_fill,
                                color: Colors.white54, size: 20),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── Chat content ────────────────────────────────────────
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16)),
                      child: const ChatBotScreen(embedded: true),
                    ),
                  ),
                  // ── Resize handle ──────────────────────────────────────
                  GestureDetector(
                    onPanUpdate: (d) {
                      setState(() {
                        _size = Size(
                          (_size.width + d.delta.dx).clamp(_minW, _maxW),
                          (_size.height + d.delta.dy).clamp(_minH, _maxH),
                        );
                      });
                    },
                    child: Container(
                      height: 18,
                      decoration: const BoxDecoration(
                        color: roomifyNavy,
                        borderRadius:
                            BorderRadius.vertical(bottom: Radius.circular(16)),
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 32,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({
    super.key,
    required this.property,
    required this.initialMode,
    required this.isAuthenticated,
    required this.onOpenAuth,
  });

  final PropertyItem property;
  final ConnectMode initialMode;
  final bool isAuthenticated;
  final AuthFlow onOpenAuth;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _notesController = TextEditingController();

  late ConnectMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void didUpdateWidget(covariant ConnectScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode) {
      _mode = widget.initialMode;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _scheduleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_mode == ConnectMode.book && !widget.isAuthenticated) {
      final authenticated = await widget.onOpenAuth(AuthMode.login);
      if (!mounted || !authenticated) {
        return;
      }
    }

    // Lưu yêu cầu vào Firestore.
    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null) {
      await FirestoreService.instance.createBooking(
        userId: uid,
        propertyId: widget.property.id,
        propertyTitle: widget.property.title,
        name: _nameController.text,
        phone: _phoneController.text,
        type: _mode == ConnectMode.book ? 'book' : 'contact',
        schedule:
            _scheduleController.text.isEmpty ? null : _scheduleController.text,
        notes: _notesController.text.isEmpty ? null : _notesController.text,
      );
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _mode == ConnectMode.book
              ? 'Đã gửi yêu cầu đặt lịch xem ${widget.property.title}'
              : 'Đã gửi yêu cầu tư vấn cho ${widget.property.title}',
        ),
      ),
    );

    _formKey.currentState!.reset();
    _nameController.clear();
    _phoneController.clear();
    _scheduleController.clear();
    _notesController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [roomifyCream, roomifyMist],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            const NativeSliverHeader(
              title: 'Đặt lịch và liên hệ',
              subtitle: 'Thao tác',
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LabelText('Liên hệ'),
                    const SizedBox(height: 8),
                    Text(
                      'Chuyển từ quan tâm sang hành động.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 18),
                    SelectedPropertyCard(property: widget.property),
                    const SizedBox(height: 14),
                    OwnerInfoCard(
                      property: widget.property,
                      primaryLabel: _mode == ConnectMode.book
                          ? 'Gửi yêu cầu xem nhà'
                          : 'Gửi yêu cầu tư vấn',
                      onPrimaryAction: () {
                        _submit();
                      },
                    ),
                    // Nút nhắn tin trực tiếp (chỉ hiện với tin đăng từ Firestore)
                    Builder(builder: (context) {
                      final ownerId = widget.property.ownerId;
                      final currentUid = AuthService.instance.currentUser?.uid;
                      if (!widget.isAuthenticated ||
                          ownerId == null ||
                          ownerId == currentUid) {
                        return const SizedBox.shrink();
                      }
                      final currentName =
                          AuthService.instance.currentUser?.displayName ??
                              AuthService.instance.currentUser?.email ??
                              'Thành viên';
                      return Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: StartChatButton(
                          ownerId: ownerId,
                          ownerName: widget.property.ownerName,
                          propertyTitle: widget.property.title,
                          currentUserId: currentUid!,
                          currentUserName: currentName,
                        ),
                      );
                    }),
                    const SizedBox(height: 18),
                    SegmentedButton<ConnectMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: ConnectMode.book,
                          label: Text('Đặt lịch xem nhà'),
                        ),
                        ButtonSegment(
                          value: ConnectMode.contact,
                          label: Text('Liên hệ tư vấn'),
                        ),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _mode = selection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    NativeFormCard(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            AppTextField(
                              controller: _nameController,
                              label: 'Họ và tên',
                              hint: 'Nhập họ và tên của bạn',
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Vui lòng nhập họ và tên'
                                      : null,
                            ),
                            const SizedBox(height: 14),
                            AppTextField(
                              controller: _phoneController,
                              label: 'Số điện thoại',
                              hint: 'Nhập số điện thoại',
                              keyboardType: TextInputType.phone,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Vui lòng nhập số điện thoại'
                                      : null,
                            ),
                            if (_mode == ConnectMode.book) ...[
                              const SizedBox(height: 14),
                              AppTextField(
                                controller: _scheduleController,
                                label: 'Thời gian mong muốn',
                                hint: 'Ví dụ: Ngày mai, 14:00',
                              ),
                            ],
                            const SizedBox(height: 14),
                            AppTextField(
                              controller: _notesController,
                              label: 'Ghi chú',
                              hint:
                                  'Hỏi thêm về nội thất, tiện ích hoặc tài chính.',
                              maxLines: 4,
                            ),
                            const SizedBox(height: 18),
                            FilledButton(
                              onPressed: _submit,
                              style: appPrimaryButtonStyle,
                              child: Text(
                                _mode == ConnectMode.book
                                    ? 'Gửi yêu cầu xem nhà'
                                    : 'Gửi yêu cầu tư vấn',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PostPropertyScreen extends StatefulWidget {
  const PostPropertyScreen({
    super.key,
    required this.onPreviewCreated,
    required this.isAuthenticated,
    required this.membershipTier,
    required this.onPurchaseMembership,
  });

  final ValueChanged<PropertyItem> onPreviewCreated;
  final bool isAuthenticated;
  final MembershipTier? membershipTier;
  final MembershipFlow onPurchaseMembership;

  @override
  State<PostPropertyScreen> createState() => _PostPropertyScreenState();
}

class _PostPropertyScreenState extends State<PostPropertyScreen> {
  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _locationController = TextEditingController();
  final _vrController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _bedroomsController = TextEditingController();
  final _areaController = TextEditingController();
  final _floorsController = TextEditingController();
  final _descController = TextEditingController();
  String _type = 'Căn hộ';
  PropertyItem? _draft;
  XFile? _pickedImage;
  String? _uploadedImageUrl;
  bool _isUploading = false;
  double _uploadProgress = 0;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _vrController.dispose();
    _ownerPhoneController.dispose();
    _bedroomsController.dispose();
    _areaController.dispose();
    _floorsController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImageUploadService.pickImage();
    if (file == null) return;
    setState(() {
      _pickedImage = file;
      _uploadedImageUrl = null;
    });
  }

  Future<void> _createPreview() async {
    final postingPrice = widget.membershipTier == null ? '50.000đ' : '0đ';

    // Upload ảnh nếu người dùng đã chọn nhưng chưa upload.
    if (_pickedImage != null && _uploadedImageUrl == null) {
      final uid = AuthService.instance.currentUser?.uid ?? 'anonymous';
      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });
      try {
        final url = await ImageUploadService.uploadPropertyImage(
          _pickedImage!,
          uid,
          onProgress: (p) => setState(() => _uploadProgress = p),
        );
        setState(() {
          _uploadedImageUrl = url;
          _isUploading = false;
        });
      } catch (e) {
        setState(() => _isUploading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi tải ảnh: $e')),
          );
        }
        return;
      }
    }

    final title =
        _titleController.text.isEmpty ? 'Tin đăng nháp' : _titleController.text;
    final location = _locationController.text.isEmpty
        ? 'Quận/Huyện, Thành phố'
        : _locationController.text;
    final price =
        _priceController.text.isEmpty ? postingPrice : _priceController.text;
    final bedroomsVal = int.tryParse(_bedroomsController.text.trim()) ?? 0;
    final areaVal = _areaController.text.trim().isEmpty
        ? 'Đang cập nhật'
        : '${_areaController.text.trim()} m²';
    final descVal = _descController.text.trim().isEmpty
        ? 'Bản nháp dành cho chủ nhà, sẵn sàng xuất bản với mức giá, hình ảnh và liên kết tham quan 360.'
        : _descController.text.trim();

    final draft = PropertyItem(
      id: 999,
      title: title,
      location: location,
      type: _type,
      price: price,
      numericPrice: 0,
      bedrooms: bedroomsVal,
      bathrooms: 0,
      area: areaVal,
      description: descVal,
      vrCopy: _vrController.text.isEmpty
          ? 'Hãy gắn liên kết 360 để tin đăng nổi bật hơn trên Roomify.'
          : 'Bản nháp này đã có liên kết tham quan 360 để khách có thể xem nhà từ xa.',
      tags: const ['Nháp', 'Chủ nhà'],
      featured: false,
      colors: const [Color(0xFF19365D), roomifyGold, Color(0xFFE7EEF8)],
      ownerName: AuthService.instance.currentUser?.displayName ?? 'Chủ nhà',
      ownerRole: 'Người đăng tin',
      ownerPhone: _ownerPhoneController.text.trim().isEmpty
          ? ''
          : _ownerPhoneController.text.trim(),
      imageUrl: _uploadedImageUrl,
      panoramaUrl: _vrController.text.isEmpty ? null : _vrController.text,
      matterportUrl: null,
    );

    setState(() {
      _draft = draft;
    });
    widget.onPreviewCreated(draft);

    // Lưu tin đăng lên Firestore nếu người dùng đã đăng nhập.
    final uid = AuthService.instance.currentUser?.uid;
    if (uid != null) {
      // Hiển thị hộp thoại xác nhận thông tin trước khi đăng.
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Xác nhận đăng tin'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ConfirmRow(label: 'Tiêu đề', value: title),
              _ConfirmRow(label: 'Mức giá', value: price),
              _ConfirmRow(label: 'Vị trí', value: location),
              _ConfirmRow(label: 'Loại hình', value: _type),
              const SizedBox(height: 10),
              const Text(
                'Tin đăng sẽ được xem xét và hiển thị trên Roomify.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: roomifyNavy),
              child: const Text('Đăng tin'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final ownerName = AuthService.instance.currentUser?.displayName ??
          AuthService.instance.currentUser?.email ??
          'Chủ nhà';
      FirestoreService.instance.postProperty(
        userId: uid,
        ownerName: ownerName,
        title: title,
        price: price,
        location: location,
        type: _type,
        imageUrl: _uploadedImageUrl,
        vrUrl: _vrController.text.isEmpty ? null : _vrController.text,
        ownerPhone: _ownerPhoneController.text.trim().isEmpty
            ? null
            : _ownerPhoneController.text.trim(),
        bedrooms: bedroomsVal > 0 ? bedroomsVal : null,
        area: _areaController.text.trim().isEmpty
            ? null
            : _areaController.text.trim(),
        floors: _floorsController.text.trim().isEmpty
            ? null
            : _floorsController.text.trim(),
        description: _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
      );
    }
  }

  Future<void> _openMembershipPage() async {
    final checkout = await Navigator.of(context).push<MembershipCheckoutResult>(
      MaterialPageRoute(
        builder: (_) => MembershipManagementPage(
          currentTier: widget.membershipTier,
          isAuthenticated: widget.isAuthenticated,
        ),
      ),
    );

    if (!mounted || checkout == null) {
      return;
    }

    await widget.onPurchaseMembership(checkout.tier, checkout.method);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [roomifyCream, roomifyMist],
        ),
      ),
      child: CustomScrollView(
        slivers: [
          const NativeSliverHeader(
            title: 'Đăng bất động sản của bạn',
            subtitle: 'Chủ nhà',
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LabelText('Dành cho chủ nhà'),
                  const SizedBox(height: 8),
                  Text(
                    'Tạo tin đăng chỉ trong vài phút.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 18),
                  MembershipPricingCard(
                    currentTier: widget.membershipTier,
                    onManageMembership: _openMembershipPage,
                  ),
                  const SizedBox(height: 18),
                  NativeFormCard(
                    child: Column(
                      children: [
                        PostingFeeSummary(
                          membershipTier: widget.membershipTier,
                          onManageMembership: _openMembershipPage,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _titleController,
                          label: 'Tiêu đề tin đăng',
                          hint: 'Nhà phố view sông',
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _priceController,
                          label: 'Mức giá',
                          hint: '1,2 triệu USD',
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _locationController,
                          label: 'Vị trí',
                          hint: 'Quận/Huyện, Thành phố',
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _ownerPhoneController,
                          label: 'Số điện thoại chủ nhà',
                          hint: '0901 234 567',
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                controller: _bedroomsController,
                                label: 'Số phòng ngủ',
                                hint: '3',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: AppTextField(
                                controller: _floorsController,
                                label: 'Số tầng',
                                hint: '5',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _areaController,
                          label: 'Diện tích (m²)',
                          hint: '120',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _descController,
                          label: 'Mô tả bất động sản',
                          hint:
                              'Mô tả chi tiết về vị trí, tiện ích, nội thất...',
                          maxLines: 4,
                        ),
                        const SizedBox(height: 14),
                        AppDropdownField<String>(
                          label: 'Loại hình bất động sản',
                          value: _type,
                          items: const [
                            'Căn hộ',
                            'Căn hộ penthouse',
                            'Nhà phố',
                            'Biệt thự',
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _type = value;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        _ImagePickerField(
                          pickedImage: _pickedImage,
                          isUploading: _isUploading,
                          uploadProgress: _uploadProgress,
                          onPick: _pickImage,
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _vrController,
                          label: 'Liên kết tham quan 360',
                          hint: 'https://example.com/360-tour',
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _isUploading ? null : _createPreview,
                          style: appPrimaryButtonStyle,
                          child: const Text('Tạo bản xem trước'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          widget.membershipTier == null
                              ? 'Bạn đang ở chế độ đăng lẻ: 50.000đ/bài.'
                              : 'Gói thành viên đang hoạt động, bài đăng hiện được miễn phí.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  // ── Banner liên hệ thiết kế VR ─────────────────────────
                  NativeFormCard(
                    backgroundColor: roomifyNavy,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LabelText('Dịch vụ của Roomify',
                            color: roomifyGold),
                        const SizedBox(height: 10),
                        const Text(
                          'Thiết kế Tour VR / 360° cho BĐS của bạn',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Đội ngũ Roomify chụp ảnh, dựng 3D và tạo tour VR chuyên nghiệp, giúp BĐS nổi bật và thu hút khách xem nhà từ xa.',
                          style: TextStyle(color: Colors.white70, height: 1.5),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          '📸 Gói 1: 10.000.000đ — Chụp 360° + Tour cơ bản\n'
                          '🎯 Gói 2: 15.000.000đ — Tour VR tương tác đầy đủ\n'
                          '⭐ Gói 3: 35.000.000đ — 3D photorealistic cao cấp',
                          style: TextStyle(color: Colors.white, height: 1.7),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton.icon(
                          onPressed: () => showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Liên hệ thiết kế VR/360°'),
                              content: const Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Đội ngũ Roomify VR sẵn sàng hỗ trợ bạn!'),
                                  SizedBox(height: 12),
                                  Text('📞 Hotline: 0901 234 567'),
                                  SizedBox(height: 4),
                                  Text('📧 Email: vr@roomify.vn'),
                                  SizedBox(height: 4),
                                  Text('🌐 roomify.vn/vr-design'),
                                ],
                              ),
                              actions: [
                                FilledButton(
                                  onPressed: () => Navigator.pop(context),
                                  style: FilledButton.styleFrom(
                                      backgroundColor: roomifyNavy),
                                  child: const Text('Đã hiểu'),
                                ),
                              ],
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: roomifyGold,
                            side: const BorderSide(color: roomifyGold),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(CupertinoIcons.phone_fill),
                          label: const Text('Liên hệ đội ngũ VR của Roomify'),
                        ),
                      ],
                    ),
                  ),
                  // ── Tin đã đăng của người dùng ─────────────────────────
                  const _UserPostingsSection(),
                  const SizedBox(height: 18),
                  if (_draft == null)
                    const EmptyStateCard(
                      title: 'Bản xem trước sẽ hiển thị tại đây.',
                      message:
                          'Dùng biểu mẫu này để mô phỏng quy trình đăng tin của chủ nhà khi demo sản phẩm hoặc thuyết trình.',
                    )
                  else
                    PropertyCard(
                      property: _draft!,
                      compact: true,
                      isSaved: false,
                      onToggleSaved: () {},
                      onTap: () {},
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget hiển thị một dòng xác nhận (label: value).
class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
              child: Text(value, overflow: TextOverflow.ellipsis, maxLines: 2)),
        ],
      ),
    );
  }
}

// Section hiển thị tin đã đăng của người dùng hiện tại.
class _UserPostingsSection extends StatelessWidget {
  const _UserPostingsSection();

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.instance.getUserPostingsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        final listings = snapshot.data ?? [];
        if (listings.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 18),
            const LabelText('Tin đã đăng của bạn'),
            const SizedBox(height: 10),
            ...listings.map((listing) => _UserPostingTile(listing: listing)),
          ],
        );
      },
    );
  }
}

// Tile một tin đăng của người dùng với nút xóa.
class _UserPostingTile extends StatelessWidget {
  const _UserPostingTile({required this.listing});
  final Map<String, dynamic> listing;

  @override
  Widget build(BuildContext context) {
    final docId = listing['_id'] as String;
    final title = listing['title'] as String? ?? 'Không có tiêu đề';
    final price = listing['price'] as String? ?? '';
    final location = listing['location'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: roomifyNavy.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: roomifyNavy.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: roomifyGold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(CupertinoIcons.house_fill,
              color: roomifyGold, size: 20),
        ),
        title: Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$price • $location',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: IconButton(
          icon: const Icon(CupertinoIcons.delete, color: Colors.red, size: 20),
          tooltip: 'Xóa tin đăng',
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Xóa tin đăng'),
                content: Text(
                    'Bạn có chắc muốn xóa tin "$title" không? Hành động này không thể hoàn tác.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Hủy'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Xóa'),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await FirestoreService.instance.deleteProperty(docId);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa tin đăng.')),
                );
              }
            }
          },
        ),
      ),
    );
  }
}

// Widget chọn ảnh thay thế cho ô nhập URL.
class _ImagePickerField extends StatelessWidget {
  const _ImagePickerField({
    required this.pickedImage,
    required this.isUploading,
    required this.uploadProgress,
    required this.onPick,
  });

  final XFile? pickedImage;
  final bool isUploading;
  final double uploadProgress;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hình ảnh bất động sản',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: roomifyNavy,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: isUploading ? null : onPick,
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: roomifyMist,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: roomifyNavy.withOpacity(0.2)),
            ),
            clipBehavior: Clip.antiAlias,
            child: isUploading
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: uploadProgress > 0 ? uploadProgress : null,
                        color: roomifyGold,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        uploadProgress > 0
                            ? 'Đang tải lên... ${(uploadProgress * 100).toStringAsFixed(0)}%'
                            : 'Đang tải lên...',
                        style: const TextStyle(color: roomifyNavy),
                      ),
                    ],
                  )
                : pickedImage != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Trên web path là objectURL, trên desktop là đường dẫn file.
                          kIsWeb
                              ? Image.network(
                                  pickedImage!.path,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholder(context),
                                )
                              : Image.file(
                                  import_io.File(pickedImage!.path),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _placeholder(context),
                                ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: _changeButton(context),
                          ),
                        ],
                      )
                    : _placeholder(context),
          ),
        ),
      ],
    );
  }

  Widget _placeholder(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined,
            size: 48, color: roomifyNavy.withOpacity(0.4)),
        const SizedBox(height: 8),
        Text(
          'Nhấn để chọn ảnh',
          style: TextStyle(color: roomifyNavy.withOpacity(0.5)),
        ),
      ],
    );
  }

  Widget _changeButton(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'Đổi ảnh',
        style: TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class MembershipPricingCard extends StatelessWidget {
  const MembershipPricingCard({
    super.key,
    required this.currentTier,
    required this.onManageMembership,
  });

  final MembershipTier? currentTier;
  final VoidCallback onManageMembership;

  @override
  Widget build(BuildContext context) {
    return NativeFormCard(
      backgroundColor: const Color(0xFFFFFBF4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: LabelText('Chi phí đăng bài')),
              if (currentTier != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: roomifyGold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    membershipPlanInfo(currentTier!).title,
                    style: const TextStyle(
                      color: roomifyNavy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Đăng lẻ 50.000đ cho mỗi bài. Nếu là thành viên đang hoạt động, bạn được miễn phí đăng bài trong suốt thời hạn gói.',
            style: TextStyle(color: roomifyText, fontSize: 15, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: membershipPlans.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final plan = membershipPlans[index];
                return SizedBox(
                  width: 274,
                  child: MembershipPlanTile(
                    title: plan.title,
                    price: plan.price,
                    benefit: plan.benefit,
                    label: plan.label,
                    highlighted: currentTier == null
                        ? plan.tier == MembershipTier.monthly
                        : currentTier == plan.tier,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Vuốt ngang để so sánh các gói rồi chọn cách thanh toán phù hợp.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onManageMembership,
            style: appPrimaryButtonStyle,
            icon: const Icon(CupertinoIcons.creditcard_fill),
            label: Text(
              currentTier == null
                  ? 'Chọn gói và thanh toán'
                  : 'Gia hạn hoặc đổi gói',
            ),
          ),
        ],
      ),
    );
  }
}

class MembershipPlanTile extends StatelessWidget {
  const MembershipPlanTile({
    super.key,
    required this.title,
    required this.price,
    required this.benefit,
    required this.label,
    this.highlighted = false,
  });

  final String title;
  final String price;
  final String benefit;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? roomifyNavy : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: highlighted
              ? roomifyGold.withValues(alpha: 0.55)
              : roomifyNavy.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: highlighted ? Colors.white : roomifyText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  benefit,
                  style: TextStyle(
                    color: highlighted ? Colors.white70 : roomifyMuted,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: highlighted ? roomifyGold : roomifyNavy,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: highlighted
                  ? roomifyGold.withValues(alpha: 0.18)
                  : roomifyGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              price,
              style: TextStyle(
                color: highlighted ? roomifyGold : roomifyNavy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PostingFeeSummary extends StatelessWidget {
  const PostingFeeSummary({
    super.key,
    required this.membershipTier,
    required this.onManageMembership,
  });

  final MembershipTier? membershipTier;
  final VoidCallback onManageMembership;

  @override
  Widget build(BuildContext context) {
    final isMember = membershipTier != null;
    final title =
        isMember ? 'Phí đăng hiện tại: 0đ' : 'Phí đăng hiện tại: 50.000đ/bài';
    final subtitle = isMember
        ? 'Bạn đang dùng ${membershipPlanInfo(membershipTier!).title.toLowerCase()}, mọi bài đăng đều được miễn phí.'
        : 'Kích hoạt gói thành viên để miễn phí đăng bài ngay từ bài đầu tiên.';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isMember ? roomifyGold.withValues(alpha: 0.12) : roomifyMist,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            isMember
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.money_dollar_circle,
            color: isMember ? roomifyGold : roomifyNavy,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          TextButton(
            onPressed: onManageMembership,
            child: const Text('Xem gói'),
          ),
        ],
      ),
    );
  }
}

class MembershipManagementPage extends StatefulWidget {
  const MembershipManagementPage({
    super.key,
    required this.currentTier,
    required this.isAuthenticated,
  });

  final MembershipTier? currentTier;
  final bool isAuthenticated;

  @override
  State<MembershipManagementPage> createState() =>
      _MembershipManagementPageState();
}

class _MembershipManagementPageState extends State<MembershipManagementPage> {
  late final PageController _pageController;
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.currentTier == null
        ? 0
        : membershipPlans.indexWhere((plan) => plan.tier == widget.currentTier);
    if (_selectedIndex < 0) {
      _selectedIndex = 0;
    }
    _pageController = PageController(
      viewportFraction: 0.86,
      initialPage: _selectedIndex,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openPaymentSheet(MembershipPlanInfo plan) async {
    final method = await showModalBottomSheet<PaymentMethod>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MembershipPaymentSheet(plan: plan),
    );

    if (!mounted || method == null) {
      return;
    }

    Navigator.of(
      context,
    ).pop(MembershipCheckoutResult(tier: plan.tier, method: method));
  }

  @override
  Widget build(BuildContext context) {
    final selectedPlan = membershipPlans[_selectedIndex];

    return Scaffold(
      backgroundColor: roomifyCream,
      appBar: AppBar(
        backgroundColor: roomifyCream,
        foregroundColor: roomifyNavy,
        title: const Text('Quản lý gói thành viên'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          NativeFormCard(
            backgroundColor: roomifyNavy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LabelText('Trạng thái thành viên', color: roomifyGold),
                const SizedBox(height: 10),
                Text(
                  widget.currentTier == null
                      ? 'Bạn đang ở chế độ đăng lẻ'
                      : 'Đang kích hoạt ${membershipPlanInfo(widget.currentTier!).title.toLowerCase()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.currentTier == null
                      ? 'Đăng từng bài với phí 50.000đ hoặc nâng cấp để miễn phí đăng bài.'
                      : 'Mọi tin đăng mới trong thời hạn gói đều được miễn phí. Bạn có thể nâng cấp hoặc gia hạn ngay trên màn này.',
                  style: const TextStyle(color: Colors.white70, height: 1.55),
                ),
                if (!widget.isAuthenticated) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Bạn sẽ được yêu cầu đăng nhập trước khi kích hoạt gói.',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 280,
            child: PageView.builder(
              controller: _pageController,
              itemCount: membershipPlans.length,
              onPageChanged: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final plan = membershipPlans[index];
                final active = widget.currentTier == plan.tier;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: NativeFormCard(
                    backgroundColor: active ? roomifyNavy : Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                plan.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color:
                                          active ? Colors.white : roomifyText,
                                    ),
                              ),
                            ),
                            PriceChip(plan.price),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          plan.benefit,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: active ? Colors.white : roomifyText,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          plan.label,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: active ? Colors.white70 : roomifyMuted,
                              ),
                        ),
                        const Spacer(),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            InfoPill(active ? 'Đang dùng' : 'Có thể nâng cấp'),
                            const InfoPill('QR hoặc thẻ'),
                          ],
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _openPaymentSheet(plan),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            backgroundColor: active ? roomifyGold : roomifyNavy,
                            foregroundColor:
                                active ? roomifyNavy : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          icon: const Icon(CupertinoIcons.creditcard),
                          label: Text(
                            active
                                ? 'Gia hạn và thanh toán'
                                : 'Thanh toán gói này',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var index = 0; index < membershipPlans.length; index++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  height: 8,
                  width: index == _selectedIndex ? 26 : 8,
                  decoration: BoxDecoration(
                    color: index == _selectedIndex ? roomifyNavy : roomifyMuted,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          NativeFormCard(
            backgroundColor: const Color(0xFFFFFBF4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LabelText('Gói đang chọn'),
                const SizedBox(height: 10),
                Text(
                  selectedPlan.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '${selectedPlan.price} • ${selectedPlan.benefit}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Vuốt ngang để đổi gói, sau đó bấm thanh toán để mở QR hoặc nhập thẻ.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MembershipPaymentSheet extends StatefulWidget {
  const MembershipPaymentSheet({super.key, required this.plan});

  final MembershipPlanInfo plan;

  @override
  State<MembershipPaymentSheet> createState() => _MembershipPaymentSheetState();
}

class _MembershipPaymentSheetState extends State<MembershipPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _cardholderController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  PaymentMethod _method = PaymentMethod.qr;

  @override
  void dispose() {
    _cardholderController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_method == PaymentMethod.card && !_formKey.currentState!.validate()) {
      return;
    }

    Navigator.of(context).pop(_method);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: NativeFormCard(
        backgroundColor: Colors.white,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LabelText('Thanh toán thành viên'),
                const SizedBox(height: 10),
                Text(
                  widget.plan.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                Text(
                  '${widget.plan.price} • ${widget.plan.benefit}',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                SegmentedButton<PaymentMethod>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: PaymentMethod.qr,
                      label: Text('QR'),
                      icon: Icon(CupertinoIcons.qrcode_viewfinder),
                    ),
                    ButtonSegment(
                      value: PaymentMethod.card,
                      label: Text('Thẻ'),
                      icon: Icon(CupertinoIcons.creditcard),
                    ),
                  ],
                  selected: {_method},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _method = selection.first;
                    });
                  },
                ),
                const SizedBox(height: 18),
                if (_method == PaymentMethod.qr)
                  QrPaymentPreview(plan: widget.plan)
                else
                  Column(
                    children: [
                      AppTextField(
                        controller: _cardholderController,
                        label: 'Tên chủ thẻ',
                        hint: 'NGUYEN VAN A',
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập tên chủ thẻ';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _cardNumberController,
                        label: 'Số thẻ',
                        hint: '4111 1111 1111 1111',
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(19),
                          CardNumberInputFormatter(),
                        ],
                        validator: (value) {
                          final digits = value?.replaceAll(' ', '') ?? '';
                          if (digits.length < 16) {
                            return 'Số thẻ cần ít nhất 16 số';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _expiryController,
                              label: 'Ngày hết hạn',
                              hint: 'MM/YY',
                              keyboardType: TextInputType.datetime,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                                ExpiryDateInputFormatter(),
                              ],
                              validator: (value) {
                                final text = value?.trim() ?? '';
                                if (text.isEmpty) {
                                  return 'Nhập MM/YY';
                                }
                                if (!RegExp(
                                  r'^(0[1-9]|1[0-2])/[0-9]{2}$',
                                ).hasMatch(text)) {
                                  return 'Ngày hết hạn chưa hợp lệ';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _cvvController,
                              label: 'CVV',
                              hint: '123',
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              validator: (value) {
                                if (value == null || value.trim().length < 3) {
                                  return 'CVV chưa hợp lệ';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _submit,
                  style: appPrimaryButtonStyle,
                  icon: Icon(
                    _method == PaymentMethod.qr
                        ? CupertinoIcons.qrcode_viewfinder
                        : CupertinoIcons.check_mark_circled_solid,
                  ),
                  label: Text(
                    _method == PaymentMethod.qr
                        ? 'Xác nhận đã quét QR'
                        : 'Xác nhận thanh toán bằng thẻ',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QrPaymentPreview extends StatelessWidget {
  const QrPaymentPreview({super.key, required this.plan});

  final MembershipPlanInfo plan;

  @override
  Widget build(BuildContext context) {
    final payload = membershipPaymentPayload(plan);
    final reference = membershipPaymentReference(plan);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: roomifyCream,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              Container(
                width: 176,
                height: 176,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: roomifyNavy.withValues(alpha: 0.08),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: payload,
                    version: QrVersions.auto,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: roomifyNavy,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: roomifyNavy,
                    ),
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Roomify Membership',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '${plan.title} • ${plan.price}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                reference,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: roomifyNavy,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Ngân hàng demo: Roomify Bank • STK 1020304050 • Nội dung: $reference',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: payload));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã sao chép mã thanh toán QR.')),
              );
            }
          },
          icon: const Icon(CupertinoIcons.doc_on_doc),
          label: const Text('Sao chép mã thanh toán'),
        ),
      ],
    );
  }
}

class CardNumberInputFormatter extends TextInputFormatter {
  const CardNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var index = 0; index < digits.length; index++) {
      if (index > 0 && index % 4 == 0) {
        buffer.write(' ');
      }
      buffer.write(digits[index]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class ExpiryDateInputFormatter extends TextInputFormatter {
  const ExpiryDateInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue();
    }

    final trimmed = digits.length > 4 ? digits.substring(0, 4) : digits;
    final buffer = StringBuffer();
    for (var index = 0; index < trimmed.length; index++) {
      if (index == 2) {
        buffer.write('/');
      }
      buffer.write(trimmed[index]);
    }
    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class PropertyDetailPage extends StatelessWidget {
  const PropertyDetailPage({
    super.key,
    required this.property,
    required this.isSaved,
    required this.onToggleSaved,
    required this.isAuthenticated,
    required this.onOpenAuth,
  });

  final PropertyItem property;
  final bool isSaved;
  final VoidCallback onToggleSaved;
  final bool isAuthenticated;
  final AuthFlow onOpenAuth;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: roomifyCream,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ConnectScreen(
                      property: property,
                      initialMode: ConnectMode.contact,
                      isAuthenticated: isAuthenticated,
                      onOpenAuth: onOpenAuth,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: Color(0x1F0A1931)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('Liên hệ tư vấn'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ConnectScreen(
                      property: property,
                      initialMode: ConnectMode.book,
                      isAuthenticated: isAuthenticated,
                      onOpenAuth: onOpenAuth,
                    ),
                  ),
                ),
                style: appPrimaryButtonStyle,
                child: const Text('Đặt lịch xem nhà'),
              ),
            ),
          ],
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            pinned: true,
            stretch: true,
            backgroundColor: roomifyCream,
            foregroundColor: roomifyNavy,
            title: Text(property.title),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: SaveIconButton(
                  isSaved: isSaved,
                  onPressed: onToggleSaved,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: PropertyArt(property: property, height: 320),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LabelText(property.type),
                            const SizedBox(height: 8),
                            Text(
                              property.title,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              property.location,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      PriceChip(property.price),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    property.description,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: 'Phòng ngủ',
                          value: '${property.bedrooms}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricTile(
                          label: 'Phòng tắm',
                          value: '${property.bathrooms}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricTile(
                          label: 'Diện tích',
                          value: property.area,
                        ),
                      ),
                    ],
                  ),
                  if (property.panoramaUrl != null) ...[
                    const SizedBox(height: 18),
                    NativeFormCard(
                      backgroundColor: roomifyNavy,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const LabelText('Điểm nổi bật', color: roomifyGold),
                          const SizedBox(height: 10),
                          const Text(
                            'Tham quan bất động sản 360/VR',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            property.vrCopy,
                            style: const TextStyle(
                              color: Colors.white70,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      VrTourPage(property: property),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: roomifyGold,
                              foregroundColor: roomifyNavy,
                              minimumSize: const Size.fromHeight(54),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            child: const Text('Mở tour 360/VR'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  NativeFormCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            gradient: const LinearGradient(
                              colors: [Color(0x33D2A941), Color(0x120A1931)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(
                            CupertinoIcons.location_solid,
                            color: roomifyGold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const LabelText('Vị trí'),
                              const SizedBox(height: 8),
                              Text(
                                property.location,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Kết nối thuận tiện tới trường học, dịch vụ ăn uống và các trục di chuyển chính.',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  OwnerInfoCard(
                    property: property,
                    primaryLabel: 'Liên hệ chủ nhà',
                    onPrimaryAction: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ConnectScreen(
                          property: property,
                          initialMode: ConnectMode.contact,
                          isAuthenticated: isAuthenticated,
                          onOpenAuth: onOpenAuth,
                        ),
                      ),
                    ),
                  ),
                  // Nút nhắn tin cho tin đăng từ Firestore
                  Builder(builder: (context) {
                    final currentUid = AuthService.instance.currentUser?.uid;
                    final ownerId = property.ownerId;
                    if (ownerId == null || ownerId == currentUid) {
                      return const SizedBox.shrink();
                    }
                    if (currentUid == null) {
                      return const SizedBox.shrink();
                    }
                    final currentName =
                        AuthService.instance.currentUser?.displayName ??
                            AuthService.instance.currentUser?.email ??
                            'Thành viên';
                    return Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: StartChatButton(
                        ownerId: ownerId,
                        ownerName: property.ownerName,
                        propertyTitle: property.title,
                        currentUserId: currentUid,
                        currentUserName: currentName,
                      ),
                    );
                  }),
                  const SizedBox(height: 120),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VrTourPage extends StatelessWidget {
  const VrTourPage({super.key, required this.property});

  final PropertyItem property;

  @override
  Widget build(BuildContext context) {
    final panoramaUrl = property.panoramaUrl;
    return Scaffold(
      backgroundColor: roomifyNavy,
      appBar: AppBar(
        backgroundColor: roomifyNavy,
        foregroundColor: Colors.white,
        title: const Text('Tour VR 360'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LabelText('Xem thử sống động', color: roomifyGold),
              const SizedBox(height: 10),
              Text(
                'Tour 360 của ${property.title}',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 10),
              Text(
                property.vrCopy,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 20),
              // ── 360° Panorama Viewer ──────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 320,
                  child: panoramaUrl != null
                      ? Stack(
                          children: [
                            Panorama(
                              animSpeed: 0.4,
                              sensitivity: 1.8,
                              child: Image.network(
                                panoramaUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _PanoramaError(),
                              ),
                            ),
                            // Hint kéo
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(CupertinoIcons.hand_draw,
                                          color: Colors.white70, size: 16),
                                      SizedBox(width: 6),
                                      Text(
                                        'Kéo để xoay 360°',
                                        style: TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : _PanoramaError(),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  VrTag('Kéo để xoay 360°'),
                  VrTag('Cảm nhận không gian'),
                  VrTag('Chuyển phòng/tầng'),
                  VrTag('Sẵn sàng demo'),
                ],
              ),
              if (property.matterportUrl != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => MatterportTourPage(
                          title: 'Matterport - ${property.title}',
                          url: property.matterportUrl!,
                        ),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: roomifyGold,
                    foregroundColor: roomifyNavy,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(CupertinoIcons.cube_box_fill),
                  label: const Text('Mở demo Matterport'),
                ),
              ],
              const SizedBox(height: 28),
              MatterportDemoList(currentUrl: property.matterportUrl),
              const SizedBox(height: 28),
              // ── Bảng giá thiết kế VR ─────────────────────────────
              LabelText('Đặt thiết kế VR cho bất động sản', color: roomifyGold),
              const SizedBox(height: 12),
              Text(
                'Nâng tầm tin đăng với tour VR chuyên nghiệp.',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 16),
              _VrPricingCard(
                icon: CupertinoIcons.camera_rotate,
                title: 'Thiết kế 360 + VR',
                price: '10.000.000đ',
                features: const [
                  'Chụp ảnh 360° toàn bộ không gian',
                  'Tour VR cơ bản (xem qua trình duyệt)',
                  'Tích hợp vào tin đăng Roomify',
                ],
              ),
              const SizedBox(height: 12),
              _VrPricingCard(
                icon: CupertinoIcons.cube_box,
                title: 'Thiết kế VR',
                price: '15.000.000đ',
                features: const [
                  'Tour VR tương tác đầy đủ',
                  'Hotspot điểm nổi bật từng phòng',
                  'Tương thích kính VR & di động',
                  'Báo cáo lượt xem hàng tháng',
                ],
                highlighted: true,
              ),
              const SizedBox(height: 12),
              _VrPricingCard(
                icon: CupertinoIcons.star_fill,
                title: 'Thiết kế VR cao cấp',
                price: '35.000.000đ',
                features: const [
                  'Tour VR cao cấp nhiều tầng/khu vực',
                  'Dựng cảnh 3D nội thất photorealistic',
                  'Âm thanh môi trường & hiệu ứng ánh sáng',
                  'Nhà ảo tương tác (chọn nội thất trực tiếp)',
                  'Hỗ trợ kỹ thuật 6 tháng',
                ],
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(CupertinoIcons.back),
                label: const Text('Quay lại'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class MatterportTourPage extends StatefulWidget {
  const MatterportTourPage({super.key, required this.title, required this.url});

  final String title;
  final String url;

  @override
  State<MatterportTourPage> createState() => _MatterportTourPageState();
}

class _MatterportTourPageState extends State<MatterportTourPage> {
  bool _launching = false;

  Future<void> _openInBrowser() async {
    setState(() => _launching = true);
    final uri = Uri.parse(widget.url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở trình duyệt.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể mở liên kết VR.')),
        );
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: roomifyNavy,
      appBar: AppBar(
        backgroundColor: roomifyNavy,
        foregroundColor: Colors.white,
        title: Text(widget.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LabelText('Matterport Demo', color: roomifyGold),
              const SizedBox(height: 8),
              if (matterportEmbedSupported) ...[
                Text(
                  'Dùng các điểm tương tác để di chuyển phòng, lên tầng và xem không gian như tour thật.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      color: Colors.black,
                      child: buildMatterportEmbed(url: widget.url),
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  'Tour VR 3D hoạt động tốt nhất trên Chrome hoặc trình duyệt của bạn.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF1B3560),
                            roomifyNavy,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: roomifyGold.withValues(alpha: 0.3),
                            width: 1),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: roomifyGold.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                              border: Border.all(color: roomifyGold, width: 2),
                            ),
                            child: const Icon(
                              CupertinoIcons.cube_box_fill,
                              color: roomifyGold,
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Tour VR 3D Matterport',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Nhấn bên dưới để mở tour tham quan 3D trong trình duyệt. Trải nghiệm đầy đủ bao gồm di chuyển phòng, đo không gian và xem chi tiết.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: FilledButton.icon(
                              onPressed: _launching ? null : _openInBrowser,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                                backgroundColor: roomifyGold,
                                foregroundColor: roomifyNavy,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: _launching
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: roomifyNavy),
                                    )
                                  : const Icon(CupertinoIcons
                                      .arrow_up_right_square_fill),
                              label: Text(
                                _launching
                                    ? 'Đang mở...'
                                    : 'Mở Tour VR trong trình duyệt',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: _launching ? null : _openInBrowser,
                            icon: const Icon(CupertinoIcons.share,
                                size: 16, color: Colors.white38),
                            label: const Text(
                              'Sao chép liên kết hoặc chia sẻ',
                              style: TextStyle(
                                  color: Colors.white38, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  VrTag('Di chuyển 360°'),
                  VrTag('Đo không gian'),
                  VrTag('Chuyển phòng / tầng'),
                  VrTag('Xem chi tiết nội thất'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── VR Pricing Card ───────────────────────────────────────────────────────────
class _VrPricingCard extends StatelessWidget {
  const _VrPricingCard({
    required this.icon,
    required this.title,
    required this.price,
    required this.features,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String price;
  final List<String> features;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final borderColor = highlighted ? roomifyGold : Colors.white24;
    final bg = highlighted
        ? roomifyGold.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.06);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: highlighted ? 1.5 : 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  color: highlighted ? roomifyGold : Colors.white70, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: highlighted ? roomifyGold : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: highlighted ? roomifyGold : Colors.white12,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  price,
                  style: TextStyle(
                    color: highlighted ? roomifyNavy : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(CupertinoIcons.checkmark_alt,
                      size: 14, color: roomifyGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MatterportDemoList extends StatelessWidget {
  const MatterportDemoList({super.key, this.currentUrl});

  final String? currentUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LabelText('Tour Matterport mẫu', color: roomifyGold),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: matterportDemos.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final demo = matterportDemos[index];
              final active = demo.url == currentUrl;
              return SizedBox(
                width: 220,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            MatterportTourPage(title: demo.name, url: demo.url),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.16)
                          : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: active
                            ? roomifyGold
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          demo.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          demo.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class NativeSliverHeader extends StatelessWidget {
  const NativeSliverHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      backgroundColor: roomifyCream.withValues(alpha: 0.96),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      toolbarHeight: 74,
      titleSpacing: 20,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabelText(subtitle),
          const SizedBox(height: 2),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
      actions: [...trailing, const SizedBox(width: 20)],
    );
  }
}

class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: roomifyNavy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: Icon(icon),
    );
  }
}

class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({
    super.key,
    required this.isAuthenticated,
    required this.membershipTier,
    required this.onTap,
  });

  final bool isAuthenticated;
  final MembershipTier? membershipTier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  colors: isAuthenticated
                      ? const [roomifyNavy, Color(0xFF1B4577)]
                      : const [Color(0xFFFFF6E3), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: roomifyNavy.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                CupertinoIcons.person_crop_circle_fill,
                color: isAuthenticated ? roomifyGold : roomifyNavy,
              ),
            ),
            if (membershipTier != null)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: roomifyGold,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Text(
                    'VIP',
                    style: TextStyle(
                      color: roomifyNavy,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NativeSearchField extends StatelessWidget {
  const NativeSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
  });

  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(CupertinoIcons.search, color: roomifyMuted),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class PremiumHeroCard extends StatelessWidget {
  const PremiumHeroCard({
    super.key,
    required this.property,
    required this.onLaunchVr,
  });

  final PropertyItem property;
  final VoidCallback onLaunchVr;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [roomifyNavy, property.colors.first],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: roomifyNavy.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LabelText('Tính năng nổi bật', color: roomifyGold),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'VIEW IN VR',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Tham quan ${property.title} ngay trên điện thoại',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            'Xem trước bố cục, ánh sáng và vật liệu hoàn thiện với trải nghiệm VR được đặt ở vị trí trung tâm của sản phẩm.',
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              InfoTag(label: property.type),
              InfoTag(label: property.area),
              const InfoTag(label: 'Trải nghiệm 360'),
            ],
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onLaunchVr,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: roomifyNavy,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text('Mở tour 360'),
          ),
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    required this.trailing,
  });

  final String title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        trailing,
      ],
    );
  }
}

class CategoryCard extends StatelessWidget {
  const CategoryCard({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 138,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LabelText('$count tin'),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}

class PropertyCard extends StatelessWidget {
  const PropertyCard({
    super.key,
    required this.property,
    required this.compact,
    required this.isSaved,
    required this.onToggleSaved,
    required this.onTap,
  });

  final PropertyItem property;
  final bool compact;
  final bool isSaved;
  final VoidCallback onToggleSaved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageHeight = compact ? 184.0 : 120.0;
    final descriptionSpacing = compact ? 12.0 : 10.0;
    final footerSpacing = compact ? 14.0 : 10.0;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                  child: PropertyArt(property: property, height: imageHeight),
                ),
                Positioned(
                  top: 14,
                  right: 14,
                  child: SaveIconButton(
                    isSaved: isSaved,
                    onPressed: onToggleSaved,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              property.title,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: compact ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              property.location,
                              style: Theme.of(context).textTheme.bodyMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      PriceChip(property.price),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: property.tags
                        .take(2)
                        .map((tag) => InfoTag(label: tag, dense: true))
                        .toList(),
                  ),
                  SizedBox(height: descriptionSpacing),
                  Text(
                    property.description,
                    maxLines: compact ? 2 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: footerSpacing),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${property.bedrooms} PN • ${property.bathrooms} PT • ${property.area}',
                          style: Theme.of(context).textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!compact)
                        TextButton(
                          onPressed: onTap,
                          child: const Text('Xem chi tiết'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PriceChip extends StatelessWidget {
  const PriceChip(this.price, {super.key});

  final String price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: roomifyGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        price,
        style: const TextStyle(color: roomifyNavy, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class SaveIconButton extends StatelessWidget {
  const SaveIconButton({
    super.key,
    required this.isSaved,
    required this.onPressed,
  });

  final bool isSaved;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        foregroundColor: isSaved ? roomifyGold : roomifyNavy,
      ),
      icon: Icon(isSaved ? CupertinoIcons.heart_fill : CupertinoIcons.heart),
    );
  }
}

class PropertyArt extends StatelessWidget {
  const PropertyArt({super.key, required this.property, required this.height});

  final PropertyItem property;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (property.imageUrl != null && property.imageUrl!.isNotEmpty) {
      return Image.network(
        property.imageUrl!,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _generatedArt(),
      );
    }

    return _generatedArt();
  }

  Widget _generatedArt() {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [property.colors[0], property.colors[2], property.colors[1]],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 20,
            top: 18,
            child: Text(
              'ROOMIFY',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 3,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: height * 0.42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: Text(
              property.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FilterGroup extends StatelessWidget {
  const FilterGroup({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: options.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final option = options[index];
              final active = option == selected;
              return ChoiceChip(
                label: Text(option),
                selected: active,
                onSelected: (_) => onSelected(option),
                selectedColor: roomifyNavy,
                labelStyle: TextStyle(
                  color: active ? Colors.white : roomifyNavy,
                  fontWeight: FontWeight.w700,
                ),
                backgroundColor: Colors.white,
                side: BorderSide(color: roomifyNavy.withValues(alpha: 0.08)),
              );
            },
          ),
        ),
      ],
    );
  }
}

class InfoTag extends StatelessWidget {
  const InfoTag({super.key, required this.label, this.dense = false});

  final String label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 12,
        vertical: dense ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: dense ? 1 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: dense
              ? roomifyNavy.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: dense ? roomifyNavy : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class SelectedPropertyCard extends StatelessWidget {
  const SelectedPropertyCard({super.key, required this.property});

  final PropertyItem property;

  @override
  Widget build(BuildContext context) {
    return NativeFormCard(
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 82,
              height: 82,
              child: PropertyArt(property: property, height: 82),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LabelText('Bất động sản đã chọn'),
                const SizedBox(height: 8),
                Text(
                  property.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  property.location,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          PriceChip(property.price),
        ],
      ),
    );
  }
}

class OwnerInfoCard extends StatelessWidget {
  const OwnerInfoCard({
    super.key,
    required this.property,
    required this.primaryLabel,
    required this.onPrimaryAction,
  });

  final PropertyItem property;
  final String primaryLabel;
  final VoidCallback onPrimaryAction;

  @override
  Widget build(BuildContext context) {
    return NativeFormCard(
      backgroundColor: const Color(0xFFFFFBF4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LabelText('Thông tin chủ nhà'),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: roomifyNavy,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Text(
                  property.ownerName.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      property.ownerName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      property.ownerRole,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              PriceChip(property.ownerPhone),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Gửi yêu cầu ngay để Roomify kết nối bạn với chủ nhà. Hoặc nhắn tin trực tiếp nếu bạn muốn trao đổi nhanh hơn.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onPrimaryAction,
            style: appPrimaryButtonStyle,
            child: Text(primaryLabel),
          ),
        ],
      ),
    );
  }
}

class AuthAccessCard extends StatelessWidget {
  const AuthAccessCard({
    super.key,
    required this.onLogin,
    required this.onRegister,
  });

  final VoidCallback onLogin;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return NativeFormCard(
      backgroundColor: const Color(0xFFFFFBF4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LabelText('Tài khoản Roomify'),
          const SizedBox(height: 10),
          Text(
            'Đăng nhập để lưu tin, đặt lịch xem nhà và nhận tư vấn nhanh hơn.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Nếu bạn chưa có tài khoản, tạo mới chỉ mất chưa tới một phút.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onLogin,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    side: BorderSide(
                      color: roomifyNavy.withValues(alpha: 0.12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text('Đăng nhập'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onRegister,
                  style: appPrimaryButtonStyle,
                  child: const Text('Tạo tài khoản'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key, required this.initialMode});

  final AuthMode initialMode;

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  late AuthMode _mode;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _loading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final AuthResult result;
    if (_mode == AuthMode.login) {
      result = await AuthService.instance.login(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } else {
      result = await AuthService.instance.register(
        name: _nameController.text,
        email: _emailController.text,
        password: _passwordController.text,
      );
    }

    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _loading = false;
        _errorMessage = result.errorMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        top: 32,
      ),
      child: NativeFormCard(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LabelText('Tài khoản'),
              const SizedBox(height: 8),
              Text(
                _mode == AuthMode.login ? 'Đăng nhập' : 'Tạo tài khoản mới',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 16),
              SegmentedButton<AuthMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AuthMode.login,
                    label: Text('Đăng nhập'),
                  ),
                  ButtonSegment(
                    value: AuthMode.register,
                    label: Text('Đăng ký'),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) {
                  setState(() {
                    _mode = selection.first;
                    if (_mode == AuthMode.login) {
                      _confirmPasswordController.clear();
                    }
                  });
                },
              ),
              if (_mode == AuthMode.register) ...[
                const SizedBox(height: 16),
                AppTextField(
                  controller: _nameController,
                  label: 'Họ và tên',
                  hint: 'Nguyễn Văn A',
                  validator: (value) {
                    if (_mode == AuthMode.register &&
                        (value == null || value.trim().isEmpty)) {
                      return 'Vui lòng nhập họ và tên';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 16),
              AppTextField(
                controller: _emailController,
                label: 'Email',
                hint: 'ban@example.com',
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập email';
                  }
                  if (!value.contains('@')) {
                    return 'Email chưa hợp lệ';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _passwordController,
                label: 'Mật khẩu',
                hint: 'Ít nhất 6 ký tự',
                obscureText: _obscurePassword,
                enableSuggestions: false,
                autocorrect: false,
                suffixIcon: IconButton(
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                  icon: Icon(
                    _obscurePassword
                        ? CupertinoIcons.eye_slash
                        : CupertinoIcons.eye,
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng nhập mật khẩu';
                  }
                  if (value.trim().length < 6) {
                    return 'Mật khẩu cần ít nhất 6 ký tự';
                  }
                  return null;
                },
              ),
              if (_mode == AuthMode.register) ...[
                const SizedBox(height: 16),
                AppTextField(
                  controller: _confirmPasswordController,
                  label: 'Xác nhận mật khẩu',
                  hint: 'Nhập lại mật khẩu',
                  obscureText: _obscureConfirmPassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        _obscureConfirmPassword = !_obscureConfirmPassword;
                      });
                    },
                    icon: Icon(
                      _obscureConfirmPassword
                          ? CupertinoIcons.eye_slash
                          : CupertinoIcons.eye,
                    ),
                  ),
                  validator: (value) {
                    if (_mode != AuthMode.register) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng xác nhận mật khẩu';
                    }
                    if (value != _passwordController.text) {
                      return 'Mật khẩu xác nhận chưa khớp';
                    }
                    return null;
                  },
                ),
              ],
              const SizedBox(height: 18),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      color: Color(0xFFB00020),
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: appPrimaryButtonStyle,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _mode == AuthMode.login
                            ? 'Tiếp tục đăng nhập'
                            : 'Tạo tài khoản',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NativeFormCard extends StatelessWidget {
  const NativeFormCard({
    super.key,
    required this.child,
    this.backgroundColor = Colors.white,
  });

  final Widget child;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: roomifyNavy.withValues(alpha: 0.06),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.validator,
    this.keyboardType,
    this.maxLines = 1,
    this.obscureText = false,
    this.enableSuggestions = true,
    this.autocorrect = true,
    this.suffixIcon,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool obscureText;
  final bool enableSuggestions;
  final bool autocorrect;
  final Widget? suffixIcon;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          maxLines: obscureText ? 1 : maxLines,
          obscureText: obscureText,
          obscuringCharacter: '•',
          enableSuggestions: enableSuggestions,
          autocorrect: autocorrect,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: roomifyCream,
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          value: value,
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(item.toString()),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: roomifyCream,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return NativeFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LabelText('Roomify'),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return NativeFormCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LabelText(label),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class HotspotChip extends StatelessWidget {
  const HotspotChip({
    super.key,
    required this.label,
    this.top,
    this.left,
    this.right,
    this.bottom,
  });

  final String label;
  final double? top;
  final double? left;
  final double? right;
  final double? bottom;

  const HotspotChip.inline({super.key, required this.label})
      : top = null,
        left = null,
        right = null,
        bottom = null;

  @override
  Widget build(BuildContext context) {
    if (top == null && left == null && right == null && bottom == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class VrOverlayChip extends StatelessWidget {
  const VrOverlayChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanoramaError extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: roomifyNavy.withValues(alpha: 0.6),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.eye_slash_fill, color: Colors.white30, size: 48),
          SizedBox(height: 12),
          Text('Không tải được ảnh 360°',
              style: TextStyle(color: Colors.white38)),
        ],
      ),
    );
  }
}

class VrTag extends StatelessWidget {
  const VrTag(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: roomifyGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: roomifyGold.withValues(alpha: 0.22)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class InfoPill extends StatelessWidget {
  const InfoPill(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: roomifyGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: roomifyNavy,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class LabelText extends StatelessWidget {
  const LabelText(this.text, {super.key, this.color = roomifyGold});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.6,
      ),
    );
  }
}

final ButtonStyle appPrimaryButtonStyle = FilledButton.styleFrom(
  minimumSize: const Size.fromHeight(56),
  backgroundColor: roomifyNavy,
  foregroundColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
);

class PropertyItem {
  const PropertyItem({
    required this.id,
    required this.title,
    required this.location,
    required this.type,
    required this.price,
    required this.numericPrice,
    required this.bedrooms,
    required this.bathrooms,
    required this.area,
    required this.description,
    required this.vrCopy,
    required this.tags,
    required this.featured,
    required this.colors,
    required this.ownerName,
    required this.ownerRole,
    required this.ownerPhone,
    this.imageUrl,
    this.panoramaUrl,
    this.matterportUrl,
    this.ownerId,
  });

  final int id;
  final String title;
  final String location;
  final String type;
  final String price;
  final int numericPrice;
  final int bedrooms;
  final int bathrooms;
  final String area;
  final String description;
  final String vrCopy;
  final List<String> tags;
  final bool featured;
  final List<Color> colors;
  final String ownerName;
  final String ownerRole;
  final String ownerPhone;
  final String? imageUrl;
  final String? panoramaUrl;
  final String? matterportUrl;

  /// UID của chủ nhà (chỉ có ở tin đăng từ Firestore).
  final String? ownerId;

  String get district => location.split(',').first.trim();
}

const List<PropertyItem> mockProperties = [
  PropertyItem(
    id: 1,
    title: 'Căn hộ Skyline One',
    location: 'Thủ Đức, TP. Hồ Chí Minh',
    type: 'Căn hộ penthouse',
    price: '1,48 triệu USD',
    numericPrice: 1480000,
    bedrooms: 4,
    bathrooms: 3,
    area: '238 m²',
    description:
        'Căn penthouse trên cao với không gian sống phân lớp, tầm nhìn toàn cảnh và các khu lounge riêng dành cho nhịp sống đô thị cao cấp.',
    vrCopy:
        'Dạo qua phòng khách trần cao, so sánh các góc sáng ban ngày và xem trước sân thượng hướng skyline trong chế độ 360 sống động.',
    tags: ['Nổi bật', 'Có VR'],
    featured: true,
    colors: [Color(0xFF1F3D63), roomifyGold, Color(0xFF10213E)],
    ownerName: 'Ngọc Trâm',
    ownerRole: 'Chủ nhà xác thực',
    ownerPhone: '0908 221 118',
    imageUrl: 'https://picsum.photos/seed/roomify-penthouse/1200/800',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/cayley_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=bVZzGXzms8Z',
  ),
  PropertyItem(
    id: 2,
    title: 'Loft Azure Heights',
    location: 'Quận 2, TP. Hồ Chí Minh',
    type: 'Căn hộ',
    price: '820 nghìn USD',
    numericPrice: 820000,
    bedrooms: 2,
    bathrooms: 2,
    area: '126 m²',
    description:
        'Căn loft tối giản mềm mại với hệ tủ cao cấp, bếp mở rộng rãi và góc làm việc linh hoạt dành cho nhịp sống hiện đại.',
    vrCopy:
        'Dùng lớp VR để kiểm tra luồng di chuyển, kho lưu trữ âm tường và độ phù hợp của nội thất trước khi liên hệ tư vấn viên.',
    tags: ['Mới', 'Vào ở nhanh'],
    featured: true,
    colors: [Color(0xFF30557E), roomifyGold, Color(0xFFEFF4F8)],
    ownerName: 'Minh Khang',
    ownerRole: 'Môi giới đại diện',
    ownerPhone: '0933 715 226',
    imageUrl: 'https://picsum.photos/seed/roomify-loft/1200/800',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/kiara_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=doiCgKgUuRV',
  ),
  PropertyItem(
    id: 3,
    title: 'Maison Ven Sông',
    location: 'Quận 7, TP. Hồ Chí Minh',
    type: 'Nhà phố',
    price: '1,12 triệu USD',
    numericPrice: 1120000,
    bedrooms: 3,
    bathrooms: 3,
    area: '194 m²',
    description:
        'Nhà phố tinh tế cân bằng giữa sự thoải mái cho gia đình và không gian tiếp khách, hoàn thiện bằng vật liệu ấm và hệ kính nhìn ra vườn.',
    vrCopy:
        'Chuyển sang chế độ 360 để đánh giá sự liên kết trong ngoài nhà và cách tầng sinh hoạt mở ra sân hiên ven sông.',
    tags: ['Gia đình', 'Ven sông'],
    featured: true,
    colors: [Color(0xFF26425D), Color(0xFF9FC7DB), roomifyGold],
    ownerName: 'Thu Hà',
    ownerRole: 'Chủ nhà',
    ownerPhone: '0977 445 820',
    imageUrl: 'https://picsum.photos/seed/roomify-townhouse/1200/800',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lebombo.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=WMo88QtrD3A',
  ),
  PropertyItem(
    id: 4,
    title: 'Biệt thự Goldline',
    location: 'Thảo Điền, TP. Hồ Chí Minh',
    type: 'Biệt thự',
    price: '2,35 triệu USD',
    numericPrice: 2350000,
    bedrooms: 5,
    bathrooms: 4,
    area: '412 m²',
    description:
        'Biệt thự tạo dấu ấn với nội thất điêu khắc, hồ bơi riêng và hoàn thiện tiêu chuẩn nghỉ dưỡng dành cho nhóm khách hàng cao cấp.',
    vrCopy:
        'Làm nổi bật tour biệt thự khi thuyết trình bằng cách đi xuyên suốt khu giải trí, chăm sóc sức khỏe và hồ bơi trong một mạch liền lạc.',
    tags: ['Cao cấp', 'Biểu tượng'],
    featured: false,
    colors: [Color(0xFF0F2745), roomifyGold, Color(0xFFF7EDD2)],
    ownerName: 'Hoàng Nam',
    ownerRole: 'Môi giới cao cấp',
    ownerPhone: '0912 664 118',
    imageUrl: 'https://picsum.photos/seed/roomify-villa/1200/800',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/glasshouse_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=rX9xYJkbR6X',
  ),
  PropertyItem(
    id: 5,
    title: 'Studio Harbor Crest',
    location: 'Bình Thạnh, TP. Hồ Chí Minh',
    type: 'Căn hộ',
    price: '460 nghìn USD',
    numericPrice: 460000,
    bedrooms: 1,
    bathrooms: 1,
    area: '68 m²',
    description:
        'Studio cao cấp nhỏ gọn dành cho người mua lần đầu, kết hợp mặt bằng hiệu quả với vật liệu tốt và tầm nhìn thành phố.',
    vrCopy:
        'Giúp người mua đánh giá nhanh khả năng lưu trữ, độ thoáng và tầm nhìn thông qua trải nghiệm VR ưu tiên cho quyết định nhanh.',
    tags: ['Khởi đầu', 'Đầu tư'],
    featured: false,
    colors: [Color(0xFF183455), roomifyGold, Color(0xFFDAE6F5)],
    ownerName: 'Anh Duy',
    ownerRole: 'Chủ đầu tư thứ cấp',
    ownerPhone: '0981 202 441',
    imageUrl: 'https://picsum.photos/seed/roomify-studio/1200/800',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lythwood_room.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=tBUbpx9R2xC',
  ),

  // ── 18 mock properties từ JSON ──────────────────────────────────
  PropertyItem(
    id: 6,
    title: 'Căn hộ Lumiere Riverside',
    location: 'Thủ Đức, TP.HCM',
    type: 'Căn hộ',
    price: '12 triệu/tháng',
    numericPrice: 12000000,
    bedrooms: 2,
    bathrooms: 2,
    area: '68 m²',
    description:
        'Căn hộ hiện đại dành cho người đi làm bận rộn, gần tuyến giao thông chính, nội thất tối giản và không gian sống thoáng.',
    vrCopy:
        'Khám phá không gian sống hiện đại với ban công rộng và tầm nhìn ven sông qua chế độ tour 360° sống động.',
    tags: ['Có VR', 'Nội thất đầy đủ', 'Phù hợp thuê ở'],
    featured: true,
    colors: [Color(0xFF1F3D63), roomifyGold, Color(0xFF10213E)],
    ownerName: 'Lan Phương',
    ownerRole: 'Chủ nhà xác thực',
    ownerPhone: '0909 123 456',
    imageUrl:
        'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/cayley_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=bVZzGXzms8Z',
  ),
  PropertyItem(
    id: 7,
    title: 'Nhà phố The Urban Nest',
    location: 'Nam Từ Liêm, Hà Nội',
    type: 'Nhà phố',
    price: '4,6 tỷ',
    numericPrice: 4600000000,
    bedrooms: 3,
    bathrooms: 3,
    area: '126 m²',
    description:
        'Nhà phố phù hợp gia đình trẻ hoặc người mua ở lâu dài, thiết kế hiện đại, nhiều ánh sáng và dễ quan sát qua tour VR.',
    vrCopy:
        'Trải nghiệm tour VR để thấy rõ luồng di chuyển, phòng bếp rộng và không gian gia đình trong một mạch liền lạc.',
    tags: ['Có VR', 'Phù hợp mua ở', 'Nhà phố hiện đại'],
    featured: true,
    colors: [Color(0xFF26425D), Color(0xFF9FC7DB), roomifyGold],
    ownerName: 'Tuấn Anh',
    ownerRole: 'Môi giới đại diện',
    ownerPhone: '0934 567 891',
    imageUrl:
        'https://images.unsplash.com/photo-1600585154526-990dced4db0d?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lebombo.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=doiCgKgUuRV',
  ),
  PropertyItem(
    id: 8,
    title: 'Studio Minimal Coast',
    location: 'Sơn Trà, Đà Nẵng',
    type: 'Studio',
    price: '7,5 triệu/tháng',
    numericPrice: 7500000,
    bedrooms: 1,
    bathrooms: 1,
    area: '38 m²',
    description:
        'Studio nhỏ gọn, tiện nghi, phù hợp người sống một mình hoặc làm việc từ xa. Thiết kế tối giản và gần biển.',
    vrCopy:
        'Cảm nhận không gian sống nhỏ gọn, tối giản với vị trí gần biển qua trải nghiệm VR 360° trực tuyến.',
    tags: ['Có VR', 'Giá tốt', 'Phù hợp người độc thân'],
    featured: false,
    colors: [Color(0xFF183455), roomifyGold, Color(0xFFDAE6F5)],
    ownerName: 'Khánh Linh',
    ownerRole: 'Chủ nhà',
    ownerPhone: '0978 234 567',
    imageUrl:
        'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lythwood_room.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=WMo88QtrD3A',
  ),
  PropertyItem(
    id: 9,
    title: 'Căn hộ Green Living Hub',
    location: 'Quận 7, TP.HCM',
    type: 'Căn hộ',
    price: '15 triệu/tháng',
    numericPrice: 15000000,
    bedrooms: 2,
    bathrooms: 2,
    area: '72 m²',
    description:
        'Không gian sống xanh, gần trung tâm thương mại, phù hợp với người làm văn phòng muốn tìm nơi ở tiện nghi.',
    vrCopy:
        'Dạo qua khu vui chơi xanh, hành lang thoáng và nội thất căn hộ qua chế độ VR trực quan trước khi tham quan thực tế.',
    tags: ['Không gian xanh', 'Căn hộ tiện nghi', 'Gần trung tâm'],
    featured: false,
    colors: [Color(0xFF1F3D63), roomifyGold, Color(0xFF10213E)],
    ownerName: 'Minh Hải',
    ownerRole: 'Chủ đầu tư thứ cấp',
    ownerPhone: '0912 345 678',
    imageUrl:
        'https://images.unsplash.com/photo-1494526585095-c41746248156?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/kiara_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=rX9xYJkbR6X',
  ),
  PropertyItem(
    id: 10,
    title: 'Nhà phố Golden Lane',
    location: 'Cầu Giấy, Hà Nội',
    type: 'Nhà phố',
    price: '5,8 tỷ',
    numericPrice: 5800000000,
    bedrooms: 4,
    bathrooms: 3,
    area: '140 m²',
    description:
        'Mặt tiền đẹp, khu dân cư đông đúc, phù hợp người mua nhà kết hợp ở và kinh doanh nhỏ.',
    vrCopy:
        'Tour VR giúp bạn đánh giá mặt tiền rộng và thiết kế mở bên trong trước khi đến xem thực tế.',
    tags: ['Mua ở lâu dài', 'Vị trí đẹp', 'Mặt tiền lớn'],
    featured: false,
    colors: [Color(0xFF26425D), Color(0xFF9FC7DB), roomifyGold],
    ownerName: 'Quỳnh Anh',
    ownerRole: 'Chủ nhà xác thực',
    ownerPhone: '0965 432 109',
    imageUrl:
        'https://images.unsplash.com/photo-1484154218962-a197022b5858?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/glasshouse_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=tBUbpx9R2xC',
  ),
  PropertyItem(
    id: 11,
    title: 'Studio Smart Compact',
    location: 'Bình Thạnh, TP.HCM',
    type: 'Studio',
    price: '6,8 triệu/tháng',
    numericPrice: 6800000,
    bedrooms: 1,
    bathrooms: 1,
    area: '32 m²',
    description:
        'Studio gọn gàng, phù hợp sinh hoạt cá nhân, tối ưu không gian và vị trí gần khu văn phòng.',
    vrCopy:
        'Xem xét tối ưu không gian sống và tất cả tiện nghi căn studio qua VR trước khi đưa ra quyết định.',
    tags: ['Giá tốt', 'Gọn gàng', 'Ở một mình'],
    featured: true,
    colors: [Color(0xFF183455), roomifyGold, Color(0xFFDAE6F5)],
    ownerName: 'Bảo Châu',
    ownerRole: 'Môi giới đại diện',
    ownerPhone: '0987 654 321',
    imageUrl:
        'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/kiara_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=i81gEraWpeJ',
  ),
  PropertyItem(
    id: 12,
    title: 'Căn hộ Sky Garden Residence',
    location: 'Quận 2, TP.HCM',
    type: 'Căn hộ',
    price: '13,5 triệu/tháng',
    numericPrice: 13500000,
    bedrooms: 2,
    bathrooms: 2,
    area: '75 m²',
    description:
        'Căn hộ hiện đại với không gian sáng, phù hợp cho gia đình trẻ hoặc người đi làm muốn sống gần trung tâm.',
    vrCopy:
        'Khám phá hồ bơi, gym và không gian căn hộ hiện đại qua tour VR360 đầy đủ trước khi liên hệ chủ nhà.',
    tags: ['Có VR', 'View đẹp', 'Căn hộ cao cấp'],
    featured: true,
    colors: [Color(0xFF1F3D63), roomifyGold, Color(0xFF10213E)],
    ownerName: 'Thanh Hằng',
    ownerRole: 'Chủ nhà xác thực',
    ownerPhone: '0908 765 432',
    imageUrl:
        'https://images.unsplash.com/photo-1724582586529-62622e50c0b3?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/cayley_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=kmzrbJKkgB7',
  ),
  PropertyItem(
    id: 13,
    title: 'Nhà phố Riverside Corner',
    location: 'Quận 9, TP.HCM',
    type: 'Nhà phố',
    price: '5,2 tỷ',
    numericPrice: 5200000000,
    bedrooms: 4,
    bathrooms: 3,
    area: '148 m²',
    description:
        'Nhà phố góc hai mặt tiền, thoáng mát, phù hợp để ở lâu dài hoặc kết hợp kinh doanh nhỏ.',
    vrCopy:
        'Trải nghiệm tour VR để thấy rõ hai mặt tiền và toàn bộ không gian rộng rãi của ngôi nhà phố.',
    tags: ['Có VR', 'Nhà phố rộng', 'Hai mặt tiền'],
    featured: false,
    colors: [Color(0xFF26425D), Color(0xFF9FC7DB), roomifyGold],
    ownerName: 'Văn Đức',
    ownerRole: 'Môi giới đại diện',
    ownerPhone: '0945 678 901',
    imageUrl:
        'https://images.unsplash.com/photo-1769805446592-35a4ed882bc4?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lebombo.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=D8GJH72oZpx',
  ),
  PropertyItem(
    id: 14,
    title: 'Studio City View',
    location: 'Ba Đình, Hà Nội',
    type: 'Studio',
    price: '8,2 triệu/tháng',
    numericPrice: 8200000,
    bedrooms: 1,
    bathrooms: 1,
    area: '40 m²',
    description:
        'Studio tối giản nhưng đầy đủ tiện nghi, phù hợp sinh viên, người độc thân hoặc người làm việc tự do.',
    vrCopy:
        'Cảm nhận studio tiện nghi với nội thất đầy đủ và tầm nhìn thành phố qua trải nghiệm VR 360°.',
    tags: ['Có VR', 'Studio đẹp', 'Tiện nghi'],
    featured: true,
    colors: [Color(0xFF183455), roomifyGold, Color(0xFFDAE6F5)],
    ownerName: 'Ngọc Mai',
    ownerRole: 'Chủ nhà',
    ownerPhone: '0976 543 210',
    imageUrl:
        'https://images.unsplash.com/photo-1759691555010-7f3f8674d2f2?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lythwood_room.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=H8g1Yj1rrGW',
  ),
  PropertyItem(
    id: 15,
    title: 'Căn hộ Lotus Central',
    location: 'Thanh Xuân, Hà Nội',
    type: 'Căn hộ',
    price: '14 triệu/tháng',
    numericPrice: 14000000,
    bedrooms: 3,
    bathrooms: 2,
    area: '84 m²',
    description:
        'Căn hộ gia đình với thiết kế ấm cúng, gần trường học, trung tâm thương mại và khu văn phòng lớn.',
    vrCopy:
        'Khám phá 3 phòng ngủ, không gian gia đình và các tiện ích xung quanh qua tour VR liền mạch, thuận tiện.',
    tags: ['Có VR', 'Phù hợp gia đình', 'Gần trung tâm'],
    featured: false,
    colors: [Color(0xFF1F3D63), roomifyGold, Color(0xFF10213E)],
    ownerName: 'Hùng Khoa',
    ownerRole: 'Chủ đầu tư thứ cấp',
    ownerPhone: '0933 456 789',
    imageUrl:
        'https://images.unsplash.com/photo-1738168269267-241954441823?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/kiara_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=NChqGkBbeVo',
  ),
  PropertyItem(
    id: 16,
    title: 'Nhà phố Maple Home',
    location: 'Hải Châu, Đà Nẵng',
    type: 'Nhà phố',
    price: '4,2 tỷ',
    numericPrice: 4200000000,
    bedrooms: 3,
    bathrooms: 3,
    area: '132 m²',
    description:
        'Nhà phố phong cách hiện đại, phù hợp gia đình cần không gian sống rộng rãi gần trung tâm thành phố.',
    vrCopy:
        'Dạo qua sân trước, phòng khách và các phòng của ngôi nhà phố hiện đại qua chế độ tour 360°.',
    tags: ['Có VR', 'Nhà phố đẹp', 'Ở lâu dài'],
    featured: true,
    colors: [Color(0xFF26425D), Color(0xFF9FC7DB), roomifyGold],
    ownerName: 'Thu Phương',
    ownerRole: 'Chủ nhà xác thực',
    ownerPhone: '0901 234 567',
    imageUrl:
        'https://images.unsplash.com/photo-1605276374104-dee2a0ed3cd6?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/glasshouse_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=VsxrdxtQPjo',
  ),
  PropertyItem(
    id: 17,
    title: 'Studio Ocean Breeze',
    location: 'Ngũ Hành Sơn, Đà Nẵng',
    type: 'Studio',
    price: '7,9 triệu/tháng',
    numericPrice: 7900000,
    bedrooms: 1,
    bathrooms: 1,
    area: '36 m²',
    description:
        'Studio gần biển, phong cách trẻ trung, thích hợp cho người độc thân hoặc các bạn làm việc từ xa.',
    vrCopy:
        'Cảm nhận studio trẻ trung gần biển với ban công nhỏ và nội thất mới qua trải nghiệm VR 360° đầy đủ.',
    tags: ['Có VR', 'Gần biển', 'Studio trẻ trung'],
    featured: false,
    colors: [Color(0xFF183455), roomifyGold, Color(0xFFDAE6F5)],
    ownerName: 'Thảo Vy',
    ownerRole: 'Chủ nhà',
    ownerPhone: '0977 890 123',
    imageUrl:
        'https://images.unsplash.com/photo-1749878064335-117141e3a1aa?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/kiara_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=7Sa4qvF9qxz',
  ),
  PropertyItem(
    id: 18,
    title: 'Căn hộ Sunrise Premium',
    location: 'Quận 4, TP.HCM',
    type: 'Căn hộ',
    price: '16 triệu/tháng',
    numericPrice: 16000000,
    bedrooms: 2,
    bathrooms: 2,
    area: '78 m²',
    description:
        'Căn hộ cao cấp với thiết kế sang trọng, phù hợp cho người thuê cần không gian sống tiện nghi gần trung tâm.',
    vrCopy:
        'Tour VR giúp bạn trải nghiệm view sông, hồ bơi tràn và nội thất cao cấp trước khi liên hệ tư vấn viên.',
    tags: ['Có VR', 'Cao cấp', 'View đẹp'],
    featured: true,
    colors: [Color(0xFF1F3D63), roomifyGold, Color(0xFF10213E)],
    ownerName: 'Đức Minh',
    ownerRole: 'Môi giới cao cấp',
    ownerPhone: '0911 222 333',
    imageUrl:
        'https://images.unsplash.com/photo-1669317139155-912572c38362?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/cayley_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=aNiCYQR1oh4',
  ),
  PropertyItem(
    id: 19,
    title: 'Nhà phố Heritage Square',
    location: 'Hoàng Mai, Hà Nội',
    type: 'Nhà phố',
    price: '6,3 tỷ',
    numericPrice: 6300000000,
    bedrooms: 5,
    bathrooms: 4,
    area: '165 m²',
    description:
        'Nhà phố rộng rãi, thiết kế sang trọng, phù hợp gia đình đông người hoặc đầu tư giữ tài sản lâu dài.',
    vrCopy:
        'Dạo qua 5 phòng ngủ, gara riêng và không gian sang trọng của nhà phố qua chế độ tour 360° toàn cảnh.',
    tags: ['Có VR', 'Rộng rãi', 'Nhà phố cao cấp'],
    featured: true,
    colors: [Color(0xFF26425D), Color(0xFF9FC7DB), roomifyGold],
    ownerName: 'Kim Ngân',
    ownerRole: 'Chủ nhà xác thực',
    ownerPhone: '0956 789 012',
    imageUrl:
        'https://images.unsplash.com/photo-1748063578185-3d68121b11ff?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lebombo.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=LhbwwoBWJ8x',
  ),
  PropertyItem(
    id: 20,
    title: 'Căn hộ Imperial River View',
    location: 'Vỹ Dạ, Huế',
    type: 'Căn hộ',
    price: '11 triệu/tháng',
    numericPrice: 11000000,
    bedrooms: 2,
    bathrooms: 2,
    area: '67 m²',
    description:
        'Căn hộ hiện đại gần sông, không gian sáng và yên tĩnh, phù hợp cho gia đình nhỏ hoặc người đi làm cần nơi ở tiện nghi.',
    vrCopy:
        'Khám phá căn hộ view sông yên tĩnh với ban công rộng và ánh sáng tự nhiên qua trải nghiệm tour 360° sống động.',
    tags: ['Có VR', 'View đẹp', 'Căn hộ tiện nghi'],
    featured: true,
    colors: [Color(0xFF1F3D63), roomifyGold, Color(0xFF10213E)],
    ownerName: 'Xuân Hà',
    ownerRole: 'Chủ nhà',
    ownerPhone: '0944 321 098',
    imageUrl:
        'https://images.unsplash.com/photo-1499955085172-a104c9463ece?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lythwood_room.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=vkRHUcj3Gte',
  ),
  PropertyItem(
    id: 21,
    title: 'Nhà phố Cố Đô Residence',
    location: 'An Cựu, Huế',
    type: 'Nhà phố',
    price: '4,3 tỷ',
    numericPrice: 4300000000,
    bedrooms: 3,
    bathrooms: 3,
    area: '128 m²',
    description:
        'Nhà phố thiết kế hiện đại, khu dân cư yên tĩnh, phù hợp gia đình muốn ở lâu dài tại khu vực trung tâm Huế.',
    vrCopy:
        'Tour VR giúp bạn thấy rõ phòng khách lớn và không gian sống yên tĩnh tại khu vực trung tâm thành phố Huế.',
    tags: ['Có VR', 'Nhà phố đẹp', 'Ở lâu dài'],
    featured: false,
    colors: [Color(0xFF26425D), Color(0xFF9FC7DB), roomifyGold],
    ownerName: 'Bích Trâm',
    ownerRole: 'Môi giới đại diện',
    ownerPhone: '0966 543 210',
    imageUrl:
        'https://images.unsplash.com/photo-1706164971309-fb4785fe6ceb?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/glasshouse_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=GyWHbeV3thf',
  ),
  PropertyItem(
    id: 22,
    title: 'Studio Huế Minimal',
    location: 'Thuận Hòa, Huế',
    type: 'Studio',
    price: '6,9 triệu/tháng',
    numericPrice: 6900000,
    bedrooms: 1,
    bathrooms: 1,
    area: '34 m²',
    description:
        'Studio nhỏ gọn, tối ưu không gian, phù hợp sinh viên, người độc thân hoặc người làm việc từ xa.',
    vrCopy:
        'Xem xét toàn bộ không gian sống thông minh, tối ưu của studio qua trải nghiệm VR 360° trực quan.',
    tags: ['Có VR', 'Giá tốt', 'Studio đẹp'],
    featured: true,
    colors: [Color(0xFF183455), roomifyGold, Color(0xFFDAE6F5)],
    ownerName: 'Quang Hiếu',
    ownerRole: 'Chủ nhà',
    ownerPhone: '0989 123 456',
    imageUrl:
        'https://images.unsplash.com/photo-1748679767437-00b5c0327b1a?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lythwood_room.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=4vuk5Fufe9p',
  ),
  PropertyItem(
    id: 23,
    title: 'Căn hộ Perfume River Home',
    location: 'Phú Hội, Huế',
    type: 'Căn hộ',
    price: '13 triệu/tháng',
    numericPrice: 13000000,
    bedrooms: 2,
    bathrooms: 2,
    area: '74 m²',
    description:
        'Căn hộ phù hợp gia đình trẻ, thiết kế ấm cúng, gần khu trung tâm và thuận tiện di chuyển trong thành phố.',
    vrCopy:
        'Khám phá căn hộ ấm cúng gần sông Hương với 2 phòng ngủ và đầy đủ tiện nghi qua tour VR 360° liền mạch.',
    tags: ['Có VR', 'Phù hợp gia đình', 'Tiện nghi'],
    featured: false,
    colors: [Color(0xFF1F3D63), roomifyGold, Color(0xFF10213E)],
    ownerName: 'Diệu Linh',
    ownerRole: 'Chủ nhà xác thực',
    ownerPhone: '0922 345 678',
    imageUrl:
        'https://images.unsplash.com/photo-1560185009-5bf9f2849488?auto=format&fit=crop&w=1200&q=80',
    panoramaUrl:
        'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/cayley_interior.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=oBTCWr5UnbE',
  ),
];

const String demoPanoramaUrl =
    'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/lebombo.jpg';

class MatterportDemo {
  const MatterportDemo({
    required this.name,
    required this.label,
    required this.url,
  });

  final String name;
  final String label;
  final String url;
}

const List<MatterportDemo> matterportDemos = [
  MatterportDemo(
    name: 'Matterport Demo 1',
    label: 'Tour tham khảo cho căn penthouse',
    url: 'https://my.matterport.com/show/?m=bVZzGXzms8Z',
  ),
  MatterportDemo(
    name: 'Matterport Demo 2',
    label: 'Tour tham khảo cho loft/can ho',
    url: 'https://my.matterport.com/show/?m=doiCgKgUuRV',
  ),
  MatterportDemo(
    name: 'Matterport Demo 3',
    label: 'Tour tham khảo cho nha pho',
    url: 'https://my.matterport.com/show/?m=WMo88QtrD3A',
  ),
  MatterportDemo(
    name: 'Matterport Demo 4',
    label: 'Tour tham khảo cho biet thu',
    url: 'https://my.matterport.com/show/?m=rX9xYJkbR6X',
  ),
  MatterportDemo(
    name: 'Matterport Demo 5',
    label: 'Tour tham khảo cho studio/can nho',
    url: 'https://my.matterport.com/show/?m=tBUbpx9R2xC',
  ),
  MatterportDemo(
    name: 'Matterport Demo 6',
    label: 'Tour bo sung de test dieu huong tang/phong',
    url: 'https://my.matterport.com/show/?m=i81gEraWpeJ',
  ),
];
