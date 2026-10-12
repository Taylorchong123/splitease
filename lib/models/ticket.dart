import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/money.dart';

enum TicketStatus { draft, open, partiallyPaid, settled }

class TicketItem {
  const TicketItem({
    required this.name,
    required this.amount,
    this.quantity = 1,
    this.assignedEmails = const [],
  });

  final String name;

  /// Unit price in minor units.
  final int amount;
  final int quantity;

  /// List of participant emails assigned to this item.
  /// If empty, the item is shared by all participants.
  final List<String> assignedEmails;

  int get total => amount * quantity;

  TicketItem copyWith({
    String? name,
    int? amount,
    int? quantity,
    List<String>? assignedEmails,
  }) =>
      TicketItem(
        name: name ?? this.name,
        amount: amount ?? this.amount,
        quantity: quantity ?? this.quantity,
        assignedEmails: assignedEmails ?? this.assignedEmails,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'amount': amount,
        'quantity': quantity,
        'assignedEmails': assignedEmails,
      };

  factory TicketItem.fromMap(Map<String, dynamic> m) => TicketItem(
        name: m['name'] as String,
        amount: (m['amount'] as num).toInt(),
        quantity: (m['quantity'] as num? ?? 1).toInt(),
        assignedEmails: (m['assignedEmails'] as List?)
                ?.map((e) => e.toString().toLowerCase())
                .toList() ??
            const [],
      );
}

class Participant {
  const Participant({
    required this.name,
    required this.email,
    required this.share,
    required this.paid,
    this.isOwner = false,
  });

  final String name;
  final String email;
  final int share; // minor units
  final bool paid;
  final bool isOwner;

  Participant copyWith({int? share, bool? paid}) => Participant(
        name: name,
        email: email,
        share: share ?? this.share,
        paid: paid ?? this.paid,
        isOwner: isOwner,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'email': email,
        'share': share,
        'paid': paid,
        'isOwner': isOwner,
      };

  factory Participant.fromMap(Map<String, dynamic> m) => Participant(
        name: m['name'] as String,
        email: m['email'] as String,
        share: (m['share'] as num).toInt(),
        paid: m['paid'] as bool,
        isOwner: m['isOwner'] as bool? ?? false,
      );
}

/// One bill = one ticket.
class Ticket {
  const Ticket({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.currency,
    required this.items,
    required this.tax,
    required this.tip,
    required this.participants,
    required this.status,
    required this.source,
    required this.createdAt,
    this.fxRates,
  });

  final String id;
  final String ownerId;
  final String title;
  final String currency;
  final List<TicketItem> items;
  final int tax;
  final int tip;
  final List<Participant> participants;
  final TicketStatus status;

  /// `manual` or `scan`.
  final String source;
  final DateTime createdAt;

  /// Exchange-rate snapshot (units per 1 USD) taken when the ticket was created,
  /// so historical tickets never change.
  final Map<String, double>? fxRates;

  int get subtotal => items.fold(0, (sum, i) => sum + i.total);
  int get total => subtotal + tax + tip;

  Ticket copyWith({
    List<Participant>? participants,
    TicketStatus? status,
  }) =>
      Ticket(
        id: id,
        ownerId: ownerId,
        title: title,
        currency: currency,
        items: items,
        tax: tax,
        tip: tip,
        participants: participants ?? this.participants,
        status: status ?? this.status,
        source: source,
        createdAt: createdAt,
        fxRates: fxRates,
      );

  /// Calculates each participant's share based on item assignments + proportional tax/tip.
  Ticket recalculated() {
    if (participants.isEmpty) return copyWith(status: TicketStatus.draft);

    final itemSubtotals = List<int>.filled(participants.length, 0);

    for (final item in items) {
      final assigned = item.assignedEmails.isEmpty
          ? participants
          : participants
              .where((p) => item.assignedEmails.contains(p.email.toLowerCase()))
              .toList();

      final effectiveAssigned = assigned.isEmpty ? participants : assigned;
      final shares = Money.splitEqually(item.total, effectiveAssigned.length);

      for (var i = 0; i < effectiveAssigned.length; i++) {
        final pEmail = effectiveAssigned[i].email.toLowerCase();
        final pIndex = participants.indexWhere((p) => p.email.toLowerCase() == pEmail);
        if (pIndex != -1) {
          itemSubtotals[pIndex] += shares[i];
        }
      }
    }

    final totalItemSubtotal = itemSubtotals.fold<int>(0, (a, b) => a + b);
    final totalTaxTip = tax + tip;
    List<int> totalShares;

    if (totalTaxTip != 0 && totalItemSubtotal > 0) {
      final taxTipShares = Money.allocate(totalTaxTip, itemSubtotals);
      totalShares = [
        for (var i = 0; i < participants.length; i++) itemSubtotals[i] + taxTipShares[i],
      ];
    } else if (totalItemSubtotal > 0) {
      totalShares = itemSubtotals;
    } else {
      totalShares = Money.splitEqually(total, participants.length);
    }

    final updated = [
      for (var i = 0; i < participants.length; i++)
        participants[i].copyWith(share: totalShares[i]),
    ];

    final others = updated.where((p) => !p.isOwner).toList();
    final newStatus = others.isEmpty
        ? TicketStatus.draft
        : others.every((p) => p.paid)
            ? TicketStatus.settled
            : others.any((p) => p.paid)
                ? TicketStatus.partiallyPaid
                : TicketStatus.open;

    return copyWith(participants: updated, status: newStatus);
  }

  Map<String, dynamic> toMap() => {
        'ownerId': ownerId,
        'title': title,
        'currency': currency,
        'items': items.map((i) => i.toMap()).toList(),
        'tax': tax,
        'tip': tip,
        'participants': participants.map((p) => p.toMap()).toList(),
        'memberEmails': participants.map((p) => p.email.toLowerCase()).toList(),
        'status': status.name,
        'source': source,
        'createdAt': Timestamp.fromDate(createdAt),
        'fxRates': fxRates,
      };

  factory Ticket.fromMap(String id, Map<String, dynamic> m) => Ticket(
        id: id,
        ownerId: m['ownerId'] as String,
        title: m['title'] as String,
        currency: m['currency'] as String,
        items: (m['items'] as List)
            .map((e) => TicketItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        tax: (m['tax'] as num).toInt(),
        tip: (m['tip'] as num).toInt(),
        participants: (m['participants'] as List)
            .map((e) => Participant.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        status: TicketStatus.values.byName(m['status'] as String),
        source: m['source'] as String,
        createdAt: (m['createdAt'] as Timestamp).toDate(),
        fxRates: (m['fxRates'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
}
