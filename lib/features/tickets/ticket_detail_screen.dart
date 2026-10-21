import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/currencies.dart';
import '../../core/money.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../services/notification_service.dart';
import 'tickets_screen.dart' show buildStatusBadge;

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

  Future<void> _notify(BuildContext context, WidgetRef ref) async {
    final unpaid = ticket.participants.where((p) => !p.isOwner && !p.paid).toList();
    if (unpaid.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SelectNotificationParticipantsSheet(
        ticket: ticket,
        unpaid: unpaid,
        ref: ref,
        parentContext: context,
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
                    buildStatusBadge(context, ticket.status),
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
            title: const Text('SST / Tax'),
            trailing: Text(Money.format(ticket.tax, ticket.currency)),
          ),
        if (ticket.serviceCharge > 0)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Service Charge'),
            trailing: Text(Money.format(ticket.serviceCharge, ticket.currency)),
          ),
        if (ticket.tip != 0)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Rounding Adjustment'),
            trailing: Text(Money.format(ticket.tip, ticket.currency)),
          ),
        const Divider(height: 32),
        Row(
          children: [
            Text('Participants', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
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

class _SelectNotificationParticipantsSheet extends StatefulWidget {
  const _SelectNotificationParticipantsSheet({
    required this.ticket,
    required this.unpaid,
    required this.ref,
    required this.parentContext,
  });

  final Ticket ticket;
  final List<Participant> unpaid;
  final WidgetRef ref;
  final BuildContext parentContext;

  @override
  State<_SelectNotificationParticipantsSheet> createState() =>
      _SelectNotificationParticipantsSheetState();
}

class _SelectNotificationParticipantsSheetState
    extends State<_SelectNotificationParticipantsSheet> {
  late Set<String> _selectedEmails;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _selectedEmails = widget.unpaid.map((p) => p.email.toLowerCase()).toSet();
  }

  Future<void> _launchEmailApp(Participant p) async {
    final subject = 'Payment Reminder: ${widget.ticket.title.isEmpty ? 'Bill' : widget.ticket.title}';
    final body = NotificationService.formatEmailBreakdown(widget.ticket, p);

    final mailUri = Uri(
      scheme: 'mailto',
      path: p.email,
      queryParameters: {
        'subject': subject,
        'body': body,
      },
    );

    if (await canLaunchUrl(mailUri)) {
      await launchUrl(mailUri);
    }
  }

  Future<void> _send() async {
    if (_selectedEmails.isEmpty) return;

    setState(() => _sending = true);
    try {
      await widget.ref.read(ticketRepositoryProvider).queueNotifications(
            widget.ticket,
            selectedEmails: _selectedEmails.toList(),
          );

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(widget.parentContext).showSnackBar(
        SnackBar(
          content: Text(
            'Payment reminder sent to ${_selectedEmails.length} participant(s)!',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Select Participants to Notify', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Select who should receive payment reminders and email breakdowns.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 16),

              for (final p in widget.unpaid) ...[
                Builder(builder: (context) {
                  final emailNorm = p.email.toLowerCase();
                  final isSelected = _selectedEmails.contains(emailNorm);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (checked) {
                                  setState(() {
                                    if (checked == true) {
                                      _selectedEmails.add(emailNorm);
                                    } else {
                                      _selectedEmails.remove(emailNorm);
                                    }
                                  });
                                },
                              ),
                              CircleAvatar(
                                radius: 14,
                                child: Text(p.name.isEmpty ? '?' : p.name[0].toUpperCase()),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Text(p.email, style: theme.textTheme.bodySmall),
                                  ],
                                ),
                              ),
                              Text(
                                Money.format(p.share, widget.ticket.currency),
                                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                icon: const Icon(Icons.copy, size: 16),
                                label: const Text('Copy Text'),
                                onPressed: () {
                                  final text = NotificationService.formatEmailBreakdown(widget.ticket, p);
                                  Clipboard.setData(ClipboardData(text: text));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Copied email text for ${p.name}')),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                icon: const Icon(Icons.mail_outline, size: 16),
                                label: const Text('Open Email App'),
                                onPressed: () => _launchEmailApp(p),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _selectedEmails.isEmpty || _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _sending
                      ? 'Sending...'
                      : 'Send Reminders (${_selectedEmails.length})',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
