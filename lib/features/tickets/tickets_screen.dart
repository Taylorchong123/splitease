import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../services/notification_service.dart';
import 'create_ticket_screen.dart';
import 'scan_screen.dart';
import 'ticket_detail_screen.dart';

Widget buildStatusBadge(BuildContext context, TicketStatus status) {
  final (label, bg, fg) = switch (status) {
    TicketStatus.draft => ('Draft', const Color(0xFFF1F5F9), const Color(0xFF475569)),
    TicketStatus.open => ('Open', const Color(0xFFFEF3C7), const Color(0xFFD97706)),
    TicketStatus.partiallyPaid => ('Partially Paid', const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
    TicketStatus.settled => ('Settled', const Color(0xFFDCFCE7), const Color(0xFF15803D)),
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.bold),
    ),
  );
}

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  @override
  void initState() {
    super.initState();
    NotificationService.registerDevice().catchError((_) {});
  }

  void _newTicket() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C897).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.document_scanner, color: Color(0xFF00C897)),
                ),
                title: const Text('Scan a bill', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Extract items, tax & total automatically using AI OCR'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScanScreen()));
                },
              ),
              const Divider(indent: 16, endIndent: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B6EF3).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.edit_note, color: Color(0xFF1B6EF3)),
                ),
                title: const Text('Enter manually', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Create a bill by entering dishes & participants manually'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context)
                      .push(MaterialPageRoute<void>(builder: (_) => const CreateTicketScreen()));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/split_ease_icon.png',
                height: 32,
                width: 32,
                errorBuilder: (_, __, ___) => const Icon(Icons.receipt_long, color: Color(0xFF1B6EF3)),
              ),
            ),
            const SizedBox(width: 10),
            const Text('SplitEase', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_outlined),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              ref.invalidate(ticketsProvider);
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTicket,
        backgroundColor: const Color(0xFF1B6EF3),
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add),
        label: const Text('New bill', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/icon/split_ease_icon.png',
                      height: 80,
                      width: 80,
                      errorBuilder: (_, __, ___) => const Icon(Icons.receipt_long, size: 64, color: Color(0xFF1B6EF3)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No bills yet',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Tap "New bill" below to scan a receipt or create one manually.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _newTicket,
                      icon: const Icon(Icons.add),
                      label: const Text('Create your first bill'),
                    ),
                  ],
                ),
              ),
            );
          }

          final currentUid = user?.uid;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              // --- Hero Brand Summary Banner ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B6EF3), Color(0xFF0F52BA)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B6EF3).withValues(alpha: 0.3),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Dashboard Summary',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${list.length} Bill${list.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Split Bills Fairly',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF1B6EF3),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => const ScanScreen()),
                            ),
                            icon: const Icon(Icons.document_scanner, size: 18),
                            label: const Text('Scan Bill'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C897),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(builder: (_) => const CreateTicketScreen()),
                            ),
                            icon: const Icon(Icons.edit, size: 18),
                            label: const Text('Manual Bill'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              Text(
                'Recent Bills',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
              ),
              const SizedBox(height: 12),

              for (final t in list) ...[
                Builder(builder: (context) {
                  final isOwner = t.ownerId == currentUid;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Dismissible(
                      key: Key(t.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.delete_outline, color: Colors.white),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      confirmDismiss: (_) async {
                        if (!isOwner) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Only the creator can delete this bill')),
                          );
                          return false;
                        }

                        return await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Delete bill?'),
                                content: Text(
                                  'Are you sure you want to delete "${t.title.isEmpty ? 'Untitled bill' : t.title}"?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Theme.of(context).colorScheme.error,
                                    ),
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            ) ==
                            true;
                      },
                      onDismissed: (_) async {
                        await ref.read(ticketRepositoryProvider).delete(t.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Deleted "${t.title.isEmpty ? 'Untitled bill' : t.title}"')),
                          );
                        }
                      },
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => TicketDetailScreen(ticketId: t.id)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: t.source == 'scan'
                                        ? const Color(0xFF00C897).withValues(alpha: 0.12)
                                        : const Color(0xFF1B6EF3).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    t.source == 'scan' ? Icons.document_scanner : Icons.edit_note,
                                    color: t.source == 'scan' ? const Color(0xFF00C897) : const Color(0xFF1B6EF3),
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        t.title.isEmpty ? 'Untitled bill' : t.title,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          buildStatusBadge(context, t.status),
                                          const SizedBox(width: 8),
                                          Text(
                                            '• ${t.participants.length} people',
                                            style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  Money.format(t.total, t.currency),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ],
          );
        },
      ),
    );
  }
}
