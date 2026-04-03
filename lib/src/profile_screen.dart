import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'firestore_service.dart';

const Color _navy = Color(0xFF0A1931);
const Color _gold = Color(0xFFC8A951);
const Color _cream = Color(0xFFFAF7F2);
const Color _mist = Color(0xFFEFF3F8);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.onLogout});

  /// Gọi khi người dùng đăng xuất thành công.
  final VoidCallback onLogout;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final User? _user;
  Map<String, dynamic>? _profile;
  bool _loading = true;
  int _postedCount = 0;
  int _chatCount = 0;

  @override
  void initState() {
    super.initState();
    _user = AuthService.instance.currentUser;
    _loadProfile();
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
    await _user?.updateDisplayName(newName);
    await FirestoreService.instance.upsertUserProfile(_user!);
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
    try {
      final email = _user?.email ?? '';
      final cred =
          EmailAuthProvider.credential(email: email, password: curCtrl.text);
      await _user?.reauthenticateWithCredential(cred);
      await _user?.updatePassword(newCtrl.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã đổi mật khẩu thành công.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Lỗi xác thực.')),
        );
      }
    }
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
    final displayName = _user?.displayName ?? _profile?['name'] ?? 'Người dùng';
    final email = _user?.email ?? '';
    final tier = _profile?['membershipTier'] as String?;
    final tierLabel = switch (tier) {
      'monthly' => 'Thành viên Tháng',
      'quarterly' => 'Thành viên Quý',
      'yearly' => 'Thành viên Năm',
      _ => 'Gói miễn phí',
    };
    final tierColor = tier != null ? _gold : Colors.black38;

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
                          const SizedBox(height: 48),
                          // Avatar
                          GestureDetector(
                            onTap: _editName,
                            child: Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: _gold,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white24, width: 2),
                              ),
                              alignment: Alignment.center,
                              child: Text(
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
                      icon: const Icon(CupertinoIcons.pencil_circle),
                      tooltip: 'Đổi tên',
                      onPressed: _editName,
                    ),
                  ],
                ),

                // ── Nội dung ────────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Thông tin tài khoản ─────────────────
                        _SectionHeader('Tài khoản'),
                        _InfoCard(children: [
                          _InfoRow(
                            icon: CupertinoIcons.person,
                            label: 'Tên hiển thị',
                            value: displayName,
                            onTap: _editName,
                          ),
                          const Divider(height: 1, indent: 44),
                          _InfoRow(
                            icon: CupertinoIcons.mail,
                            label: 'Email',
                            value: email,
                          ),
                          const Divider(height: 1, indent: 44),
                          _InfoRow(
                            icon: CupertinoIcons.phone,
                            label: 'Số điện thoại',
                            value:
                                (_profile?['phone'] as String?)?.isNotEmpty ==
                                        true
                                    ? _profile!['phone'] as String
                                    : 'Chưa cập nhật',
                            onTap: _editPhone,
                            trailing: const Icon(CupertinoIcons.chevron_right,
                                size: 16, color: Colors.black38),
                          ),
                          const Divider(height: 1, indent: 44),
                          _InfoRow(
                            icon: CupertinoIcons.lock,
                            label: 'Mật khẩu',
                            value: '••••••••',
                            onTap: _changePassword,
                            trailing: const Icon(CupertinoIcons.chevron_right,
                                size: 16, color: Colors.black38),
                          ),
                        ]),
                        const SizedBox(height: 20),

                        // ── Gói thành viên ──────────────────────
                        _SectionHeader('Gói thành viên'),
                        _InfoCard(children: [
                          _InfoRow(
                            icon: CupertinoIcons.star,
                            label: 'Gói hiện tại',
                            value: tierLabel,
                            valueColor: tierColor,
                          ),
                        ]),
                        const SizedBox(height: 20),

                        // ── Thống kê hoạt động ─────────────────
                        _SectionHeader('Hoạt động'),
                        _ActivityStats(
                          profile: _profile,
                          postedCount: _postedCount,
                          chatCount: _chatCount,
                        ),
                        const SizedBox(height: 20),

                        // ── Hành động khác ─────────────────────
                        _SectionHeader('Khác'),
                        _InfoCard(children: [
                          _InfoRow(
                            icon: CupertinoIcons.square_arrow_right,
                            label: 'Đăng xuất',
                            value: '',
                            valueColor: Colors.red,
                            iconColor: Colors.red,
                            onTap: _confirmLogout,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Widgets phụ ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.black45,
          letterSpacing: 1.2,
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor ?? _navy),
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
                  size: 16, color: Colors.black38),
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
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
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
