import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'firestore_service.dart';

const Color _navy = Color(0xFF0A1931);
const Color _gold = Color(0xFFD2A941);
const Color _cream = Color(0xFFFAF7F2);

class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: _cream,
        appBar: AppBar(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(CupertinoIcons.shield_fill, color: _gold, size: 20),
              SizedBox(width: 8),
              Text('Admin Panel',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          bottom: const TabBar(
            labelColor: _gold,
            unselectedLabelColor: Colors.white60,
            indicatorColor: _gold,
            tabs: [
              Tab(icon: Icon(CupertinoIcons.chart_bar_alt_fill, size: 18), text: 'Tổng quan'),
              Tab(icon: Icon(CupertinoIcons.creditcard_fill, size: 18), text: 'Doanh thu'),
              Tab(icon: Icon(CupertinoIcons.house_fill, size: 18), text: 'Tin đăng'),
              Tab(icon: Icon(CupertinoIcons.person_2_fill, size: 18), text: 'Người dùng'),
              Tab(icon: Icon(CupertinoIcons.calendar, size: 18), text: 'Đặt lịch'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DashboardTab(),
            _RevenueTab(),
            _ListingsTab(),
            _UsersTab(),
            _BookingsTab(),
          ],
        ),
      ),
    );
  }
}

// ── Dashboard ────────────────────────────────────────────────────────────────

class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  Map<String, int>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await FirestoreService.instance.getAdminStats();
    if (mounted) setState(() { _stats = stats; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final s = _stats!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text('Tổng quan hệ thống',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: _navy, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Kéo xuống để làm mới',
              style: TextStyle(color: Colors.black38, fontSize: 12)),
          const SizedBox(height: 20),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
            children: [
              _StatCard(
                label: 'Người dùng',
                value: '${s['users']}',
                icon: CupertinoIcons.person_2_fill,
                color: const Color(0xFF3B82F6),
              ),
              _StatCard(
                label: 'Tổng tin đăng',
                value: '${s['listings']}',
                icon: CupertinoIcons.house_fill,
                color: const Color(0xFF10B981),
              ),
              _StatCard(
                label: 'Chờ duyệt',
                value: '${s['pending']}',
                icon: CupertinoIcons.clock_fill,
                color: const Color(0xFFF59E0B),
              ),
              _StatCard(
                label: 'Đặt lịch',
                value: '${s['bookings']}',
                icon: CupertinoIcons.calendar_badge_plus,
                color: const Color(0xFF8B5CF6),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _InfoBanner(
            icon: CupertinoIcons.info_circle_fill,
            text: s['pending']! > 0
                ? 'Có ${s['pending']} tin đăng đang chờ duyệt.'
                : 'Không có tin đăng nào chờ duyệt.',
            color: s['pending']! > 0
                ? const Color(0xFFF59E0B)
                : const Color(0xFF10B981),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.08)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: _navy)),
              Text(label,
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(
      {required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: color, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }
}

// ── Revenue ──────────────────────────────────────────────────────────────────

class _RevenueTab extends StatefulWidget {
  const _RevenueTab();

  @override
  State<_RevenueTab> createState() => _RevenueTabState();
}

class _RevenueTabState extends State<_RevenueTab> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stats = await FirestoreService.instance.getPaymentStats();
    if (mounted) setState(() { _stats = stats; _loading = false; });
  }

  String _formatMoney(int amount) {
    if (amount >= 1000000) {
      final m = amount / 1000000;
      return '${m % 1 == 0 ? m.toInt() : m.toStringAsFixed(1)}M đ';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toInt()}K đ';
    }
    return '$amount đ';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final s = _stats!;
    final totalRevenue = s['totalRevenue'] as int;
    final activeRevenue = s['activeRevenue'] as int;
    final totalMembers = s['totalMembers'] as int;
    final activeMembers = s['activeMembers'] as int;
    final expiringSoon = s['expiringSoon'] as int;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text('Thống kê doanh thu',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(color: _navy, fontWeight: FontWeight.w700)),
          Text('Kéo xuống để làm mới',
              style: const TextStyle(color: Colors.black38, fontSize: 12)),
          const SizedBox(height: 20),

          // Tổng doanh thu
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tổng doanh thu ước tính',
                    style: TextStyle(color: Colors.white60, fontSize: 13)),
                const SizedBox(height: 6),
                Text(_formatMoney(totalRevenue),
                    style: const TextStyle(
                        color: _gold,
                        fontSize: 36,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MiniStat(
                        label: 'Đang active',
                        value: _formatMoney(activeRevenue),
                        color: const Color(0xFF10B981)),
                    const SizedBox(width: 20),
                    _MiniStat(
                        label: 'Tổng thành viên',
                        value: '$totalMembers',
                        color: Colors.white70),
                    const SizedBox(width: 20),
                    _MiniStat(
                        label: 'Active',
                        value: '$activeMembers',
                        color: const Color(0xFF10B981)),
                  ],
                ),
              ],
            ),
          ),

          if (expiringSoon > 0) ...[
            const SizedBox(height: 12),
            _InfoBanner(
              icon: CupertinoIcons.exclamationmark_circle_fill,
              text: '$expiringSoon thành viên sắp hết hạn trong 7 ngày tới.',
              color: const Color(0xFFF59E0B),
            ),
          ],

          const SizedBox(height: 20),
          const Text('Chi tiết theo gói',
              style: TextStyle(
                  color: _navy,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
          const SizedBox(height: 12),

          _PlanRevenueCard(
            label: 'Gói Tháng',
            price: '300.000đ / tháng',
            total: s['monthly'] as int,
            active: s['activeMonthly'] as int,
            revenue: (s['monthly'] as int) * 300000,
            color: const Color(0xFF3B82F6),
            icon: CupertinoIcons.calendar,
          ),
          const SizedBox(height: 10),
          _PlanRevenueCard(
            label: 'Gói Quý',
            price: '700.000đ / quý',
            total: s['quarterly'] as int,
            active: s['activeQuarterly'] as int,
            revenue: (s['quarterly'] as int) * 700000,
            color: const Color(0xFF8B5CF6),
            icon: CupertinoIcons.calendar_badge_plus,
          ),
          const SizedBox(height: 10),
          _PlanRevenueCard(
            label: 'Gói Năm',
            price: '2.100.000đ / năm',
            total: s['yearly'] as int,
            active: s['activeYearly'] as int,
            revenue: (s['yearly'] as int) * 2100000,
            color: _gold,
            icon: CupertinoIcons.star_fill,
          ),

          const SizedBox(height: 20),
          const Text('Lưu ý',
              style: TextStyle(
                  color: Colors.black45,
                  fontSize: 12,
                  fontStyle: FontStyle.italic)),
          const Text(
            'Doanh thu được tính dựa trên số lượng gói đã đăng ký (kể cả đã hết hạn). '
            'Doanh thu active chỉ tính các gói còn hiệu lực.',
            style: TextStyle(color: Colors.black38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      ],
    );
  }
}

class _PlanRevenueCard extends StatelessWidget {
  const _PlanRevenueCard({
    required this.label,
    required this.price,
    required this.total,
    required this.active,
    required this.revenue,
    required this.color,
    required this.icon,
  });

  final String label;
  final String price;
  final int total;
  final int active;
  final int revenue;
  final Color color;
  final IconData icon;

  String _fmt(int amount) {
    if (amount >= 1000000) {
      final m = amount / 1000000;
      return '${m % 1 == 0 ? m.toInt() : m.toStringAsFixed(1)}M đ';
    }
    return '${(amount / 1000).toInt()}K đ';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _navy)),
                Text(price,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black45)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Tag('$total đã mua', Colors.black38),
                    const SizedBox(width: 6),
                    _Tag('$active active', const Color(0xFF10B981)),
                  ],
                ),
              ],
            ),
          ),
          Text(
            revenue == 0 ? '—' : _fmt(revenue),
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Listings ─────────────────────────────────────────────────────────────────

class _ListingsTab extends StatefulWidget {
  const _ListingsTab();

  @override
  State<_ListingsTab> createState() => _ListingsTabState();
}

class _ListingsTabState extends State<_ListingsTab> {
  String _filter = 'all'; // all | pending | active | rejected

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter bar
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(label: 'Tất cả', value: 'all', selected: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
                _FilterChip(label: 'Chờ duyệt', value: 'pending', selected: _filter == 'pending', onTap: () => setState(() => _filter = 'pending')),
                _FilterChip(label: 'Đã duyệt', value: 'active', selected: _filter == 'active', onTap: () => setState(() => _filter = 'active')),
                _FilterChip(label: 'Từ chối', value: 'rejected', selected: _filter == 'rejected', onTap: () => setState(() => _filter = 'rejected')),
              ],
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirestoreService.instance.getAdminListingsStream(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snap.data ?? [];
              final items = _filter == 'all'
                  ? all
                  : all.where((r) => r['status'] == _filter).toList();
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.house, size: 48, color: Colors.black26),
                      const SizedBox(height: 12),
                      Text('Không có tin đăng nào',
                          style: TextStyle(color: Colors.black45)),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _ListingCard(data: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _navy : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? _navy : Colors.black26),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : Colors.black54,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal),
        ),
      ),
    );
  }
}

class _ListingCard extends StatefulWidget {
  const _ListingCard({required this.data});
  final Map<String, dynamic> data;

  @override
  State<_ListingCard> createState() => _ListingCardState();
}

class _ListingCardState extends State<_ListingCard> {
  bool _loading = false;

  Future<void> _showPreview(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ListingPreviewSheet(
        data: widget.data,
        onUpdateStatus: (s) async {
          await _updateStatus(s);
          if (context.mounted) Navigator.pop(context);
        },
        onDelete: () async {
          Navigator.pop(context);
          await _delete();
        },
      ),
    );
  }

  Future<void> _updateStatus(String status) async {
    setState(() => _loading = true);
    await FirestoreService.instance
        .updateListingStatus(widget.data['id'] as String, status);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa tin đăng'),
        content: const Text('Bạn chắc chắn muốn xóa tin này?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Xóa')),
        ],
      ),
    );
    if (ok == true) {
      await FirestoreService.instance
          .adminDeleteListing(widget.data['id'] as String);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final status = d['status'] as String? ?? 'pending';
    final statusColor = switch (status) {
      'active' => const Color(0xFF10B981),
      'rejected' => Colors.red,
      _ => const Color(0xFFF59E0B),
    };
    final statusLabel = switch (status) {
      'active' => 'Đã duyệt',
      'rejected' => 'Từ chối',
      _ => 'Chờ duyệt',
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    d['title'] as String? ?? '(Không có tiêu đề)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: _navy),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${d['owner_name'] ?? ''} · ${d['location'] ?? ''} · ${d['price'] ?? ''}',
              style: const TextStyle(fontSize: 13, color: Colors.black54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
            else
              Row(
                children: [
                  if (status != 'active')
                    _ActionBtn(
                      label: 'Duyệt',
                      icon: CupertinoIcons.checkmark_circle_fill,
                      color: const Color(0xFF10B981),
                      onTap: () => _updateStatus('active'),
                    ),
                  if (status != 'active') const SizedBox(width: 8),
                  if (status != 'rejected')
                    _ActionBtn(
                      label: 'Từ chối',
                      icon: CupertinoIcons.xmark_circle_fill,
                      color: Colors.red,
                      onTap: () => _updateStatus('rejected'),
                    ),
                  if (status != 'rejected') const SizedBox(width: 8),
                  if (status == 'active')
                    _ActionBtn(
                      label: 'Bỏ duyệt',
                      icon: CupertinoIcons.arrow_uturn_left_circle_fill,
                      color: const Color(0xFFF59E0B),
                      onTap: () => _updateStatus('pending'),
                    ),
                  const Spacer(),
                  // Xem thử
                  IconButton(
                    icon: const Icon(CupertinoIcons.eye_fill,
                        color: Color(0xFF3B82F6), size: 18),
                    onPressed: () => _showPreview(context),
                    tooltip: 'Xem thử',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(CupertinoIcons.trash_fill,
                        color: Colors.red, size: 18),
                    onPressed: _delete,
                    tooltip: 'Xóa',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Users ─────────────────────────────────────────────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab();

  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  List<Map<String, dynamic>>? _users;
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await FirestoreService.instance.getAdminUsers();
    if (mounted) setState(() { _users = users; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final all = _users ?? [];
    final items = _search.isEmpty
        ? all
        : all.where((u) {
            final name = (u['full_name'] as String? ?? '').toLowerCase();
            final email = (u['email'] as String? ?? '').toLowerCase();
            return name.contains(_search.toLowerCase()) ||
                email.contains(_search.toLowerCase());
          }).toList();

    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Tìm kiếm tên hoặc email...',
              prefixIcon: const Icon(CupertinoIcons.search, size: 18),
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: items.isEmpty
                ? const Center(
                    child: Text('Không có kết quả',
                        style: TextStyle(color: Colors.black45)))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _UserCard(data: items[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final name = data['full_name'] as String? ?? 'Người dùng';
    final email = data['email'] as String? ?? '';
    final tier = data['membership_tier'] as String?;
    final isAdmin = data['is_admin'] == true;
    final expiryStr = data['membership_expiry_date'] as String?;
    final expiry = expiryStr != null ? DateTime.tryParse(expiryStr)?.toLocal() : null;

    final tierLabel = switch (tier) {
      'monthly' => 'Tháng',
      'quarterly' => 'Quý',
      'yearly' => 'Năm',
      _ => 'Miễn phí',
    };
    final tierColor = tier != null ? _gold : Colors.black38;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isAdmin ? _navy : const Color(0xFFE5E7EB),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: isAdmin ? _gold : Colors.black54,
                  fontWeight: FontWeight.w700,
                  fontSize: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: _navy)),
                    if (isAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _navy,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('Admin',
                            style: TextStyle(
                                color: _gold,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(email,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                    overflow: TextOverflow.ellipsis),
                if (expiry != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Hết hạn: ${expiry.day.toString().padLeft(2, '0')}/${expiry.month.toString().padLeft(2, '0')}/${expiry.year}',
                    style: TextStyle(
                        fontSize: 11,
                        color: expiry.isBefore(DateTime.now())
                            ? Colors.red
                            : Colors.black38),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tierColor.withValues(alpha: 0.3)),
            ),
            child: Text(tierLabel,
                style: TextStyle(
                    color: tierColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ── Bookings ──────────────────────────────────────────────────────────────────

class _BookingsTab extends StatefulWidget {
  const _BookingsTab();

  @override
  State<_BookingsTab> createState() => _BookingsTabState();
}

class _BookingsTabState extends State<_BookingsTab> {
  List<Map<String, dynamic>>? _bookings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await FirestoreService.instance.getAdminBookings();
    if (mounted) setState(() { _bookings = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final items = _bookings ?? [];
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.calendar, size: 48, color: Colors.black26),
            SizedBox(height: 12),
            Text('Chưa có yêu cầu đặt lịch nào',
                style: TextStyle(color: Colors.black45)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _BookingCard(data: items[i]),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final type = data['booking_type'] as String? ?? 'book';
    final isVr = type.startsWith('vr_');

    // Label & màu theo loại
    final (typeLabel, typeColor) = switch (type) {
      'book'       => ('Đặt lịch xem', const Color(0xFF3B82F6)),
      'vr_basic'   => ('VR Cơ bản', const Color(0xFF3B82F6)),
      'vr_pro'     => ('VR Chuyên nghiệp', const Color(0xFF8B5CF6)),
      'vr_premium' => ('VR Cao cấp', _gold),
      _            => ('Tư vấn', const Color(0xFF8B5CF6)),
    };

    final createdStr = data['created_at'] as String?;
    final created = createdStr != null
        ? DateTime.tryParse(createdStr)?.toLocal()
        : null;
    final dateLabel = created != null
        ? '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}'
        : '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isVr
            ? Border.all(color: typeColor.withValues(alpha: 0.35), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
              color: isVr
                  ? typeColor.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isVr) ...[
                      Icon(CupertinoIcons.cube_box_fill,
                          size: 10, color: typeColor),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      typeLabel,
                      style: TextStyle(
                          color: typeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(dateLabel,
                  style: const TextStyle(fontSize: 11, color: Colors.black38)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            data['property_title'] as String? ?? 'Bất động sản',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14, color: _navy),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          _BookingRow(
              icon: CupertinoIcons.person,
              text: data['contact_name'] as String? ?? ''),
          _BookingRow(
              icon: CupertinoIcons.phone,
              text: data['contact_phone'] as String? ?? ''),
          if ((data['schedule'] as String?)?.isNotEmpty == true)
            _BookingRow(
                icon: isVr ? CupertinoIcons.location : CupertinoIcons.clock,
                text: data['schedule'] as String),
          if ((data['notes'] as String?)?.isNotEmpty == true)
            _BookingRow(
                icon: CupertinoIcons.text_quote,
                text: data['notes'] as String),
        ],
      ),
    );
  }
}

class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.black38),
          const SizedBox(width: 6),
          Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 13, color: Colors.black54))),
        ],
      ),
    );
  }
}

// ── Listing Preview Sheet ─────────────────────────────────────────────────────

class _ListingPreviewSheet extends StatelessWidget {
  const _ListingPreviewSheet({
    required this.data,
    required this.onUpdateStatus,
    required this.onDelete,
  });

  final Map<String, dynamic> data;
  final Future<void> Function(String status) onUpdateStatus;
  final Future<void> Function() onDelete;

  String _fmtDate(String? raw) {
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] as String? ?? 'pending';
    final statusColor = switch (status) {
      'active' => const Color(0xFF10B981),
      'rejected' => Colors.red,
      _ => const Color(0xFFF59E0B),
    };
    final statusLabel = switch (status) {
      'active' => 'Đã duyệt',
      'rejected' => 'Từ chối',
      _ => 'Chờ duyệt',
    };

    // Images
    final rawImages = data['images'];
    final images = rawImages is List
        ? rawImages.whereType<String>().toList()
        : <String>[];

    final title = data['title'] as String? ?? '(Không có tiêu đề)';
    final description = data['description'] as String?;
    final price = data['price'] as String? ?? data['price_value']?.toString();
    final location = data['location'] as String?;
    final area = data['area'] as String? ?? data['area_value']?.toString();
    final propertyType = data['property_type'] as String?;
    final listingType = data['listing_type'] as String?;
    final ownerName = data['owner_name'] as String?;
    final ownerEmail = data['owner_email'] as String?;
    final ownerPhone = data['owner_phone'] as String?;
    final viewCount = (data['view_count'] as int?) ?? 0;
    final createdAt = data['created_at'] as String?;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.eye_fill,
                      size: 16, color: Color(0xFF3B82F6)),
                  const SizedBox(width: 8),
                  const Text('Xem thử bài đăng',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _navy)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(CupertinoIcons.xmark_circle_fill,
                        color: Colors.black26, size: 24),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // Image(s)
                  if (images.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        images.first,
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _imagePlaceholder(),
                      ),
                    ),
                    if (images.length > 1) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 64,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: images.length - 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              images[i + 1],
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(
                                width: 64,
                                height: 64,
                                color: const Color(0xFFE9EFF7),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ] else ...[
                    _imagePlaceholder(),
                    const SizedBox(height: 16),
                  ],

                  // Title
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: _navy)),
                  const SizedBox(height: 10),

                  // Tags row
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (price != null)
                        _Tag(price, const Color(0xFF10B981)),
                      if (area != null)
                        _Tag('$area m²', const Color(0xFF3B82F6)),
                      if (propertyType != null)
                        _Tag(propertyType, _navy),
                      if (listingType != null)
                        _Tag(
                          listingType == 'rent' ? 'Cho thuê' : 'Bán',
                          const Color(0xFF8B5CF6),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Location
                  if (location != null) ...[
                    _PreviewRow(
                        icon: CupertinoIcons.location_solid,
                        text: location,
                        color: Colors.red),
                    const SizedBox(height: 8),
                  ],

                  // Description
                  if (description != null && description.isNotEmpty) ...[
                    const Divider(height: 24),
                    const Text('Mô tả',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _navy)),
                    const SizedBox(height: 8),
                    Text(description,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                            height: 1.5)),
                  ],

                  // Owner info
                  if (ownerName != null || ownerEmail != null) ...[
                    const Divider(height: 24),
                    const Text('Người đăng',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _navy)),
                    const SizedBox(height: 8),
                    if (ownerName?.isNotEmpty == true)
                      _PreviewRow(
                          icon: CupertinoIcons.person_fill,
                          text: ownerName!,
                          color: _navy),
                    if (ownerEmail?.isNotEmpty == true)
                      _PreviewRow(
                          icon: CupertinoIcons.mail_solid,
                          text: ownerEmail!,
                          color: _navy),
                    if (ownerPhone?.isNotEmpty == true)
                      _PreviewRow(
                          icon: CupertinoIcons.phone_fill,
                          text: ownerPhone!,
                          color: _navy),
                  ],

                  // Meta
                  const Divider(height: 24),
                  _PreviewRow(
                      icon: CupertinoIcons.calendar_today,
                      text: 'Đăng lúc: ${_fmtDate(createdAt)}',
                      color: Colors.black45),
                  if (viewCount > 0)
                    _PreviewRow(
                        icon: CupertinoIcons.eye_fill,
                        text: '$viewCount lượt xem',
                        color: Colors.black45),

                  // Action buttons
                  const SizedBox(height: 24),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (status != 'active')
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => onUpdateStatus('active'),
                            style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981)),
                            icon: const Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                size: 16),
                            label: const Text('Duyệt bài'),
                          ),
                        ),
                      if (status != 'active' && status != 'rejected')
                        const SizedBox(width: 10),
                      if (status != 'rejected')
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => onUpdateStatus('rejected'),
                            style: FilledButton.styleFrom(
                                backgroundColor: Colors.red),
                            icon: const Icon(CupertinoIcons.xmark_circle_fill,
                                size: 16),
                            label: const Text('Từ chối'),
                          ),
                        ),
                      if (status == 'active') ...[
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => onUpdateStatus('pending'),
                            style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B)),
                            icon: const Icon(
                                CupertinoIcons.arrow_uturn_left_circle_fill,
                                size: 16),
                            label: const Text('Bỏ duyệt'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: onDelete,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red)),
                        icon: const Icon(CupertinoIcons.trash_fill, size: 16),
                        label: const Text('Xóa'),
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

  Widget _imagePlaceholder() => Container(
        height: 160,
        decoration: BoxDecoration(
          color: const Color(0xFFE9EFF7),
          borderRadius: BorderRadius.circular(14),
        ),
        alignment: Alignment.center,
        child: const Icon(CupertinoIcons.building_2_fill,
            size: 48, color: Colors.black26),
      );
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow(
      {required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 13, color: color, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
