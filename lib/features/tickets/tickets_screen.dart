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

String statusLabel(TicketStatus s) => switch (s) {
      TicketStatus.draft => 'Draft',
      TicketStatus.open => 'Open',
      TicketStatus.partiallyPaid => 'Partially paid',
      TicketStatus.settled => 'Settled',
    };

class TicketsScreen extends ConsumerStatefulWidget {
  const TicketsScreen({super.key});

  @override
  ConsumerState<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends ConsumerState<TicketsScreen> {
  @override
  void initState() {
    super.initState();
    // Best effort: push notifications are optional (e.g. unsupported on some platforms).
    NotificationService.registerDevice().catchError((_) {});
  }

  void _newTicket() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.document_scanner_outlined),
              title: const Text('Scan a bill'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ScanScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Enter manually'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const CreateTicketScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tickets = ref.watch(ticketsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My tickets'),
        actions: [
          IconButton(
            tooltip: 'Log out',
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newTicket,
        icon: const Icon(Icons.add),
        label: const Text('New bill'),
      ),
      body: tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No bills yet.\nTap “New bill” to scan or enter one.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = list[i];
              final currentUid = FirebaseAuth.instance.currentUser?.uid;
              final isOwner = t.ownerId == currentUid;

              return Dismissible(
                key: Key(t.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.error,
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

                  final confirmed = await showDialog<bool>(
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
                  );

                  return confirmed == true;
                },
                onDismissed: (_) async {
                  await ref.read(ticketRepositoryProvider).delete(t.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Deleted "${t.title.isEmpty ? 'Untitled bill' : t.title}"')),
                    );
                  }
                },
                child: ListTile(
                  leading: Icon(t.source == 'scan' ? Icons.document_scanner : Icons.edit_note),
                  title: Text(t.title.isEmpty ? 'Untitled bill' : t.title),
                  subtitle: Text('${statusLabel(t.status)} · ${t.participants.length} people'),
                  trailing: Text(Money.format(t.total, t.currency)),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => TicketDetailScreen(ticketId: t.id)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
