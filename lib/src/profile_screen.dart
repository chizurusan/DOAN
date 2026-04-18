import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'admin_screen.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'image_upload_service.dart';

const Color _navy = Color(0xFF0A1931);
const Color _gold = Color(0xFFD2A941);
const Color _cream = Color(0xFFFAF7F2);
const Color _mist = Color(0xFFEFF3F8);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onLogout,
    this.savedProperties = const [],
  });

  /// Gọi khi người dùng đăng xuất thành công.
  final VoidCallback onLogout;

  /// Danh sách BĐS đã lưu (dạng Map để tránh phụ thuộc vào PropertyItem).
  final List<Map<String, dynamic>> savedProperties;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final AppUser? _user;
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _uploadingAvatar = false;
  int _postedCount = 0;
  int _chatCount = 0;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _user = AuthService.instance.currentUser;
    _loadProfile();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = _user?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      FirestoreService.instance.getUserProfile(uid),
      FirestoreService.instance.getUserPostingsCount(uid),
      FirestoreService.instance.getUserConversationsCount(uid),
    ]);
    if (mounted)
      setState(() {
        _profile = results[0] as Map<String, dynamic>?;
        _postedCount = results[1] as int;
        _chatCount = results[2] as int;
        _loading = false;
      });
  }

  Future<void> _uploadAvatar() async {
    final file = await ImageUploadService.pickImage();
    if (file == null) return;
    final uid = _user?.uid;
    if (uid == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      final url = await ImageUploadService.uploadPropertyImage(file, uid);
      await FirestoreService.instance.updateAvatarUrl(uid, url);
      if (mounted) {
        setState(() {
          _profile = {...?_profile, 'avatar_url': url};
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tải ảnh thất bại: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _user?.displayName ?? '');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi tên hiển thị'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nhập tên mới'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Lưu')),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || !mounted) return;
    await AuthService.instance.updateDisplayName(newName);
    if (_user != null) {
      await FirestoreService.instance.upsertUserProfile(_user);
    }
    if (mounted) setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật tên.')),
      );
    }
  }

  Future<void> _editPhone() async {
    final controller =
        TextEditingController(text: _profile?['phone'] as String? ?? '');
    final newPhone = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cập nhật số điện thoại'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(hintText: 'VD: 0901 234 567'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Lưu')),
        ],
      ),
    );
    if (newPhone == null || !mounted) return;
    final uid = _user?.uid;
    if (uid == null) return;
    await FirestoreService.instance.updateUserPhone(uid, newPhone);
    if (mounted) {
      setState(() {
        _profile = {...?_profile, 'phone': newPhone};
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã cập nhật số điện thoại.')),
      );
    }
  }

  Future<void> _changePassword() async {
    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final cfCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PwdField(controller: curCtrl, label: 'Mật khẩu hiện tại'),
            const SizedBox(height: 10),
            _PwdField(controller: newCtrl, label: 'Mật khẩu mới'),
            const SizedBox(height: 10),
            _PwdField(controller: cfCtrl, label: 'Xác nhận mật khẩu mới'),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Đổi')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (newCtrl.text != cfCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mật khẩu xác nhận không khớp.')),
      );
      return;
    }
    final error = await AuthService.instance.changePassword(
      currentPassword: curCtrl.text,
      newPassword: newCtrl.text,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Đã đổi mật khẩu thành công.'),
      ),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất không?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Đăng xuất')),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService.instance.signOut();
    if (mounted) {
      Navigator.of(context).pop();
      widget.onLogout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _user?.displayName ?? _profile?['full_name'] ?? 'Người dùng';
    final email = _user?.email ?? '';
    final tier = _profile?['membership_tier'] as String?;
    final tierLabel = switch (tier) {
      'monthly' => 'Thành viên Tháng',
      'quarterly' => 'Thành viên Quý',
      'yearly' => 'Thành viên Năm',
      _ => 'Gói miễn phí',
    };
    final tierColor = tier != null ? _gold : Colors.black38;

    // Ngày đăng ký & hết hạn
    final startStr = _profile?['membership_start_date'] as String?;
    final expiryStr = _profile?['membership_expiry_date'] as String?;
    final startDate = startStr != null ? DateTime.tryParse(startStr)?.toLocal() : null;
    final expiryDate = expiryStr != null ? DateTime.tryParse(expiryStr)?.toLocal() : null;
    final daysLeft = expiryDate != null
        ? expiryDate.difference(DateTime.now()).inDays
        : null;
    String fmtDate(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Scaffold(
      backgroundColor: _cream,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // ── Header ─────────────────────────────────────
                SliverAppBar(
                  pinned: true,
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  expandedHeight: 220,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0A1931), Color(0xFF1B3560)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 34),
                          // Avatar
                          GestureDetector(
                            onTap: _uploadAvatar,
                            child: Stack(
                              children: [
                                Container(
                                  width: 84,
                                  height: 84,
                                  decoration: BoxDecoration(
                                    color: _gold,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                        color: Colors.white.withOpacity(0.85), width: 3),
                                    image: (_profile?['avatar_url']
                                                as String?)
                                            ?.isNotEmpty ==
                                        true
                                        ? DecorationImage(
                                            image: NetworkImage(
                                                _profile!['avatar_url']
                                                    as String),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  alignment: Alignment.center,
                                  child: (_profile?['avatar_url'] as String?)
                                              ?.isNotEmpty ==
                                          true
                                      ? null
                                      : _uploadingAvatar
                                          ? const SizedBox(
                                              width: 28,
                                              height: 28,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: _navy,
                                              ),
                                            )
                                          : Text(
                                              displayName.isNotEmpty
                                                  ? displayName[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                color: _navy,
                                                fontSize: 34,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: const BoxDecoration(
                                      color: _gold,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      CupertinoIcons.camera_fill,
                                      size: 14,
                                      color: _navy,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: tierColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: tierColor, width: 1),
                            ),
                            child: Text(
                              tierLabel,
                              style: TextStyle(
                                  color: tierColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  title: const Text('Hồ sơ của tôi'),
                  actions: [
                    IconButton(
                      icon: const Icon(CupertinoIcons.pencil_circle_fill),
                      tooltip: 'Đổi tên',
                      onPressed: _editName,
                    ),
                  ],
                ),

                // ── Info cards (account, membership, settings) ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader('Tài khoản'),
                        _InfoCard(children: [
                          _InfoRow(
                            icon: CupertinoIcons.person_fill,
                            label: 'Tên hiển thị',
                            value: displayName,
                            onTap: _editName,
                          ),
                          const Divider(height: 1, indent: 44),
                          _InfoRow(
                            icon: CupertinoIcons.mail_solid,
                            label: 'Email',
                            value: email,
                          ),
                          const Divider(height: 1, indent: 44),
                          _InfoRow(
                            icon: CupertinoIcons.phone_fill,
                            label: 'Số điện thoại',
                            value: (_profile?['phone'] as String?)
                                        ?.isNotEmpty ==
                                    true
                                ? _profile!['phone'] as String
                                : 'Chưa cập nhật',
                            onTap: _editPhone,
                            trailing: const Icon(CupertinoIcons.chevron_right,
                                size: 16, color: Colors.black38),
                          ),
                          const Divider(height: 1, indent: 44),
                          _InfoRow(
                            icon: CupertinoIcons.lock_fill,
                            label: 'Mật khẩu',
                            value: '••••••••',
                            onTap: _changePassword,
                            trailing: const Icon(CupertinoIcons.chevron_right,
                                size: 16, color: Colors.black38),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _SectionHeader('Gói thành viên'),
                        _InfoCard(children: [
                          _InfoRow(
                            icon: CupertinoIcons.star_fill,
                            label: 'Gói hiện tại',
                            value: tierLabel,
                            valueColor: tierColor,
                          ),
                          if (tier != null) ...[
                            const Divider(height: 1, indent: 44),
                            _InfoRow(
                              icon: CupertinoIcons.calendar_badge_plus,
                              label: 'Ngày đăng ký',
                              value: startDate != null ? fmtDate(startDate) : '—',
                            ),
                            const Divider(height: 1, indent: 44),
                            _InfoRow(
                              icon: CupertinoIcons.calendar_badge_minus,
                              label: 'Ngày hết hạn',
                              value: expiryDate != null ? fmtDate(expiryDate) : '—',
                              valueColor: daysLeft != null && daysLeft <= 7
                                  ? Colors.red
                                  : null,
                            ),
                            const Divider(height: 1, indent: 44),
                            _InfoRow(
                              icon: CupertinoIcons.clock_fill,
                              label: 'Thời gian còn lại',
                              value: daysLeft == null
                                  ? '—'
                                  : daysLeft <= 0
                                      ? 'Đã hết hạn'
                                      : '$daysLeft ngày',
                              valueColor: daysLeft != null
                                  ? (daysLeft <= 0
                                      ? Colors.red
                                      : daysLeft <= 7
                                          ? Colors.orange
                                          : Colors.green.shade700)
                                  : null,
                            ),
                          ],
                        ]),
                        const SizedBox(height: 20),
                        _SectionHeader('Hoạt động'),
                        _ActivityStats(
                          profile: _profile,
                          postedCount: _postedCount,
                          chatCount: _chatCount,
                        ),
                        const SizedBox(height: 20),
                        if (_profile?['is_admin'] == true) ...[
                          _SectionHeader('Quản trị'),
                          _InfoCard(children: [
                            _InfoRow(
                              icon: CupertinoIcons.shield_fill,
                              label: 'Admin Panel',
                              value: 'Quản lý hệ thống',
                              valueColor: const Color(0xFF0A1931),
                              iconColor: const Color(0xFFC8A951),
                              trailing: const Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 16,
                                  color: Colors.black38),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AdminScreen()),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 20),
                        ],
                        _SectionHeader('Khác'),
                        _InfoCard(children: [
                          _InfoRow(
                            icon: CupertinoIcons.arrow_right_circle_fill,
                            label: 'Đăng xuất',
                            value: '',
                            valueColor: Colors.red,
                            iconColor: Colors.red,
                            onTap: _confirmLogout,
                          ),
                        ]),
                        const SizedBox(height: 20),
                        // ── Tab header ──────────────────────────
                        _SectionHeader('Bất động sản của tôi'),
                      ],
                    ),
                  ),
                ),

                // ── Sticky TabBar ────────────────────────────────
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _StickyTabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: _navy,
                      unselectedLabelColor: Colors.black45,
                      indicatorColor: _gold,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                      unselectedLabelStyle:
                          const TextStyle(fontSize: 13),
                      tabs: const [
                        Tab(text: 'Tin đăng'),
                        Tab(text: 'Đã lưu'),
                        Tab(text: 'Đặt lịch'),
                      ],
                    ),
                  ),
                ),
              // ── Tab content fills the rest of the scroll area ─────────
              SliverFillRemaining(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1 — Tin đăng
                    _PostingsTab(uid: _user?.uid ?? ''),
                    // Tab 2 — Đã lưu
                    _SavedTab(savedProperties: widget.savedProperties),
                    // Tab 3 — Đặt lịch
                    _BookingsTab(uid: _user?.uid ?? ''),
                  ],
                ),
              ),
            ],
          ),
    );
  }
}

// ── Sticky TabBar delegate ────────────────────────────────────────────────

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _StickyTabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height + 1;
  @override
  double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          tabBar,
          const Divider(height: 1),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyTabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}

// ── Tab: Tin đăng (own posted properties) ────────────────────────────────

class _PostingsTab extends StatelessWidget {
  const _PostingsTab({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return const Center(
          child: Text('Đăng nhập để xem tin đăng của bạn.'));
    }
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirestoreService.instance.getUserPostingsStream(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.building_2_fill, size: 48, color: Colors.black26),
                SizedBox(height: 12),
                Text('Bạn chưa đăng tin nào',
                    style: TextStyle(color: Colors.black45)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final item = items[index];
            return _ListingTile(item: item);
          },
        );
      },
    );
  }
}

// ── Tab: Đã lưu ──────────────────────────────────────────────────────────

class _SavedTab extends StatelessWidget {
  const _SavedTab({required this.savedProperties});
  final List<Map<String, dynamic>> savedProperties;

  @override
  Widget build(BuildContext context) {
    if (savedProperties.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.heart_fill, size: 48, color: Colors.black26),
            SizedBox(height: 12),
            Text('Chưa có bất động sản yêu thích',
                style: TextStyle(color: Colors.black45)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: savedProperties.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = savedProperties[index];
        return _ListingTile(item: {
          'title': item['title'],
          'location': item['location'],
          'price': item['price'],
          'type': item['type'],
          'bedrooms': item['bedrooms'],
          'area': item['area'],
          'image_url': item['imageUrl'],
          'status': 'active',
        });
      },
    );
  }
}

// ── Tab: Đặt lịch ────────────────────────────────────────────────────────

class _BookingsTab extends StatelessWidget {
  const _BookingsTab({required this.uid});
  final String uid;

  String _fmtDate(String? raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) {
      return const Center(
          child: Text('Đăng nhập để xem lịch đặt của bạn.'));
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: FirestoreService.instance.getUserBookings(uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.calendar_today, size: 48,
                    color: Colors.black26),
                SizedBox(height: 12),
                Text('Bạn chưa có lịch hẹn nào',
                    style: TextStyle(color: Colors.black45)),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final b = items[index];
            final bType = b['booking_type'] as String? ?? '';
            final typeLabel = switch (bType) {
              'book' => '📅 Đặt lịch xem',
              'contact' => '📞 Liên hệ tư vấn',
              'vr_basic' => '🎬 VR Cơ bản',
              'vr_pro' => '🎬 VR Chuyên nghiệp',
              'vr_premium' => '🎬 VR Cao cấp',
              _ => '📋 Yêu cầu',
            };
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _navy.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(CupertinoIcons.calendar_today,
                        size: 18, color: _navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b['property_title'] as String? ?? 'Yêu cầu dịch vụ',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(typeLabel,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 3),
                        Text(
                          _fmtDate(b['created_at'] as String?),
                          style: const TextStyle(
                              fontSize: 11, color: Colors.black38),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Shared listing tile ───────────────────────────────────────────────────

class _ListingTile extends StatelessWidget {
  const _ListingTile({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final status = item['status'] as String? ?? 'pending';
    final statusColor = switch (status) {
      'active' => Colors.green.shade600,
      'pending' => Colors.orange.shade700,
      'rejected' => Colors.red.shade600,
      _ => Colors.black45,
    };
    final statusLabel = switch (status) {
      'active' => 'Đã duyệt',
      'pending' => 'Chờ duyệt',
      'rejected' => 'Bị từ chối',
      _ => status,
    };
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius:
                const BorderRadius.horizontal(left: Radius.circular(14)),
            child: item['image_url'] != null
                ? Image.network(
                    item['image_url'] as String,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] as String? ?? 'Không có tiêu đề',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item['location'] as String? ??
                        item['type'] as String? ??
                        '',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        item['price'] as String? ?? 'Thương lượng',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _navy),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style: TextStyle(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 12),
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

  Widget _placeholder() => Container(
        width: 80,
        height: 80,
        color: const Color(0xFFE9EFF7),
        child: const Icon(CupertinoIcons.building_2_fill,
            color: Colors.black26, size: 28),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: _gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black45,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
    this.valueColor,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? valueColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: (iconColor ?? _navy).withOpacity(0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: iconColor ?? _navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style:
                    const TextStyle(color: _navy, fontWeight: FontWeight.w500),
              ),
            ),
            if (value.isNotEmpty)
              Text(
                value,
                style: TextStyle(
                    color: valueColor ?? Colors.black54, fontSize: 14),
              ),
            if (trailing != null) ...[
              const SizedBox(width: 4),
              trailing!,
            ] else if (onTap != null)
              const Icon(CupertinoIcons.chevron_right,
                  size: 16, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

class _ActivityStats extends StatelessWidget {
  const _ActivityStats({
    required this.profile,
    required this.postedCount,
    required this.chatCount,
  });
  final Map<String, dynamic>? profile;
  final int postedCount;
  final int chatCount;

  @override
  Widget build(BuildContext context) {
    final savedCount = (profile?['savedPropertyIds'] as List?)?.length ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          _StatCell(
            icon: CupertinoIcons.heart_fill,
            label: 'Đã lưu',
            value: '$savedCount',
            color: const Color(0xFFE05252),
          ),
          _Divider(),
          _StatCell(
            icon: CupertinoIcons.chat_bubble_2_fill,
            label: 'Tin nhắn',
            value: '$chatCount',
            color: _navy,
          ),
          _Divider(),
          _StatCell(
            icon: CupertinoIcons.doc_text_fill,
            label: 'Tin đã đăng',
            value: '$postedCount',
            color: _gold,
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: _navy)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.black45)),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        width: 1, height: 60, color: Colors.black.withOpacity(0.07));
  }
}

class _PwdField extends StatefulWidget {
  const _PwdField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  State<_PwdField> createState() => _PwdFieldState();
}

class _PwdFieldState extends State<_PwdField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}
