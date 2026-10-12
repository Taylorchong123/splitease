import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/money.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../services/notification_service.dart';
import 'tickets_screen.dart' show statusLabel;

class TicketDetailScreen extends ConsumerWidget {
  const TicketDetailScreen({super.key, required this.ticketId});

  final String ticketId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ticketProvider(ticketId));
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(title: Text(async.valueOrNull?.title ?? 'Ticket')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Something went wrong: $e')),
        data: (ticket) {
          if (ticket == null) return const Center(child: Text('Ticket not found'));
          return _TicketBody(ticket: ticket, isOwner: ticket.ownerId == uid);
        },
      ),
    );
  }
}

class _TicketBody extends ConsumerWidget {
  const _TicketBody({required this.ticket, required this.isOwner});

  final Ticket ticket;
  final bool isOwner;

  String? _converted(String preferred) {
    final rates = ticket.fxRates;
    if (rates == null || preferred == ticket.currency) return null;
    try {
      final v = Money.convert(ticket.total, from: ticket.currency, to: preferred, rates: rates);
      return '≈ ${Money.format(v, preferred)}';
    } catch (_) {
      return null;
    }
  }

  Future<void> _setPaid(WidgetRef ref, int index, bool paid) {
    final ps = [...ticket.participants];
    ps[index] = ps[index].copyWith(paid: paid);
    return ref.read(ticketRepositoryProvider).save(ticket.copyWith(participants: ps).recalculated());
  }

  Future<void> _addParticipant(BuildContext context, WidgetRef ref) async {
    final participant = await showDialog<Participant>(
      context: context,
      builder: (ctx) => const _AddParticipantDialog(),
    );
    if (participant == null) return;

    final ps = [
      ...ticket.participants,
      participant,
    ];
    await ref.read(ticketRepositoryProvider).save(ticket.copyWith(participants: ps).recalculated());
  }

  Future<void> _notify(BuildContext context, WidgetRef ref) async {
    await ref.read(ticketRepositoryProvider).queueNotifications(ticket);
    if (!context.mounted) return;

    final unpaid = ticket.participants.where((p) => !p.isOwner && !p.paid).toList();

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Payment Reminders Queued', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Notifications and email reminders with bill breakdowns were queued for ${unpaid.length} participant(s).',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Text('View / Copy Email Breakdown:', style: Theme.of(ctx).textTheme.labelLarge),
              const SizedBox(height: 8),
              for (final p in unpaid) ...[
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.email_outlined),
                  title: Text(p.name),
                  subtitle: Text(p.email),
                  trailing: TextButton.icon(
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Breakdown'),
                    onPressed: () {
                      final text = NotificationService.formatEmailBreakdown(ticket, p);
                      showDialog<void>(
                        context: ctx,
                        builder: (dCtx) => AlertDialog(
                          title: Text('Email for ${p.name}'),
                          content: SingleChildScrollView(
                            child: SelectableText(text),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preferred = ref.watch(preferredCurrencyProvider);
    final converted = _converted(preferred);
    final hasUnpaid = ticket.participants.any((p) => !p.isOwner && !p.paid);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Chip(label: Text(statusLabel(ticket.status))),
                    const Spacer(),
                    DropdownButton<String>(
                      value: preferred,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final c in supportedCurrencies) DropdownMenuItem(value: c, child: Text(c)),
                      ],
                      onChanged: (v) => ref.read(preferredCurrencyProvider.notifier).state = v ?? preferred,
                    ),
                  ],
                ),
                Text(Money.format(ticket.total, ticket.currency), style: theme.textTheme.headlineMedium),
                if (converted != null) Text(converted, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Items', style: theme.textTheme.titleMedium),
        for (final i in ticket.items)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(i.name),
            subtitle: Text(
              [
                if (i.quantity > 1) '${i.quantity} × ${Money.format(i.amount, ticket.currency)}',
                if (i.assignedEmails.isNotEmpty)
                  'Assigned to ${i.assignedEmails.length} participant(s)'
                else
                  'Shared by everyone',
              ].join(' • '),
            ),
            trailing: Text(Money.format(i.total, ticket.currency)),
          ),
        if (ticket.tax > 0)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Tax / service'),
            trailing: Text(Money.format(ticket.tax, ticket.currency)),
          ),
        const Divider(height: 32),
        Row(
          children: [
            Text('Participants', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (isOwner)
              TextButton.icon(
                onPressed: () => _addParticipant(context, ref),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Add'),
              ),
          ],
        ),
        for (var i = 0; i < ticket.participants.length; i++)
          Builder(builder: (context) {
            final p = ticket.participants[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase())),
              title: Text(p.isOwner ? '${p.name} (paid the venue)' : p.name),
              subtitle: Text(p.email),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(Money.format(p.share, ticket.currency)),
                  if (isOwner && !p.isOwner)
                    Checkbox(value: p.paid, onChanged: (v) => _setPaid(ref, i, v ?? false))
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Icon(
                        p.paid ? Icons.check_circle : Icons.schedule,
                        color: p.paid ? Colors.green : theme.disabledColor,
                      ),
                    ),
                ],
              ),
            );
          }),
        const SizedBox(height: 24),
        if (isOwner)
          FilledButton.icon(
            onPressed: hasUnpaid ? () => _notify(context, ref) : null,
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Notify unpaid participants'),
          ),
      ],
    );
  }
}

class _AddParticipantDialog extends StatefulWidget {
  const _AddParticipantDialog();

  @override
  State<_AddParticipantDialog> createState() => _AddParticipantDialogState();
}

class _AddParticipantDialogState extends State<_AddParticipantDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final n = _name.text.trim();
    final e = _email.text.trim().toLowerCase();
    if (n.isEmpty || !e.contains('@')) return;

    Navigator.pop(
      context,
      Participant(name: n, email: e, share: 0, paid: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add participant'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
            ),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

