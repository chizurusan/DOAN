import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:panorama/panorama.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'src/firebase_options.dart';
import 'src/auth_service.dart';
import 'src/firestore_service.dart';
import 'src/matterport_embed.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const RoomifyApp());
}

const Color roomifyNavy = Color(0xFF0A1931);
const Color roomifyGold = Color(0xFFD2A941);
const Color roomifyCream = Color(0xFFF7F2E8);
const Color roomifyMist = Color(0xFFE9EFF7);
const Color roomifyText = Color(0xFF13233D);
const Color roomifyMuted = Color(0xFF68758B);

enum AppTab { home, listings, connect, post }

enum ConnectMode { book, contact }

enum DetailAction { book, contact }

enum AuthMode { login, register }

enum MembershipTier { monthly, quarterly, yearly }

enum PaymentMethod { qr, card }

typedef AuthFlow = Future<bool> Function(AuthMode mode);
typedef MembershipFlow = Future<bool> Function(
  MembershipTier tier,
  PaymentMethod method,
);

class MembershipCheckoutResult {
  const MembershipCheckoutResult({
    required this.tier,
    required this.method,
  });

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
    // Lắng nghe trạng thái đăng nhập từ Firebase.
    AuthService.instance.authStateChanges.listen((user) async {
      if (!mounted) return;
      if (user != null) {
        // Tạo profile nếu chưa có (đăng nhập lần đầu).
        await FirestoreService.instance.upsertUserProfile(user);
        // Đọc membership từ Firestore.
        final profile =
            await FirestoreService.instance.getUserProfile(user.uid);
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
    if (uid != null) {
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
          bodyLarge: TextStyle(
            color: roomifyText,
            fontSize: 15,
            height: 1.55,
          ),
          bodyMedium: TextStyle(
            color: roomifyMuted,
            fontSize: 14,
            height: 1.5,
          ),
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
  ConnectMode _connectMode = ConnectMode.book;
  PropertyItem _selectedProperty = mockProperties.first;
  final Set<int> _savedPropertyIds = <int>{};

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
      final user = AuthService.instance.currentUser;
      final name = user?.displayName ?? user?.email ?? 'bạn';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đang đăng nhập với tài khoản $name.')),
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

    final result = await Navigator.of(context).push<DetailAction>(
      MaterialPageRoute(
        builder: (_) => PropertyDetailPage(
          property: property,
          isSaved: _savedPropertyIds.contains(property.id),
          onToggleSaved: () => _toggleSaved(property),
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result == DetailAction.book && !widget.isAuthenticated) {
      final authenticated = await widget.onOpenAuth(AuthMode.login);
      if (!mounted || !authenticated) {
        return;
      }
    }

    setState(() {
      _currentTab = AppTab.connect;
      _connectMode =
          result == DetailAction.book ? ConnectMode.book : ConnectMode.contact;
    });
  }

  void _openVr(PropertyItem property) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VrTourPage(property: property),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        properties: mockProperties,
        onOpenProperty: _openProperty,
        onToggleSaved: _toggleSaved,
        savedPropertyIds: _savedPropertyIds,
      ),
      ConnectScreen(
        property: _selectedProperty,
        initialMode: _connectMode,
        isAuthenticated: widget.isAuthenticated,
        onOpenAuth: widget.onOpenAuth,
      ),
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
      body: IndexedStack(index: _currentTab.index, children: pages),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openVr(_selectedProperty),
        backgroundColor: roomifyGold,
        foregroundColor: roomifyNavy,
        icon: const Icon(CupertinoIcons.viewfinder_circle_fill),
        label: const Text('Xem VR'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        height: 78,
        selectedIndex: _currentTab.index,
        backgroundColor: roomifyNavy,
        indicatorColor: roomifyGold.withValues(alpha: 0.18),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        destinations: const [
          NavigationDestination(
            icon: Icon(CupertinoIcons.house, color: Colors.white70),
            selectedIcon: Icon(CupertinoIcons.house_fill, color: Colors.white),
            label: 'Trang chủ',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.square_grid_2x2, color: Colors.white70),
            selectedIcon:
                Icon(CupertinoIcons.square_grid_2x2_fill, color: Colors.white),
            label: 'Khám phá',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.chat_bubble_2, color: Colors.white70),
            selectedIcon:
                Icon(CupertinoIcons.chat_bubble_2_fill, color: Colors.white),
            label: 'Liên hệ',
          ),
          NavigationDestination(
            icon: Icon(CupertinoIcons.add_circled, color: Colors.white70),
            selectedIcon:
                Icon(CupertinoIcons.add_circled_solid, color: Colors.white),
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
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: Colors.white,
                      ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Khám phá nhà ở cao cấp từ xa, xem mức giá ngay lập tức và chuyển thẳng sang đặt lịch hoặc liên hệ tư vấn viên.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Colors.white70,
                      ),
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
                            LabelText(widget.isAuthenticated
                                ? 'Xin chào trở lại'
                                : 'Khám phá tự do'),
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
                            label: entry.key, count: entry.value);
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
                            isSaved:
                                widget.savedPropertyIds.contains(property.id),
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
      ...{for (final property in widget.properties) property.district}
    ];
    final types = [
      'Tất cả',
      ...{for (final property in widget.properties) property.type}
    ];
    const prices = [
      'Tất cả',
      'Dưới 700 nghìn USD',
      '700 nghìn - 1,2 triệu USD',
      'Trên 1,2 triệu USD'
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
              title: 'Danh sách bất động sản', subtitle: 'Khám phá'),
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
        schedule: _scheduleController.text.isEmpty
            ? null
            : _scheduleController.text,
        notes:
            _notesController.text.isEmpty ? null : _notesController.text,
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
              title: 'Đặt lịch và liên hệ', subtitle: 'Thao tác'),
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
                  const SizedBox(height: 18),
                  SegmentedButton<ConnectMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: ConnectMode.book,
                          label: Text('Đặt lịch xem nhà')),
                      ButtonSegment(
                          value: ConnectMode.contact,
                          label: Text('Liên hệ tư vấn')),
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
                            child: Text(_mode == ConnectMode.book
                                ? 'Gửi yêu cầu xem nhà'
                                : 'Gửi yêu cầu tư vấn'),
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
  final _imageController = TextEditingController();
  final _vrController = TextEditingController();
  String _type = 'Căn hộ';
  PropertyItem? _draft;

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _locationController.dispose();
    _imageController.dispose();
    _vrController.dispose();
    super.dispose();
  }

  void _createPreview() {
    final postingPrice = widget.membershipTier == null ? '50.000đ' : '0đ';

    final title = _titleController.text.isEmpty
        ? 'Tin đăng nháp'
        : _titleController.text;
    final location = _locationController.text.isEmpty
        ? 'Quận/Huyện, Thành phố'
        : _locationController.text;
    final price =
        _priceController.text.isEmpty ? postingPrice : _priceController.text;

    final draft = PropertyItem(
      id: 999,
      title: title,
      location: location,
      type: _type,
      price: price,
      numericPrice: 0,
      bedrooms: 3,
      bathrooms: 2,
      area: 'Bản xem trước',
      description:
          'Bản nháp dành cho chủ nhà, sẵn sàng xuất bản với mức giá, hình ảnh và liên kết tham quan 360.',
      vrCopy: _vrController.text.isEmpty
          ? 'Hãy gắn liên kết 360 để tin đăng nổi bật hơn trên Roomify.'
          : 'Bản nháp này đã có liên kết tham quan 360 để khách có thể xem nhà từ xa.',
      tags: const ['Nháp', 'Chủ nhà'],
      featured: false,
      colors: const [Color(0xFF19365D), roomifyGold, Color(0xFFE7EEF8)],
      ownerName: AuthService.instance.currentUser?.displayName ?? 'Chủ nhà',
      ownerRole: 'Người đăng tin',
      ownerPhone: '0900 000 999',
      imageUrl: _imageController.text.isEmpty ? null : _imageController.text,
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
      FirestoreService.instance.postProperty(
        userId: uid,
        title: title,
        price: price,
        location: location,
        type: _type,
        imageUrl:
            _imageController.text.isEmpty ? null : _imageController.text,
        vrUrl: _vrController.text.isEmpty ? null : _vrController.text,
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
              title: 'Đăng bất động sản của bạn', subtitle: 'Chủ nhà'),
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
                        AppDropdownField<String>(
                          label: 'Loại hình bất động sản',
                          value: _type,
                          items: const [
                            'Căn hộ',
                            'Căn hộ penthouse',
                            'Nhà phố',
                            'Biệt thự'
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _type = value;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _imageController,
                          label: 'Liên kết hình ảnh',
                          hint: 'https://example.com/image.jpg',
                        ),
                        const SizedBox(height: 14),
                        AppTextField(
                          controller: _vrController,
                          label: 'Liên kết tham quan 360',
                          hint: 'https://example.com/360-tour',
                        ),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _createPreview,
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            style: TextStyle(
              color: roomifyText,
              fontSize: 15,
              height: 1.5,
            ),
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
              onPressed: onManageMembership, child: const Text('Xem gói')),
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

    Navigator.of(context).pop(
      MembershipCheckoutResult(tier: plan.tier, method: method),
    );
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
  const MembershipPaymentSheet({
    super.key,
    required this.plan,
  });

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
                                if (!RegExp(r'^(0[1-9]|1[0-2])/[0-9]{2}$')
                                    .hasMatch(text)) {
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
  const QrPaymentPreview({
    super.key,
    required this.plan,
  });

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
                  border:
                      Border.all(color: roomifyNavy.withValues(alpha: 0.08)),
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
  });

  final PropertyItem property;
  final bool isSaved;
  final VoidCallback onToggleSaved;

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
                onPressed: () =>
                    Navigator.of(context).pop(DetailAction.contact),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  side: const BorderSide(color: Color(0x1F0A1931)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text('Liên hệ tư vấn'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(DetailAction.book),
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
                            Text(property.title,
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            const SizedBox(height: 8),
                            Text(property.location,
                                style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      PriceChip(property.price),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(property.description,
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                          child: MetricTile(
                              label: 'Phòng ngủ',
                              value: '${property.bedrooms}')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: MetricTile(
                              label: 'Phòng tắm',
                              value: '${property.bathrooms}')),
                      const SizedBox(width: 12),
                      Expanded(
                          child: MetricTile(
                              label: 'Diện tích', value: property.area)),
                    ],
                  ),
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
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          property.vrCopy,
                          style: const TextStyle(
                              color: Colors.white70, height: 1.6),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      VrTourPage(property: property)),
                            );
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: roomifyGold,
                            foregroundColor: roomifyNavy,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                          ),
                          child: const Text('Mở tour 360/VR'),
                        ),
                      ],
                    ),
                  ),
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
                          child: const Icon(CupertinoIcons.location_solid,
                              color: roomifyGold),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const LabelText('Vị trí'),
                              const SizedBox(height: 8),
                              Text(property.location,
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
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
                    onPrimaryAction: () => Navigator.of(context).pop(
                      DetailAction.contact,
                    ),
                  ),
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
    return Scaffold(
      backgroundColor: roomifyNavy,
      appBar: AppBar(
        backgroundColor: roomifyNavy,
        foregroundColor: Colors.white,
        title: const Text('Tour VR 360'),
      ),
      body: SafeArea(
        child: Padding(
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
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: Panorama(
                          animSpeed: 0.1,
                          sensitivity: 1.3,
                          minZoom: 1,
                          maxZoom: 5,
                          sensorControl: kIsWeb
                              ? SensorControl.None
                              : SensorControl.Orientation,
                          child: Image.network(
                            property.panoramaUrl ??
                                property.imageUrl ??
                                demoPanoramaUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Image.network(
                                demoPanoramaUrl,
                                fit: BoxFit.cover,
                              );
                            },
                          ),
                        ),
                      ),
                      Positioned(
                        top: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          children: const [
                            VrOverlayChip(
                              icon: CupertinoIcons.hand_draw,
                              label: 'Kéo để xoay',
                            ),
                            SizedBox(width: 10),
                            VrOverlayChip(
                              icon:
                                  CupertinoIcons.arrow_up_left_arrow_down_right,
                              label: 'Chụm để zoom',
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: const [
                            HotspotChip.inline(label: 'Bếp mở'),
                            HotspotChip.inline(label: 'Khu lounge'),
                            HotspotChip.inline(label: 'View ban công'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  VrTag('Di chuyển 360'),
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
              const SizedBox(height: 18),
              MatterportDemoList(
                currentUrl: property.matterportUrl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MatterportTourPage extends StatelessWidget {
  const MatterportTourPage({
    super.key,
    required this.title,
    required this.url,
  });

  final String title;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: roomifyNavy,
      appBar: AppBar(
        backgroundColor: roomifyNavy,
        foregroundColor: Colors.white,
        title: Text(title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const LabelText('Matterport Demo', color: roomifyGold),
              const SizedBox(height: 8),
              Text(
                matterportEmbedSupported
                    ? 'Bạn có thể dùng các điểm tương tác sẵn có của Matterport để di chuyển phòng, lên tầng và xem không gian như tour thật.'
                    : 'Bản embed Matterport hiện hỗ trợ trên web demo. Hãy chạy bằng Chrome để dùng tương tác đầy đủ.',
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
                    child: buildMatterportEmbed(url: url),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                        builder: (_) => MatterportTourPage(
                          title: demo.name,
                          url: demo.url,
                        ),
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
      actions: [
        ...trailing,
        const SizedBox(width: 20),
      ],
    );
  }
}

class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton(
      {super.key, required this.icon, required this.onPressed});

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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            'Xem trước bố cục, ánh sáng và vật liệu hoàn thiện với trải nghiệm VR được đặt ở vị trí trung tâm của sản phẩm.',
            style: Theme.of(context)
                .textTheme
                .bodyLarge
                ?.copyWith(color: Colors.white70),
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
                  borderRadius: BorderRadius.circular(18)),
            ),
            child: const Text('Mở tour 360'),
          ),
        ],
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(
      {super.key, required this.title, required this.trailing});

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
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(28)),
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
      icon: Icon(
        isSaved ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
      ),
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
                    Colors.transparent
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
                Text(property.title,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(property.location,
                    style: Theme.of(context).textTheme.bodyMedium),
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
            'Gửi yêu cầu ngay để Roomify kết nối bạn với chủ nhà hoặc người đại diện trong luồng demo hiện tại.',
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
                    side:
                        BorderSide(color: roomifyNavy.withValues(alpha: 0.12)),
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
                      value: AuthMode.login, label: Text('Đăng nhập')),
                  ButtonSegment(
                      value: AuthMode.register, label: Text('Đăng ký')),
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
              .map((item) => DropdownMenuItem<T>(
                  value: item, child: Text(item.toString())))
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
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
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
        child: Text(label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class VrOverlayChip extends StatelessWidget {
  const VrOverlayChip({
    super.key,
    required this.icon,
    required this.label,
  });

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
        style:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
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
            color: roomifyNavy, fontWeight: FontWeight.w800, fontSize: 12),
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
    panoramaUrl: 'https://pannellum.org/images/alma.jpg',
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
    panoramaUrl: 'https://pannellum.org/images/bma-1.jpg',
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
    panoramaUrl: 'https://pannellum.org/images/jfk.jpg',
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
    panoramaUrl: 'https://pannellum.org/images/cerro-toco-0.jpg',
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
    panoramaUrl: 'https://pannellum.org/images/bma-0.jpg',
    matterportUrl: 'https://my.matterport.com/show/?m=tBUbpx9R2xC',
  ),
];

const String demoPanoramaUrl = 'https://pannellum.org/images/alma.jpg';

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
