import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currencies.dart';
import '../../core/money.dart';
import '../../models/ticket.dart';
import '../../providers.dart';
import '../../services/bill_parser.dart';
import 'ticket_detail_screen.dart';

/// Creates a ticket from either a scanned bill ([initial]) or blank (manual).
class CreateTicketScreen extends ConsumerStatefulWidget {
  const CreateTicketScreen({super.key, this.initial, this.source = 'manual', this.rawText});

  final ParsedBill? initial;
  final String source;

  /// Text the OCR read from the photo (scan flow only), for troubleshooting.
  final String? rawText;

  @override
  ConsumerState<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends ConsumerState<CreateTicketScreen> {
  final _title = TextEditingController();
  final _customTaxController = TextEditingController();
  final _customServiceController = TextEditingController();

  late String _currency;
  late String _country;
  late String _taxType;
  late List<TicketItem> _items;
  late List<Participant> _participants;

  int _scannedTax = 0;
  int _scannedServiceCharge = 0;
  int _scannedRounding = 0;
  int? _printedTotal;

  /// 0.0 means "Use Scanned/Printed Exact Amount".
  /// Positive value means "Calculate using this % rate".
  double _taxRatePercent = 0.0;
  double _serviceRatePercent = 0.0;
  bool _isCustomTax = false;
  bool _isCustomService = false;

  String _splitPolicy = 'proportional';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    final ownerEmail = (user?.email?.isNotEmpty == true)
        ? user!.email!.toLowerCase()
        : 'me@splitease.local';
    final ownerName = (user?.displayName?.isNotEmpty == true) ? user!.displayName! : 'Me';

    _participants = [
      Participant(
        name: ownerName,
        email: ownerEmail,
        share: 0,
        paid: true, // owner already paid the venue
        isOwner: true,
      ),
    ];

    final p = widget.initial;
    _title.text = p?.merchant ?? '';
    _currency = p?.currency ?? 'MYR';
    _country = p?.country ?? 'MY';
    _taxType = p?.taxType ?? 'SST';
    _printedTotal = p?.total;
    _items = [...?p?.items];

    if (p != null) {
      _scannedTax = p.tax;
      _scannedServiceCharge = p.serviceCharge;
      _scannedRounding = p.rounding;

      if (p.discount > 0) {
        _items.add(TicketItem(
          name: 'Discount',
          amount: -p.discount,
          quantity: 1,
          itemType: ItemType.discount,
        ));
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _customTaxController.dispose();
    _customServiceController.dispose();
    super.dispose();
  }

  int get _subtotal => _items.fold(0, (s, i) => s + i.total);

  int get _calculatedTax {
    if (_taxRatePercent == 0.0 && _scannedTax > 0) {
      return _scannedTax;
    }
    return (_subtotal * _taxRatePercent / 100).round();
  }

  int get _calculatedServiceCharge {
    if (_serviceRatePercent == 0.0 && _scannedServiceCharge > 0) {
      return _scannedServiceCharge;
    }
    return (_subtotal * _serviceRatePercent / 100).round();
  }

  Ticket get _computedTicket {
    final user = FirebaseAuth.instance.currentUser;
    final ownerId = user?.uid ?? 'local';

    return Ticket(
      id: '',
      ownerId: ownerId,
      title: _title.text.trim(),
      currency: _currency,
      country: _country,
      taxType: _taxType,
      items: _items,
      tax: _calculatedTax,
      serviceCharge: _calculatedServiceCharge,
      tip: _scannedRounding,
      printedTotal: _printedTotal,
      splitPolicy: _splitPolicy,
      participants: _participants,
      status: TicketStatus.draft,
      source: widget.source,
      createdAt: DateTime.now(),
    ).recalculated();
  }

  Future<void> _addParticipant() async {
    final participant = await showDialog<Participant>(
      context: context,
      builder: (ctx) => const _AddParticipantDialog(),
    );
    if (participant == null) return;

    final existingIndex = _participants.indexWhere(
      (p) => p.email.toLowerCase() == participant.email.toLowerCase(),
    );
    if (existingIndex != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Participant with this email is already added')),
      );
      return;
    }

    setState(() {
      _participants.add(participant);
    });
  }

  void _removeParticipant(int index) {
    if (_participants[index].isOwner) return;
    final removedEmail = _participants[index].email.toLowerCase();

    setState(() {
      _participants.removeAt(index);
      _items = [
        for (final item in _items)
          item.copyWith(
            assignedEmails: [
              for (final e in item.assignedEmails)
                if (e.toLowerCase() != removedEmail) e,
            ],
          ),
      ];
    });
  }

  Future<void> _addItem() async {
    final item = await showDialog<TicketItem>(
      context: context,
      builder: (ctx) => _AddItemDialog(
        currency: _currency,
        participants: _participants,
      ),
    );

    if (item != null) {
      setState(() => _items.add(item));
    }
  }

  void _toggleAssignment(int itemIndex, String email) {
    final normEmail = email.toLowerCase();
    final current = List<String>.from(_items[itemIndex].assignedEmails);

    if (current.contains(normEmail)) {
      current.remove(normEmail);
    } else {
      current.add(normEmail);
    }

    setState(() {
      _items[itemIndex] = _items[itemIndex].copyWith(assignedEmails: current);
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Add at least one item')));
      return;
    }
    setState(() => _saving = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;

      Map<String, double>? rates;
      try {
        rates = await ref.read(currencyServiceProvider).latestRates();
      } catch (_) {
        // Offline / provider down
      }

      final ticketToSave = Ticket(
        id: '',
        ownerId: user.uid,
        title: _title.text.trim().isEmpty ? 'Bill' : _title.text.trim(),
        currency: _currency,
        country: _country,
        taxType: _taxType,
        items: _items,
        tax: _calculatedTax,
        serviceCharge: _calculatedServiceCharge,
        tip: _scannedRounding,
        printedTotal: _printedTotal,
        splitPolicy: _splitPolicy,
        participants: _participants,
        status: TicketStatus.draft,
        source: widget.source,
        createdAt: DateTime.now(),
        fxRates: rates,
      ).recalculated();

      final id = await ref.read(ticketRepositoryProvider).create(ticketToSave);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => TicketDetailScreen(ticketId: id)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ticket = _computedTicket;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.source == 'scan' ? 'Review scanned bill' : 'New bill'),
        actions: [
          if (widget.rawText != null)
            IconButton(
              tooltip: 'View scanned text',
              icon: const Icon(Icons.text_snippet_outlined),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Text read from photo'),
                  content: SingleChildScrollView(child: SelectableText(widget.rawText!)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
                  ],
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ticket.reconciliationDiscrepancy != 0)
            Card(
              color: Colors.amber[100],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.amber),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Reconciliation Warning: Printed total (${Money.format(ticket.printedTotal!, _currency)}) differs from computed total (${Money.format(ticket.computedTotal, _currency)}) by ${Money.format(ticket.reconciliationDiscrepancy.abs(), _currency)}.',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),

          // --- General Info ---
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title (e.g. Team dinner)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [
                    for (final c in supportedCurrencies)
                      DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _currency = v ?? _currency),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _country,
                  decoration: const InputDecoration(labelText: 'Region Rules'),
                  items: const [
                    DropdownMenuItem(
                      value: 'MY',
                      child: Text('🇲🇾 Malaysia', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'SG',
                      child: Text('🇸🇬 Singapore', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      _country = v;
                      if (v == 'SG') {
                        _currency = 'SGD';
                        _taxType = 'GST';
                        _taxRatePercent = 0.0;
                      } else {
                        _currency = 'MYR';
                        _taxType = 'SST';
                        _taxRatePercent = 0.0;
                      }
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // --- SECTION 1: PARTICIPANTS (FIRST) ---
          Row(
            children: [
              Text('1. Participants', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addParticipant,
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Add participant'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Add everyone sharing this bill first so you can assign food items.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < ticket.participants.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      child: Text(
                        ticket.participants[i].name.isEmpty
                            ? '?'
                            : ticket.participants[i].name[0].toUpperCase(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    title: Text(
                      ticket.participants[i].isOwner
                          ? '${ticket.participants[i].name} (Payer / Me)'
                          : ticket.participants[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(ticket.participants[i].email),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Money.format(ticket.participants[i].share, _currency),
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (!ticket.participants[i].isOwner)
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => _removeParticipant(i),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // --- SECTION 2: ITEMS & ASSIGNMENT ---
          Row(
            children: [
              Text('2. Food Items & Assignment', style: theme.textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
              ),
            ],
          ),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No items added yet.'),
            ),

          for (var i = 0; i < _items.length; i++) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _items[i].name,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  decoration: _items[i].isVoidOrComplimentary
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              Text(
                                '${_items[i].quantity} × ${Money.format(_items[i].amount, _currency)}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Money.format(_items[i].total, _currency),
                          style: theme.textTheme.titleMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => setState(() => _items.removeAt(i)),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Text(
                      'Assign to:',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final p in _participants) ...[
                          Builder(builder: (context) {
                            final isAssigned = _items[i]
                                .assignedEmails
                                .contains(p.email.toLowerCase());
                            return FilterChip(
                              label: Text(p.name),
                              selected: isAssigned,
                              onSelected: (_) => _toggleAssignment(i, p.email),
                            );
                          }),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _items[i].assignedEmails.isEmpty
                          ? '• Shared equally by everyone'
                          : '• Assigned to ${_items[i].assignedEmails.length} participant(s)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // --- SECTION 3: TAX & SERVICE CHARGE SETTINGS ---
          Text('3. Tax & Service Charge Settings', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Charge Allocation Policy', style: theme.textTheme.labelMedium),
                    const SizedBox(height: 4),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'proportional', label: Text('Proportional')),
                        ButtonSegment(value: 'equal', label: Text('Split Equally')),
                      ],
                      selected: {_splitPolicy},
                      onSelectionChanged: (set) {
                        setState(() => _splitPolicy = set.first);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // SST / Tax Rate Selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$_taxType / Tax Rate', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(_scannedTax > 0 ? 'Scanned (${Money.format(_scannedTax, _currency)})' : '0%'),
                    selected: !_isCustomTax && _taxRatePercent == 0.0,
                    onSelected: (_) => setState(() {
                      _isCustomTax = false;
                      _taxRatePercent = 0.0;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('6% SST'),
                    selected: !_isCustomTax && _taxRatePercent == 6.0,
                    onSelected: (_) => setState(() {
                      _isCustomTax = false;
                      _taxRatePercent = 6.0;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('8% SST'),
                    selected: !_isCustomTax && _taxRatePercent == 8.0,
                    onSelected: (_) => setState(() {
                      _isCustomTax = false;
                      _taxRatePercent = 8.0;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('9% GST'),
                    selected: !_isCustomTax && _taxRatePercent == 9.0,
                    onSelected: (_) => setState(() {
                      _isCustomTax = false;
                      _taxRatePercent = 9.0;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('10%'),
                    selected: !_isCustomTax && _taxRatePercent == 10.0,
                    onSelected: (_) => setState(() {
                      _isCustomTax = false;
                      _taxRatePercent = 10.0;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Custom %'),
                    selected: _isCustomTax,
                    onSelected: (_) => setState(() {
                      _isCustomTax = true;
                    }),
                  ),
                ],
              ),
              if (_isCustomTax) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customTaxController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Custom Tax Rate (%)',
                    suffixText: '%',
                  ),
                  onChanged: (v) {
                    final rate = double.tryParse(v) ?? 0.0;
                    setState(() => _taxRatePercent = rate);
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Service Charge Rate Selector
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Service Charge Rate', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(_scannedServiceCharge > 0 ? 'Scanned (${Money.format(_scannedServiceCharge, _currency)})' : '0%'),
                    selected: !_isCustomService && _serviceRatePercent == 0.0,
                    onSelected: (_) => setState(() {
                      _isCustomService = false;
                      _serviceRatePercent = 0.0;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('5%'),
                    selected: !_isCustomService && _serviceRatePercent == 5.0,
                    onSelected: (_) => setState(() {
                      _isCustomService = false;
                      _serviceRatePercent = 5.0;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('10%'),
                    selected: !_isCustomService && _serviceRatePercent == 10.0,
                    onSelected: (_) => setState(() {
                      _isCustomService = false;
                      _serviceRatePercent = 10.0;
                    }),
                  ),
                  ChoiceChip(
                    label: const Text('Custom %'),
                    selected: _isCustomService,
                    onSelected: (_) => setState(() {
                      _isCustomService = true;
                    }),
                  ),
                ],
              ),
              if (_isCustomService) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customServiceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Custom Service Charge Rate (%)',
                    suffixText: '%',
                  ),
                  onChanged: (v) {
                    final rate = double.tryParse(v) ?? 0.0;
                    setState(() => _serviceRatePercent = rate);
                  },
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // --- SUMMARY BREAKDOWN CARD ---
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('Food Subtotal'),
                      const Spacer(),
                      Text(Money.format(ticket.subtotal, _currency)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('$_taxType Tax ${!_isCustomTax && _taxRatePercent == 0.0 && _scannedTax > 0 ? '(Scanned)' : '(${_taxRatePercent.toStringAsFixed(0)}%)'} [Read-only]'),
                      const Spacer(),
                      Text(Money.format(ticket.tax, _currency)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('Service Charge ${!_isCustomService && _serviceRatePercent == 0.0 && _scannedServiceCharge > 0 ? '(Scanned)' : '(${_serviceRatePercent.toStringAsFixed(0)}%)'} [Read-only]'),
                      const Spacer(),
                      Text(Money.format(ticket.serviceCharge, _currency)),
                    ],
                  ),
                  if (ticket.tip != 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Text('Rounding Adjustment [Last Line]'),
                        const Spacer(),
                        Text(Money.format(ticket.tip, _currency)),
                      ],
                    ),
                  ],
                  const Divider(height: 20),
                  Row(
                    children: [
                      Text('Grand Total', style: theme.textTheme.titleMedium),
                      const Spacer(),
                      Text(
                        Money.format(ticket.total, _currency),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Create ticket'),
          ),
        ],
      ),
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
              decoration: const InputDecoration(labelText: 'Name (e.g. Alice)'),
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

class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog({
    required this.currency,
    required this.participants,
  });

  final String currency;
  final List<Participant> participants;

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final Set<String> _selectedEmails = {};

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _qty.dispose();
    super.dispose();
  }

  void _submit() {
    final minor = Money.parse(_amount.text, widget.currency);
    final quantity = int.tryParse(_qty.text) ?? 1;
    final itemName = _name.text.trim();

    if (itemName.isEmpty || minor == null) return;

    Navigator.pop(
      context,
      TicketItem(
        name: itemName,
        amount: minor,
        quantity: quantity < 1 ? 1 : quantity,
        assignedEmails: _selectedEmails.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.sentences,
              autofocus: true,
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Unit price'),
            ),
            TextField(
              controller: _qty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            if (widget.participants.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Assign to:', style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final p in widget.participants)
                    FilterChip(
                      label: Text(p.name),
                      selected: _selectedEmails.contains(p.email.toLowerCase()),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedEmails.add(p.email.toLowerCase());
                          } else {
                            _selectedEmails.remove(p.email.toLowerCase());
                          }
                        });
                      },
                    ),
                ],
              ),
            ],
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
